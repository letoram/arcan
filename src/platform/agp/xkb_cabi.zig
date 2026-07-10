// Auto-generated replacement for `@cImport({xkbcommon/xkbcommon.h,
// xkbcommon/xkbcommon-x11.h, xkbcommon/xkbcommon-compose.h})` used by
// vk_xcb.zig. Same setup as xcb_cabi.zig — see its header for details.
// Regenerate with:
//
//   echo '#include <xkbcommon/xkbcommon.h>' > /tmp/h.h
//   echo '#include <xkbcommon/xkbcommon-x11.h>' >> /tmp/h.h
//   echo '#include <xkbcommon/xkbcommon-compose.h>' >> /tmp/h.h
//   /usr/local/zig-aarch64-linux-0.15.2/zig translate-c -I /usr/include /tmp/h.h \
//     > src/platform/agp/xkb_cabi.zig
//   # then paste this 9-line comment block back at the top.

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
pub const __nlink_t = c_uint;
pub const __off_t = c_long;
pub const __off64_t = c_long;
pub const __pid_t = c_int;
pub const __fsid_t = extern struct {
    __val: [2]c_int = @import("std").mem.zeroes([2]c_int),
};
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
pub const __timer_t = ?*anyopaque;
pub const __blksize_t = c_int;
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
pub const struct___va_list_1 = extern struct {
    __stack: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __vr_top: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __gr_offs: c_int = @import("std").mem.zeroes(c_int),
    __vr_offs: c_int = @import("std").mem.zeroes(c_int),
};
pub const __builtin_va_list = struct___va_list_1;
pub const __gnuc_va_list = __builtin_va_list;
const union_unnamed_2 = extern union {
    __wch: c_uint,
    __wchb: [4]u8,
};
pub const __mbstate_t = extern struct {
    __count: c_int = @import("std").mem.zeroes(c_int),
    __value: union_unnamed_2 = @import("std").mem.zeroes(union_unnamed_2),
};
pub const struct__G_fpos_t = extern struct {
    __pos: __off_t = @import("std").mem.zeroes(__off_t),
    __state: __mbstate_t = @import("std").mem.zeroes(__mbstate_t),
};
pub const __fpos_t = struct__G_fpos_t;
pub const struct__G_fpos64_t = extern struct {
    __pos: __off64_t = @import("std").mem.zeroes(__off64_t),
    __state: __mbstate_t = @import("std").mem.zeroes(__mbstate_t),
};
pub const __fpos64_t = struct__G_fpos64_t;
pub const struct__IO_marker = opaque {};
// /usr/include/bits/types/struct_FILE.h:75:7: warning: struct demoted to opaque type - has bitfield
pub const struct__IO_FILE = opaque {};
pub const __FILE = struct__IO_FILE;
pub const FILE = struct__IO_FILE;
pub const struct__IO_codecvt = opaque {};
pub const struct__IO_wide_data = opaque {};
pub const _IO_lock_t = anyopaque;
pub const cookie_read_function_t = fn (?*anyopaque, [*c]u8, usize) callconv(.c) __ssize_t;
pub const cookie_write_function_t = fn (?*anyopaque, [*c]const u8, usize) callconv(.c) __ssize_t;
pub const cookie_seek_function_t = fn (?*anyopaque, [*c]__off64_t, c_int) callconv(.c) c_int;
pub const cookie_close_function_t = fn (?*anyopaque) callconv(.c) c_int;
pub const struct__IO_cookie_io_functions_t = extern struct {
    read: ?*const cookie_read_function_t = @import("std").mem.zeroes(?*const cookie_read_function_t),
    write: ?*const cookie_write_function_t = @import("std").mem.zeroes(?*const cookie_write_function_t),
    seek: ?*const cookie_seek_function_t = @import("std").mem.zeroes(?*const cookie_seek_function_t),
    close: ?*const cookie_close_function_t = @import("std").mem.zeroes(?*const cookie_close_function_t),
};
pub const cookie_io_functions_t = struct__IO_cookie_io_functions_t;
pub const va_list = __gnuc_va_list;
pub const off_t = __off_t;
pub const fpos_t = __fpos_t;
pub extern var stdin: ?*FILE;
pub extern var stdout: ?*FILE;
pub extern var stderr: ?*FILE;
pub extern fn remove(__filename: [*c]const u8) c_int;
pub extern fn rename(__old: [*c]const u8, __new: [*c]const u8) c_int;
pub extern fn renameat(__oldfd: c_int, __old: [*c]const u8, __newfd: c_int, __new: [*c]const u8) c_int;
pub extern fn fclose(__stream: ?*FILE) c_int;
pub extern fn tmpfile() ?*FILE;
pub extern fn tmpnam([*c]u8) [*c]u8;
pub extern fn tmpnam_r(__s: [*c]u8) [*c]u8;
pub extern fn tempnam(__dir: [*c]const u8, __pfx: [*c]const u8) [*c]u8;
pub extern fn fflush(__stream: ?*FILE) c_int;
pub extern fn fflush_unlocked(__stream: ?*FILE) c_int;
pub extern fn fopen(__filename: [*c]const u8, __modes: [*c]const u8) ?*FILE;
pub extern fn freopen(noalias __filename: [*c]const u8, noalias __modes: [*c]const u8, noalias __stream: ?*FILE) ?*FILE;
pub extern fn fdopen(__fd: c_int, __modes: [*c]const u8) ?*FILE;
pub extern fn fopencookie(noalias __magic_cookie: ?*anyopaque, noalias __modes: [*c]const u8, __io_funcs: cookie_io_functions_t) ?*FILE;
pub extern fn fmemopen(__s: ?*anyopaque, __len: usize, __modes: [*c]const u8) ?*FILE;
pub extern fn open_memstream(__bufloc: [*c][*c]u8, __sizeloc: [*c]usize) ?*FILE;
pub extern fn setbuf(noalias __stream: ?*FILE, noalias __buf: [*c]u8) void;
pub extern fn setvbuf(noalias __stream: ?*FILE, noalias __buf: [*c]u8, __modes: c_int, __n: usize) c_int;
pub extern fn setbuffer(noalias __stream: ?*FILE, noalias __buf: [*c]u8, __size: usize) void;
pub extern fn setlinebuf(__stream: ?*FILE) void;
pub extern fn fprintf(noalias __stream: ?*FILE, noalias __format: [*c]const u8, ...) c_int;
pub extern fn printf(__format: [*c]const u8, ...) c_int;
pub extern fn sprintf(noalias __s: [*c]u8, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vfprintf(noalias __s: ?*FILE, noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn vprintf(noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn vsprintf(noalias __s: [*c]u8, noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn snprintf(noalias __s: [*c]u8, __maxlen: c_ulong, noalias __format: [*c]const u8, ...) c_int;
pub extern fn vsnprintf(noalias __s: [*c]u8, __maxlen: c_ulong, noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn vasprintf(noalias __ptr: [*c][*c]u8, noalias __f: [*c]const u8, __arg: __gnuc_va_list) c_int;
pub extern fn __asprintf(noalias __ptr: [*c][*c]u8, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn asprintf(noalias __ptr: [*c][*c]u8, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn vdprintf(__fd: c_int, noalias __fmt: [*c]const u8, __arg: __gnuc_va_list) c_int;
pub extern fn dprintf(__fd: c_int, noalias __fmt: [*c]const u8, ...) c_int;
pub extern fn fscanf(noalias __stream: ?*FILE, noalias __format: [*c]const u8, ...) c_int;
pub extern fn scanf(noalias __format: [*c]const u8, ...) c_int;
pub extern fn sscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, ...) c_int;
pub const _Float128 = c_longdouble;
pub const _Float32 = f32;
pub const _Float64 = f64;
pub const _Float32x = f64;
pub const _Float64x = c_longdouble;
pub extern fn vfscanf(noalias __s: ?*FILE, noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn vscanf(noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn vsscanf(noalias __s: [*c]const u8, noalias __format: [*c]const u8, __arg: __builtin_va_list) c_int;
pub extern fn fgetc(__stream: ?*FILE) c_int;
pub extern fn getc(__stream: ?*FILE) c_int;
pub extern fn getchar() c_int;
pub extern fn getc_unlocked(__stream: ?*FILE) c_int;
pub extern fn getchar_unlocked() c_int;
pub extern fn fgetc_unlocked(__stream: ?*FILE) c_int;
pub extern fn fputc(__c: c_int, __stream: ?*FILE) c_int;
pub extern fn putc(__c: c_int, __stream: ?*FILE) c_int;
pub extern fn putchar(__c: c_int) c_int;
pub extern fn fputc_unlocked(__c: c_int, __stream: ?*FILE) c_int;
pub extern fn putc_unlocked(__c: c_int, __stream: ?*FILE) c_int;
pub extern fn putchar_unlocked(__c: c_int) c_int;
pub extern fn getw(__stream: ?*FILE) c_int;
pub extern fn putw(__w: c_int, __stream: ?*FILE) c_int;
pub extern fn fgets(noalias __s: [*c]u8, __n: c_int, noalias __stream: ?*FILE) [*c]u8;
pub extern fn __getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: ?*FILE) __ssize_t;
pub extern fn getdelim(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, __delimiter: c_int, noalias __stream: ?*FILE) __ssize_t;
pub extern fn getline(noalias __lineptr: [*c][*c]u8, noalias __n: [*c]usize, noalias __stream: ?*FILE) __ssize_t;
pub extern fn fputs(noalias __s: [*c]const u8, noalias __stream: ?*FILE) c_int;
pub extern fn puts(__s: [*c]const u8) c_int;
pub extern fn ungetc(__c: c_int, __stream: ?*FILE) c_int;
pub extern fn fread(__ptr: ?*anyopaque, __size: c_ulong, __n: c_ulong, __stream: ?*FILE) c_ulong;
pub extern fn fwrite(__ptr: ?*const anyopaque, __size: c_ulong, __n: c_ulong, __s: ?*FILE) c_ulong;
pub extern fn fread_unlocked(noalias __ptr: ?*anyopaque, __size: usize, __n: usize, noalias __stream: ?*FILE) usize;
pub extern fn fwrite_unlocked(noalias __ptr: ?*const anyopaque, __size: usize, __n: usize, noalias __stream: ?*FILE) usize;
pub extern fn fseek(__stream: ?*FILE, __off: c_long, __whence: c_int) c_int;
pub extern fn ftell(__stream: ?*FILE) c_long;
pub extern fn rewind(__stream: ?*FILE) void;
pub extern fn fseeko(__stream: ?*FILE, __off: __off_t, __whence: c_int) c_int;
pub extern fn ftello(__stream: ?*FILE) __off_t;
pub extern fn fgetpos(noalias __stream: ?*FILE, noalias __pos: [*c]fpos_t) c_int;
pub extern fn fsetpos(__stream: ?*FILE, __pos: [*c]const fpos_t) c_int;
pub extern fn clearerr(__stream: ?*FILE) void;
pub extern fn feof(__stream: ?*FILE) c_int;
pub extern fn ferror(__stream: ?*FILE) c_int;
pub extern fn clearerr_unlocked(__stream: ?*FILE) void;
pub extern fn feof_unlocked(__stream: ?*FILE) c_int;
pub extern fn ferror_unlocked(__stream: ?*FILE) c_int;
pub extern fn perror(__s: [*c]const u8) void;
pub extern fn fileno(__stream: ?*FILE) c_int;
pub extern fn fileno_unlocked(__stream: ?*FILE) c_int;
pub extern fn pclose(__stream: ?*FILE) c_int;
pub extern fn popen(__command: [*c]const u8, __modes: [*c]const u8) ?*FILE;
pub extern fn ctermid(__s: [*c]u8) [*c]u8;
pub extern fn flockfile(__stream: ?*FILE) void;
pub extern fn ftrylockfile(__stream: ?*FILE) c_int;
pub extern fn funlockfile(__stream: ?*FILE) void;
pub extern fn __uflow(?*FILE) c_int;
pub extern fn __overflow(?*FILE, c_int) c_int;
pub const struct_xkb_context = opaque {};
pub const struct_xkb_keymap = opaque {};
pub const struct_xkb_state = opaque {};
pub const xkb_keycode_t = u32;
pub const xkb_keysym_t = u32;
pub const xkb_layout_index_t = u32;
pub const xkb_layout_mask_t = u32;
pub const xkb_level_index_t = u32;
pub const xkb_mod_index_t = u32;
pub const xkb_mod_mask_t = u32;
pub const xkb_led_index_t = u32;
pub const xkb_led_mask_t = u32;
pub const struct_xkb_rmlvo_builder = opaque {};
pub const XKB_RMLVO_BUILDER_NO_FLAGS: c_int = 0;
pub const enum_xkb_rmlvo_builder_flags = c_uint;
pub extern fn xkb_rmlvo_builder_new(context: ?*struct_xkb_context, rules: [*c]const u8, model: [*c]const u8, flags: enum_xkb_rmlvo_builder_flags) ?*struct_xkb_rmlvo_builder;
pub extern fn xkb_rmlvo_builder_append_layout(rmlvo: ?*struct_xkb_rmlvo_builder, layout: [*c]const u8, variant: [*c]const u8, options: [*c]const [*c]const u8, options_len: usize) bool;
pub extern fn xkb_rmlvo_builder_append_option(rmlvo: ?*struct_xkb_rmlvo_builder, option: [*c]const u8) bool;
pub extern fn xkb_rmlvo_builder_ref(rmlvo: ?*struct_xkb_rmlvo_builder) ?*struct_xkb_rmlvo_builder;
pub extern fn xkb_rmlvo_builder_unref(rmlvo: ?*struct_xkb_rmlvo_builder) void;
pub const struct_xkb_rule_names = extern struct {
    rules: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    model: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    layout: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    variant: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
    options: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
};
pub const struct_xkb_component_names = extern struct {
    keycodes: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    compatibility: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    geometry: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    symbols: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    types: [*c]u8 = @import("std").mem.zeroes([*c]u8),
};
pub extern fn xkb_components_names_from_rules(context: ?*struct_xkb_context, rmlvo_in: [*c]const struct_xkb_rule_names, rmlvo_out: [*c]struct_xkb_rule_names, components_out: [*c]struct_xkb_component_names) bool;
pub extern fn xkb_keysym_get_name(keysym: xkb_keysym_t, buffer: [*c]u8, size: usize) c_int;
pub const XKB_KEYSYM_NO_FLAGS: c_int = 0;
pub const XKB_KEYSYM_CASE_INSENSITIVE: c_int = 1;
pub const enum_xkb_keysym_flags = c_uint;
pub extern fn xkb_keysym_from_name(name: [*c]const u8, flags: enum_xkb_keysym_flags) xkb_keysym_t;
pub extern fn xkb_keysym_to_utf8(keysym: xkb_keysym_t, buffer: [*c]u8, size: usize) c_int;
pub extern fn xkb_keysym_to_utf32(keysym: xkb_keysym_t) u32;
pub extern fn xkb_utf32_to_keysym(ucs: u32) xkb_keysym_t;
pub extern fn xkb_keysym_to_upper(ks: xkb_keysym_t) xkb_keysym_t;
pub extern fn xkb_keysym_to_lower(ks: xkb_keysym_t) xkb_keysym_t;
pub const XKB_CONTEXT_NO_FLAGS: c_int = 0;
pub const XKB_CONTEXT_NO_DEFAULT_INCLUDES: c_int = 1;
pub const XKB_CONTEXT_NO_ENVIRONMENT_NAMES: c_int = 2;
pub const XKB_CONTEXT_NO_SECURE_GETENV: c_int = 4;
pub const enum_xkb_context_flags = c_uint;
pub extern fn xkb_context_new(flags: enum_xkb_context_flags) ?*struct_xkb_context;
pub extern fn xkb_context_ref(context: ?*struct_xkb_context) ?*struct_xkb_context;
pub extern fn xkb_context_unref(context: ?*struct_xkb_context) void;
pub extern fn xkb_context_set_user_data(context: ?*struct_xkb_context, user_data: ?*anyopaque) void;
pub extern fn xkb_context_get_user_data(context: ?*struct_xkb_context) ?*anyopaque;
pub extern fn xkb_context_include_path_append(context: ?*struct_xkb_context, path: [*c]const u8) c_int;
pub extern fn xkb_context_include_path_append_default(context: ?*struct_xkb_context) c_int;
pub extern fn xkb_context_include_path_reset_defaults(context: ?*struct_xkb_context) c_int;
pub extern fn xkb_context_include_path_clear(context: ?*struct_xkb_context) void;
pub extern fn xkb_context_num_include_paths(context: ?*struct_xkb_context) c_uint;
pub extern fn xkb_context_include_path_get(context: ?*struct_xkb_context, index: c_uint) [*c]const u8;
pub const XKB_LOG_LEVEL_CRITICAL: c_int = 10;
pub const XKB_LOG_LEVEL_ERROR: c_int = 20;
pub const XKB_LOG_LEVEL_WARNING: c_int = 30;
pub const XKB_LOG_LEVEL_INFO: c_int = 40;
pub const XKB_LOG_LEVEL_DEBUG: c_int = 50;
pub const enum_xkb_log_level = c_uint;
pub extern fn xkb_context_set_log_level(context: ?*struct_xkb_context, level: enum_xkb_log_level) void;
pub extern fn xkb_context_get_log_level(context: ?*struct_xkb_context) enum_xkb_log_level;
pub extern fn xkb_context_set_log_verbosity(context: ?*struct_xkb_context, verbosity: c_int) void;
pub extern fn xkb_context_get_log_verbosity(context: ?*struct_xkb_context) c_int;
pub extern fn xkb_context_set_log_fn(context: ?*struct_xkb_context, log_fn: ?*const fn (?*struct_xkb_context, enum_xkb_log_level, [*c]const u8, va_list) callconv(.c) void) void;
pub const XKB_KEYMAP_COMPILE_NO_FLAGS: c_int = 0;
pub const enum_xkb_keymap_compile_flags = c_uint;
pub const XKB_KEYMAP_FORMAT_TEXT_V1: c_int = 1;
pub const XKB_KEYMAP_FORMAT_TEXT_V2: c_int = 2;
pub const enum_xkb_keymap_format = c_uint;
pub extern fn xkb_keymap_new_from_rmlvo(rmlvo: ?*const struct_xkb_rmlvo_builder, format: enum_xkb_keymap_format, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_new_from_names(context: ?*struct_xkb_context, names: [*c]const struct_xkb_rule_names, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_new_from_names2(context: ?*struct_xkb_context, names: [*c]const struct_xkb_rule_names, format: enum_xkb_keymap_format, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_new_from_file(context: ?*struct_xkb_context, file: ?*FILE, format: enum_xkb_keymap_format, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_new_from_string(context: ?*struct_xkb_context, string: [*c]const u8, format: enum_xkb_keymap_format, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_new_from_buffer(context: ?*struct_xkb_context, buffer: [*c]const u8, length: usize, format: enum_xkb_keymap_format, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_ref(keymap: ?*struct_xkb_keymap) ?*struct_xkb_keymap;
pub extern fn xkb_keymap_unref(keymap: ?*struct_xkb_keymap) void;
pub extern fn xkb_keymap_get_as_string(keymap: ?*struct_xkb_keymap, format: enum_xkb_keymap_format) [*c]u8;
pub extern fn xkb_keymap_min_keycode(keymap: ?*struct_xkb_keymap) xkb_keycode_t;
pub extern fn xkb_keymap_max_keycode(keymap: ?*struct_xkb_keymap) xkb_keycode_t;
pub const xkb_keymap_key_iter_t = ?*const fn (?*struct_xkb_keymap, xkb_keycode_t, ?*anyopaque) callconv(.c) void;
pub extern fn xkb_keymap_key_for_each(keymap: ?*struct_xkb_keymap, iter: xkb_keymap_key_iter_t, data: ?*anyopaque) void;
pub extern fn xkb_keymap_key_get_name(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t) [*c]const u8;
pub extern fn xkb_keymap_key_by_name(keymap: ?*struct_xkb_keymap, name: [*c]const u8) xkb_keycode_t;
pub extern fn xkb_keymap_num_mods(keymap: ?*struct_xkb_keymap) xkb_mod_index_t;
pub extern fn xkb_keymap_mod_get_name(keymap: ?*struct_xkb_keymap, idx: xkb_mod_index_t) [*c]const u8;
pub extern fn xkb_keymap_mod_get_index(keymap: ?*struct_xkb_keymap, name: [*c]const u8) xkb_mod_index_t;
pub extern fn xkb_keymap_mod_get_mask(keymap: ?*struct_xkb_keymap, name: [*c]const u8) xkb_mod_mask_t;
pub extern fn xkb_keymap_mod_get_mask2(keymap: ?*struct_xkb_keymap, idx: xkb_mod_index_t) xkb_mod_mask_t;
pub extern fn xkb_keymap_num_layouts(keymap: ?*struct_xkb_keymap) xkb_layout_index_t;
pub extern fn xkb_keymap_layout_get_name(keymap: ?*struct_xkb_keymap, idx: xkb_layout_index_t) [*c]const u8;
pub extern fn xkb_keymap_layout_get_index(keymap: ?*struct_xkb_keymap, name: [*c]const u8) xkb_layout_index_t;
pub extern fn xkb_keymap_num_leds(keymap: ?*struct_xkb_keymap) xkb_led_index_t;
pub extern fn xkb_keymap_led_get_name(keymap: ?*struct_xkb_keymap, idx: xkb_led_index_t) [*c]const u8;
pub extern fn xkb_keymap_led_get_index(keymap: ?*struct_xkb_keymap, name: [*c]const u8) xkb_led_index_t;
pub extern fn xkb_keymap_num_layouts_for_key(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t) xkb_layout_index_t;
pub extern fn xkb_keymap_num_levels_for_key(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t, layout: xkb_layout_index_t) xkb_level_index_t;
pub extern fn xkb_keymap_key_get_mods_for_level(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t, layout: xkb_layout_index_t, level: xkb_level_index_t, masks_out: [*c]xkb_mod_mask_t, masks_size: usize) usize;
pub extern fn xkb_keymap_key_get_syms_by_level(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t, layout: xkb_layout_index_t, level: xkb_level_index_t, syms_out: [*c][*c]const xkb_keysym_t) c_int;
pub extern fn xkb_keymap_key_repeats(keymap: ?*struct_xkb_keymap, key: xkb_keycode_t) c_int;
pub extern fn xkb_state_new(keymap: ?*struct_xkb_keymap) ?*struct_xkb_state;
pub extern fn xkb_state_ref(state: ?*struct_xkb_state) ?*struct_xkb_state;
pub extern fn xkb_state_unref(state: ?*struct_xkb_state) void;
pub extern fn xkb_state_get_keymap(state: ?*struct_xkb_state) ?*struct_xkb_keymap;
pub const XKB_KEY_UP: c_int = 0;
pub const XKB_KEY_DOWN: c_int = 1;
pub const enum_xkb_key_direction = c_uint;
pub const XKB_STATE_MODS_DEPRESSED: c_int = 1;
pub const XKB_STATE_MODS_LATCHED: c_int = 2;
pub const XKB_STATE_MODS_LOCKED: c_int = 4;
pub const XKB_STATE_MODS_EFFECTIVE: c_int = 8;
pub const XKB_STATE_LAYOUT_DEPRESSED: c_int = 16;
pub const XKB_STATE_LAYOUT_LATCHED: c_int = 32;
pub const XKB_STATE_LAYOUT_LOCKED: c_int = 64;
pub const XKB_STATE_LAYOUT_EFFECTIVE: c_int = 128;
pub const XKB_STATE_LEDS: c_int = 256;
pub const enum_xkb_state_component = c_uint;
pub extern fn xkb_state_update_key(state: ?*struct_xkb_state, key: xkb_keycode_t, direction: enum_xkb_key_direction) enum_xkb_state_component;
pub extern fn xkb_state_update_latched_locked(state: ?*struct_xkb_state, affect_latched_mods: xkb_mod_mask_t, latched_mods: xkb_mod_mask_t, affect_latched_layout: bool, latched_layout: i32, affect_locked_mods: xkb_mod_mask_t, locked_mods: xkb_mod_mask_t, affect_locked_layout: bool, locked_layout: i32) enum_xkb_state_component;
pub extern fn xkb_state_update_mask(state: ?*struct_xkb_state, depressed_mods: xkb_mod_mask_t, latched_mods: xkb_mod_mask_t, locked_mods: xkb_mod_mask_t, depressed_layout: xkb_layout_index_t, latched_layout: xkb_layout_index_t, locked_layout: xkb_layout_index_t) enum_xkb_state_component;
pub extern fn xkb_state_key_get_syms(state: ?*struct_xkb_state, key: xkb_keycode_t, syms_out: [*c][*c]const xkb_keysym_t) c_int;
pub extern fn xkb_state_key_get_utf8(state: ?*struct_xkb_state, key: xkb_keycode_t, buffer: [*c]u8, size: usize) c_int;
pub extern fn xkb_state_key_get_utf32(state: ?*struct_xkb_state, key: xkb_keycode_t) u32;
pub extern fn xkb_state_key_get_one_sym(state: ?*struct_xkb_state, key: xkb_keycode_t) xkb_keysym_t;
pub extern fn xkb_state_key_get_layout(state: ?*struct_xkb_state, key: xkb_keycode_t) xkb_layout_index_t;
pub extern fn xkb_state_key_get_level(state: ?*struct_xkb_state, key: xkb_keycode_t, layout: xkb_layout_index_t) xkb_level_index_t;
pub const XKB_STATE_MATCH_ANY: c_int = 1;
pub const XKB_STATE_MATCH_ALL: c_int = 2;
pub const XKB_STATE_MATCH_NON_EXCLUSIVE: c_int = 65536;
pub const enum_xkb_state_match = c_uint;
pub extern fn xkb_state_serialize_mods(state: ?*struct_xkb_state, components: enum_xkb_state_component) xkb_mod_mask_t;
pub extern fn xkb_state_serialize_layout(state: ?*struct_xkb_state, components: enum_xkb_state_component) xkb_layout_index_t;
pub extern fn xkb_state_mod_name_is_active(state: ?*struct_xkb_state, name: [*c]const u8, @"type": enum_xkb_state_component) c_int;
pub extern fn xkb_state_mod_names_are_active(state: ?*struct_xkb_state, @"type": enum_xkb_state_component, match: enum_xkb_state_match, ...) c_int;
pub extern fn xkb_state_mod_index_is_active(state: ?*struct_xkb_state, idx: xkb_mod_index_t, @"type": enum_xkb_state_component) c_int;
pub extern fn xkb_state_mod_indices_are_active(state: ?*struct_xkb_state, @"type": enum_xkb_state_component, match: enum_xkb_state_match, ...) c_int;
pub const XKB_CONSUMED_MODE_XKB: c_int = 0;
pub const XKB_CONSUMED_MODE_GTK: c_int = 1;
pub const enum_xkb_consumed_mode = c_uint;
pub extern fn xkb_state_key_get_consumed_mods2(state: ?*struct_xkb_state, key: xkb_keycode_t, mode: enum_xkb_consumed_mode) xkb_mod_mask_t;
pub extern fn xkb_state_key_get_consumed_mods(state: ?*struct_xkb_state, key: xkb_keycode_t) xkb_mod_mask_t;
pub extern fn xkb_state_mod_index_is_consumed2(state: ?*struct_xkb_state, key: xkb_keycode_t, idx: xkb_mod_index_t, mode: enum_xkb_consumed_mode) c_int;
pub extern fn xkb_state_mod_index_is_consumed(state: ?*struct_xkb_state, key: xkb_keycode_t, idx: xkb_mod_index_t) c_int;
pub extern fn xkb_state_mod_mask_remove_consumed(state: ?*struct_xkb_state, key: xkb_keycode_t, mask: xkb_mod_mask_t) xkb_mod_mask_t;
pub extern fn xkb_state_layout_name_is_active(state: ?*struct_xkb_state, name: [*c]const u8, @"type": enum_xkb_state_component) c_int;
pub extern fn xkb_state_layout_index_is_active(state: ?*struct_xkb_state, idx: xkb_layout_index_t, @"type": enum_xkb_state_component) c_int;
pub extern fn xkb_state_led_name_is_active(state: ?*struct_xkb_state, name: [*c]const u8) c_int;
pub extern fn xkb_state_led_index_is_active(state: ?*struct_xkb_state, idx: xkb_led_index_t) c_int;
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
pub fn __bswap_16(arg___bsx: __uint16_t) callconv(.c) __uint16_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @as(__uint16_t, @bitCast(@as(c_short, @truncate(((@as(c_int, @bitCast(@as(c_uint, __bsx))) >> @intCast(8)) & @as(c_int, 255)) | ((@as(c_int, @bitCast(@as(c_uint, __bsx))) & @as(c_int, 255)) << @intCast(8))))));
}
pub fn __bswap_32(arg___bsx: __uint32_t) callconv(.c) __uint32_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return ((((__bsx & @as(c_uint, 4278190080)) >> @intCast(24)) | ((__bsx & @as(c_uint, 16711680)) >> @intCast(8))) | ((__bsx & @as(c_uint, 65280)) << @intCast(8))) | ((__bsx & @as(c_uint, 255)) << @intCast(24));
}
pub fn __bswap_64(arg___bsx: __uint64_t) callconv(.c) __uint64_t {
    var __bsx = arg___bsx;
    _ = &__bsx;
    return @as(__uint64_t, @bitCast(@as(c_ulong, @truncate(((((((((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 18374686479671623680)) >> @intCast(56)) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 71776119061217280)) >> @intCast(40))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 280375465082880)) >> @intCast(24))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 1095216660480)) >> @intCast(8))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 4278190080)) << @intCast(8))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 16711680)) << @intCast(24))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 65280)) << @intCast(40))) | ((@as(c_ulonglong, @bitCast(@as(c_ulonglong, __bsx))) & @as(c_ulonglong, 255)) << @intCast(56))))));
}
pub fn __uint16_identity(arg___x: __uint16_t) callconv(.c) __uint16_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint32_identity(arg___x: __uint32_t) callconv(.c) __uint32_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub fn __uint64_identity(arg___x: __uint64_t) callconv(.c) __uint64_t {
    var __x = arg___x;
    _ = &__x;
    return __x;
}
pub const __sigset_t = extern struct {
    __val: [16]c_ulong = @import("std").mem.zeroes([16]c_ulong),
};
pub const sigset_t = __sigset_t;
pub const struct_timeval = extern struct {
    tv_sec: __time_t = @import("std").mem.zeroes(__time_t),
    tv_usec: __suseconds_t = @import("std").mem.zeroes(__suseconds_t),
};
pub const struct_timespec = extern struct {
    tv_sec: __time_t = @import("std").mem.zeroes(__time_t),
    tv_nsec: __syscall_slong_t = @import("std").mem.zeroes(__syscall_slong_t),
};
pub const suseconds_t = __suseconds_t;
pub const __fd_mask = c_long;
pub const fd_set = extern struct {
    __fds_bits: [16]__fd_mask = @import("std").mem.zeroes([16]__fd_mask),
};
pub const fd_mask = __fd_mask;
pub extern fn select(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]struct_timeval) c_int;
pub extern fn pselect(__nfds: c_int, noalias __readfds: [*c]fd_set, noalias __writefds: [*c]fd_set, noalias __exceptfds: [*c]fd_set, noalias __timeout: [*c]const struct_timespec, noalias __sigmask: [*c]const __sigset_t) c_int;
pub const blksize_t = __blksize_t;
pub const blkcnt_t = __blkcnt_t;
pub const fsblkcnt_t = __fsblkcnt_t;
pub const fsfilcnt_t = __fsfilcnt_t;
const struct_unnamed_3 = extern struct {
    __low: c_uint = @import("std").mem.zeroes(c_uint),
    __high: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const __atomic_wide_counter = extern union {
    __value64: c_ulonglong,
    __value32: struct_unnamed_3,
};
pub const struct___pthread_internal_list = extern struct {
    __prev: [*c]struct___pthread_internal_list = @import("std").mem.zeroes([*c]struct___pthread_internal_list),
    __next: [*c]struct___pthread_internal_list = @import("std").mem.zeroes([*c]struct___pthread_internal_list),
};
pub const __pthread_list_t = struct___pthread_internal_list;
pub const struct___pthread_internal_slist = extern struct {
    __next: [*c]struct___pthread_internal_slist = @import("std").mem.zeroes([*c]struct___pthread_internal_slist),
};
pub const __pthread_slist_t = struct___pthread_internal_slist;
pub const struct___pthread_mutex_s = extern struct {
    __lock: c_int = @import("std").mem.zeroes(c_int),
    __count: c_uint = @import("std").mem.zeroes(c_uint),
    __owner: c_int = @import("std").mem.zeroes(c_int),
    __nusers: c_uint = @import("std").mem.zeroes(c_uint),
    __kind: c_int = @import("std").mem.zeroes(c_int),
    __spins: c_int = @import("std").mem.zeroes(c_int),
    __list: __pthread_list_t = @import("std").mem.zeroes(__pthread_list_t),
};
pub const struct___pthread_rwlock_arch_t = extern struct {
    __readers: c_uint = @import("std").mem.zeroes(c_uint),
    __writers: c_uint = @import("std").mem.zeroes(c_uint),
    __wrphase_futex: c_uint = @import("std").mem.zeroes(c_uint),
    __writers_futex: c_uint = @import("std").mem.zeroes(c_uint),
    __pad3: c_uint = @import("std").mem.zeroes(c_uint),
    __pad4: c_uint = @import("std").mem.zeroes(c_uint),
    __cur_writer: c_int = @import("std").mem.zeroes(c_int),
    __shared: c_int = @import("std").mem.zeroes(c_int),
    __pad1: c_ulong = @import("std").mem.zeroes(c_ulong),
    __pad2: c_ulong = @import("std").mem.zeroes(c_ulong),
    __flags: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const struct___pthread_cond_s = extern struct {
    __wseq: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g1_start: __atomic_wide_counter = @import("std").mem.zeroes(__atomic_wide_counter),
    __g_size: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __g1_orig_size: c_uint = @import("std").mem.zeroes(c_uint),
    __wrefs: c_uint = @import("std").mem.zeroes(c_uint),
    __g_signals: [2]c_uint = @import("std").mem.zeroes([2]c_uint),
    __unused_initialized_1: c_uint = @import("std").mem.zeroes(c_uint),
    __unused_initialized_2: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const __tss_t = c_uint;
pub const __thrd_t = c_ulong;
pub const __once_flag = extern struct {
    __data: c_int = @import("std").mem.zeroes(c_int),
};
pub const pthread_t = c_ulong;
pub const pthread_mutexattr_t = extern union {
    __size: [8]u8,
    __align: c_int,
};
pub const pthread_condattr_t = extern union {
    __size: [8]u8,
    __align: c_int,
};
pub const pthread_key_t = c_uint;
pub const pthread_once_t = c_int;
pub const union_pthread_attr_t = extern union {
    __size: [64]u8,
    __align: c_long,
};
pub const pthread_attr_t = union_pthread_attr_t;
pub const pthread_mutex_t = extern union {
    __data: struct___pthread_mutex_s,
    __size: [48]u8,
    __align: c_long,
};
pub const pthread_cond_t = extern union {
    __data: struct___pthread_cond_s,
    __size: [48]u8,
    __align: c_longlong,
};
pub const pthread_rwlock_t = extern union {
    __data: struct___pthread_rwlock_arch_t,
    __size: [56]u8,
    __align: c_long,
};
pub const pthread_rwlockattr_t = extern union {
    __size: [8]u8,
    __align: c_long,
};
pub const pthread_spinlock_t = c_int;
pub const pthread_barrier_t = extern union {
    __size: [32]u8,
    __align: c_long,
};
pub const pthread_barrierattr_t = extern union {
    __size: [8]u8,
    __align: c_int,
};
pub const struct_iovec = extern struct {
    iov_base: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    iov_len: usize = @import("std").mem.zeroes(usize),
};
pub extern fn readv(__fd: c_int, __iovec: [*c]const struct_iovec, __count: c_int) isize;
pub extern fn writev(__fd: c_int, __iovec: [*c]const struct_iovec, __count: c_int) isize;
pub extern fn preadv(__fd: c_int, __iovec: [*c]const struct_iovec, __count: c_int, __offset: __off_t) isize;
pub extern fn pwritev(__fd: c_int, __iovec: [*c]const struct_iovec, __count: c_int, __offset: __off_t) isize;
pub const struct_sched_param = extern struct {
    sched_priority: c_int = @import("std").mem.zeroes(c_int),
};
pub const __cpu_mask = c_ulong;
pub const cpu_set_t = extern struct {
    __bits: [16]__cpu_mask = @import("std").mem.zeroes([16]__cpu_mask),
};
pub extern fn __sched_cpucount(__setsize: usize, __setp: [*c]const cpu_set_t) c_int;
pub extern fn __sched_cpualloc(__count: usize) [*c]cpu_set_t;
pub extern fn __sched_cpufree(__set: [*c]cpu_set_t) void;
pub extern fn sched_setparam(__pid: __pid_t, __param: [*c]const struct_sched_param) c_int;
pub extern fn sched_getparam(__pid: __pid_t, __param: [*c]struct_sched_param) c_int;
pub extern fn sched_setscheduler(__pid: __pid_t, __policy: c_int, __param: [*c]const struct_sched_param) c_int;
pub extern fn sched_getscheduler(__pid: __pid_t) c_int;
pub extern fn sched_yield() c_int;
pub extern fn sched_get_priority_max(__algorithm: c_int) c_int;
pub extern fn sched_get_priority_min(__algorithm: c_int) c_int;
pub extern fn sched_rr_get_interval(__pid: __pid_t, __t: [*c]struct_timespec) c_int;
pub const struct_tm = extern struct {
    tm_sec: c_int = @import("std").mem.zeroes(c_int),
    tm_min: c_int = @import("std").mem.zeroes(c_int),
    tm_hour: c_int = @import("std").mem.zeroes(c_int),
    tm_mday: c_int = @import("std").mem.zeroes(c_int),
    tm_mon: c_int = @import("std").mem.zeroes(c_int),
    tm_year: c_int = @import("std").mem.zeroes(c_int),
    tm_wday: c_int = @import("std").mem.zeroes(c_int),
    tm_yday: c_int = @import("std").mem.zeroes(c_int),
    tm_isdst: c_int = @import("std").mem.zeroes(c_int),
    tm_gmtoff: c_long = @import("std").mem.zeroes(c_long),
    tm_zone: [*c]const u8 = @import("std").mem.zeroes([*c]const u8),
};
pub const struct_itimerspec = extern struct {
    it_interval: struct_timespec = @import("std").mem.zeroes(struct_timespec),
    it_value: struct_timespec = @import("std").mem.zeroes(struct_timespec),
};
pub const struct_sigevent = opaque {};
pub const struct___locale_data_4 = opaque {};
pub const struct___locale_struct = extern struct {
    __locales: [13]?*struct___locale_data_4 = @import("std").mem.zeroes([13]?*struct___locale_data_4),
    __ctype_b: [*c]const c_ushort = @import("std").mem.zeroes([*c]const c_ushort),
    __ctype_tolower: [*c]const c_int = @import("std").mem.zeroes([*c]const c_int),
    __ctype_toupper: [*c]const c_int = @import("std").mem.zeroes([*c]const c_int),
    __names: [13][*c]const u8 = @import("std").mem.zeroes([13][*c]const u8),
};
pub const __locale_t = [*c]struct___locale_struct;
pub const locale_t = __locale_t;
pub extern fn clock() clock_t;
pub extern fn time(__timer: [*c]time_t) time_t;
pub extern fn difftime(__time1: time_t, __time0: time_t) f64;
pub extern fn mktime(__tp: [*c]struct_tm) time_t;
pub extern fn strftime(noalias __s: [*c]u8, __maxsize: usize, noalias __format: [*c]const u8, noalias __tp: [*c]const struct_tm) usize;
pub extern fn strftime_l(noalias __s: [*c]u8, __maxsize: usize, noalias __format: [*c]const u8, noalias __tp: [*c]const struct_tm, __loc: locale_t) usize;
pub extern fn gmtime(__timer: [*c]const time_t) [*c]struct_tm;
pub extern fn localtime(__timer: [*c]const time_t) [*c]struct_tm;
pub extern fn gmtime_r(noalias __timer: [*c]const time_t, noalias __tp: [*c]struct_tm) [*c]struct_tm;
pub extern fn localtime_r(noalias __timer: [*c]const time_t, noalias __tp: [*c]struct_tm) [*c]struct_tm;
pub extern fn asctime(__tp: [*c]const struct_tm) [*c]u8;
pub extern fn ctime(__timer: [*c]const time_t) [*c]u8;
pub extern fn asctime_r(noalias __tp: [*c]const struct_tm, noalias __buf: [*c]u8) [*c]u8;
pub extern fn ctime_r(noalias __timer: [*c]const time_t, noalias __buf: [*c]u8) [*c]u8;
pub extern var __tzname: [2][*c]u8;
pub extern var __daylight: c_int;
pub extern var __timezone: c_long;
pub extern var tzname: [2][*c]u8;
pub extern fn tzset() void;
pub extern var daylight: c_int;
pub extern var timezone: c_long;
pub extern fn timegm(__tp: [*c]struct_tm) time_t;
pub extern fn timelocal(__tp: [*c]struct_tm) time_t;
pub extern fn dysize(__year: c_int) c_int;
pub extern fn nanosleep(__requested_time: [*c]const struct_timespec, __remaining: [*c]struct_timespec) c_int;
pub extern fn clock_getres(__clock_id: clockid_t, __res: [*c]struct_timespec) c_int;
pub extern fn clock_gettime(__clock_id: clockid_t, __tp: [*c]struct_timespec) c_int;
pub extern fn clock_settime(__clock_id: clockid_t, __tp: [*c]const struct_timespec) c_int;
pub extern fn clock_nanosleep(__clock_id: clockid_t, __flags: c_int, __req: [*c]const struct_timespec, __rem: [*c]struct_timespec) c_int;
pub extern fn clock_getcpuclockid(__pid: pid_t, __clock_id: [*c]clockid_t) c_int;
pub extern fn timer_create(__clock_id: clockid_t, noalias __evp: ?*struct_sigevent, noalias __timerid: [*c]timer_t) c_int;
pub extern fn timer_delete(__timerid: timer_t) c_int;
pub extern fn timer_settime(__timerid: timer_t, __flags: c_int, noalias __value: [*c]const struct_itimerspec, noalias __ovalue: [*c]struct_itimerspec) c_int;
pub extern fn timer_gettime(__timerid: timer_t, __value: [*c]struct_itimerspec) c_int;
pub extern fn timer_getoverrun(__timerid: timer_t) c_int;
pub extern fn timespec_get(__ts: [*c]struct_timespec, __base: c_int) c_int;
pub const __jmp_buf = [22]c_ulonglong;
pub const struct___jmp_buf_tag = extern struct {
    __jmpbuf: __jmp_buf = @import("std").mem.zeroes(__jmp_buf),
    __mask_was_saved: c_int = @import("std").mem.zeroes(c_int),
    __saved_mask: __sigset_t = @import("std").mem.zeroes(__sigset_t),
};
pub const PTHREAD_CREATE_JOINABLE: c_int = 0;
pub const PTHREAD_CREATE_DETACHED: c_int = 1;
const enum_unnamed_5 = c_uint;
pub const PTHREAD_MUTEX_TIMED_NP: c_int = 0;
pub const PTHREAD_MUTEX_RECURSIVE_NP: c_int = 1;
pub const PTHREAD_MUTEX_ERRORCHECK_NP: c_int = 2;
pub const PTHREAD_MUTEX_ADAPTIVE_NP: c_int = 3;
pub const PTHREAD_MUTEX_NORMAL: c_int = 0;
pub const PTHREAD_MUTEX_RECURSIVE: c_int = 1;
pub const PTHREAD_MUTEX_ERRORCHECK: c_int = 2;
pub const PTHREAD_MUTEX_DEFAULT: c_int = 0;
const enum_unnamed_6 = c_uint;
pub const PTHREAD_MUTEX_STALLED: c_int = 0;
pub const PTHREAD_MUTEX_STALLED_NP: c_int = 0;
pub const PTHREAD_MUTEX_ROBUST: c_int = 1;
pub const PTHREAD_MUTEX_ROBUST_NP: c_int = 1;
const enum_unnamed_7 = c_uint;
pub const PTHREAD_PRIO_NONE: c_int = 0;
pub const PTHREAD_PRIO_INHERIT: c_int = 1;
pub const PTHREAD_PRIO_PROTECT: c_int = 2;
const enum_unnamed_8 = c_uint;
pub const PTHREAD_RWLOCK_PREFER_READER_NP: c_int = 0;
pub const PTHREAD_RWLOCK_PREFER_WRITER_NP: c_int = 1;
pub const PTHREAD_RWLOCK_PREFER_WRITER_NONRECURSIVE_NP: c_int = 2;
pub const PTHREAD_RWLOCK_DEFAULT_NP: c_int = 0;
const enum_unnamed_9 = c_uint;
pub const PTHREAD_INHERIT_SCHED: c_int = 0;
pub const PTHREAD_EXPLICIT_SCHED: c_int = 1;
const enum_unnamed_10 = c_uint;
pub const PTHREAD_SCOPE_SYSTEM: c_int = 0;
pub const PTHREAD_SCOPE_PROCESS: c_int = 1;
const enum_unnamed_11 = c_uint;
pub const PTHREAD_PROCESS_PRIVATE: c_int = 0;
pub const PTHREAD_PROCESS_SHARED: c_int = 1;
const enum_unnamed_12 = c_uint;
pub const struct__pthread_cleanup_buffer = extern struct {
    __routine: ?*const fn (?*anyopaque) callconv(.c) void = @import("std").mem.zeroes(?*const fn (?*anyopaque) callconv(.c) void),
    __arg: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __canceltype: c_int = @import("std").mem.zeroes(c_int),
    __prev: [*c]struct__pthread_cleanup_buffer = @import("std").mem.zeroes([*c]struct__pthread_cleanup_buffer),
};
pub const PTHREAD_CANCEL_ENABLE: c_int = 0;
pub const PTHREAD_CANCEL_DISABLE: c_int = 1;
const enum_unnamed_13 = c_uint;
pub const PTHREAD_CANCEL_DEFERRED: c_int = 0;
pub const PTHREAD_CANCEL_ASYNCHRONOUS: c_int = 1;
const enum_unnamed_14 = c_uint;
pub extern fn pthread_create(noalias __newthread: [*c]pthread_t, noalias __attr: [*c]const pthread_attr_t, __start_routine: ?*const fn (?*anyopaque) callconv(.c) ?*anyopaque, noalias __arg: ?*anyopaque) c_int;
pub extern fn pthread_exit(__retval: ?*anyopaque) noreturn;
pub extern fn pthread_join(__th: pthread_t, __thread_return: [*c]?*anyopaque) c_int;
pub extern fn pthread_detach(__th: pthread_t) c_int;
pub extern fn pthread_self() pthread_t;
pub extern fn pthread_equal(__thread1: pthread_t, __thread2: pthread_t) c_int;
pub extern fn pthread_attr_init(__attr: [*c]pthread_attr_t) c_int;
pub extern fn pthread_attr_destroy(__attr: [*c]pthread_attr_t) c_int;
pub extern fn pthread_attr_getdetachstate(__attr: [*c]const pthread_attr_t, __detachstate: [*c]c_int) c_int;
pub extern fn pthread_attr_setdetachstate(__attr: [*c]pthread_attr_t, __detachstate: c_int) c_int;
pub extern fn pthread_attr_getguardsize(__attr: [*c]const pthread_attr_t, __guardsize: [*c]usize) c_int;
pub extern fn pthread_attr_setguardsize(__attr: [*c]pthread_attr_t, __guardsize: usize) c_int;
pub extern fn pthread_attr_getschedparam(noalias __attr: [*c]const pthread_attr_t, noalias __param: [*c]struct_sched_param) c_int;
pub extern fn pthread_attr_setschedparam(noalias __attr: [*c]pthread_attr_t, noalias __param: [*c]const struct_sched_param) c_int;
pub extern fn pthread_attr_getschedpolicy(noalias __attr: [*c]const pthread_attr_t, noalias __policy: [*c]c_int) c_int;
pub extern fn pthread_attr_setschedpolicy(__attr: [*c]pthread_attr_t, __policy: c_int) c_int;
pub extern fn pthread_attr_getinheritsched(noalias __attr: [*c]const pthread_attr_t, noalias __inherit: [*c]c_int) c_int;
pub extern fn pthread_attr_setinheritsched(__attr: [*c]pthread_attr_t, __inherit: c_int) c_int;
pub extern fn pthread_attr_getscope(noalias __attr: [*c]const pthread_attr_t, noalias __scope: [*c]c_int) c_int;
pub extern fn pthread_attr_setscope(__attr: [*c]pthread_attr_t, __scope: c_int) c_int;
pub extern fn pthread_attr_getstackaddr(noalias __attr: [*c]const pthread_attr_t, noalias __stackaddr: [*c]?*anyopaque) c_int;
pub extern fn pthread_attr_setstackaddr(__attr: [*c]pthread_attr_t, __stackaddr: ?*anyopaque) c_int;
pub extern fn pthread_attr_getstacksize(noalias __attr: [*c]const pthread_attr_t, noalias __stacksize: [*c]usize) c_int;
pub extern fn pthread_attr_setstacksize(__attr: [*c]pthread_attr_t, __stacksize: usize) c_int;
pub extern fn pthread_attr_getstack(noalias __attr: [*c]const pthread_attr_t, noalias __stackaddr: [*c]?*anyopaque, noalias __stacksize: [*c]usize) c_int;
pub extern fn pthread_attr_setstack(__attr: [*c]pthread_attr_t, __stackaddr: ?*anyopaque, __stacksize: usize) c_int;
pub extern fn pthread_setschedparam(__target_thread: pthread_t, __policy: c_int, __param: [*c]const struct_sched_param) c_int;
pub extern fn pthread_getschedparam(__target_thread: pthread_t, noalias __policy: [*c]c_int, noalias __param: [*c]struct_sched_param) c_int;
pub extern fn pthread_setschedprio(__target_thread: pthread_t, __prio: c_int) c_int;
pub extern fn pthread_once(__once_control: [*c]pthread_once_t, __init_routine: ?*const fn () callconv(.c) void) c_int;
pub extern fn pthread_setcancelstate(__state: c_int, __oldstate: [*c]c_int) c_int;
pub extern fn pthread_setcanceltype(__type: c_int, __oldtype: [*c]c_int) c_int;
pub extern fn pthread_cancel(__th: pthread_t) c_int;
pub extern fn pthread_testcancel() void;
pub const struct___cancel_jmp_buf_tag = extern struct {
    __cancel_jmp_buf: __jmp_buf = @import("std").mem.zeroes(__jmp_buf),
    __mask_was_saved: c_int = @import("std").mem.zeroes(c_int),
};
pub const __pthread_unwind_buf_t = extern struct {
    __cancel_jmp_buf: [1]struct___cancel_jmp_buf_tag = @import("std").mem.zeroes([1]struct___cancel_jmp_buf_tag),
    __pad: [4]?*anyopaque = @import("std").mem.zeroes([4]?*anyopaque),
};
pub const struct___pthread_cleanup_frame = extern struct {
    __cancel_routine: ?*const fn (?*anyopaque) callconv(.c) void = @import("std").mem.zeroes(?*const fn (?*anyopaque) callconv(.c) void),
    __cancel_arg: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    __do_it: c_int = @import("std").mem.zeroes(c_int),
    __cancel_type: c_int = @import("std").mem.zeroes(c_int),
};
pub extern fn __pthread_register_cancel(__buf: [*c]__pthread_unwind_buf_t) void;
pub extern fn __pthread_unregister_cancel(__buf: [*c]__pthread_unwind_buf_t) void;
pub extern fn __pthread_unwind_next(__buf: [*c]__pthread_unwind_buf_t) noreturn;
pub extern fn __sigsetjmp(__env: [*c]struct___jmp_buf_tag, __savemask: c_int) c_int;
pub extern fn pthread_mutex_init(__mutex: [*c]pthread_mutex_t, __mutexattr: [*c]const pthread_mutexattr_t) c_int;
pub extern fn pthread_mutex_destroy(__mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_mutex_trylock(__mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_mutex_lock(__mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_mutex_timedlock(noalias __mutex: [*c]pthread_mutex_t, noalias __abstime: [*c]const struct_timespec) c_int;
pub extern fn pthread_mutex_unlock(__mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_mutex_getprioceiling(noalias __mutex: [*c]const pthread_mutex_t, noalias __prioceiling: [*c]c_int) c_int;
pub extern fn pthread_mutex_setprioceiling(noalias __mutex: [*c]pthread_mutex_t, __prioceiling: c_int, noalias __old_ceiling: [*c]c_int) c_int;
pub extern fn pthread_mutex_consistent(__mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_mutexattr_init(__attr: [*c]pthread_mutexattr_t) c_int;
pub extern fn pthread_mutexattr_destroy(__attr: [*c]pthread_mutexattr_t) c_int;
pub extern fn pthread_mutexattr_getpshared(noalias __attr: [*c]const pthread_mutexattr_t, noalias __pshared: [*c]c_int) c_int;
pub extern fn pthread_mutexattr_setpshared(__attr: [*c]pthread_mutexattr_t, __pshared: c_int) c_int;
pub extern fn pthread_mutexattr_gettype(noalias __attr: [*c]const pthread_mutexattr_t, noalias __kind: [*c]c_int) c_int;
pub extern fn pthread_mutexattr_settype(__attr: [*c]pthread_mutexattr_t, __kind: c_int) c_int;
pub extern fn pthread_mutexattr_getprotocol(noalias __attr: [*c]const pthread_mutexattr_t, noalias __protocol: [*c]c_int) c_int;
pub extern fn pthread_mutexattr_setprotocol(__attr: [*c]pthread_mutexattr_t, __protocol: c_int) c_int;
pub extern fn pthread_mutexattr_getprioceiling(noalias __attr: [*c]const pthread_mutexattr_t, noalias __prioceiling: [*c]c_int) c_int;
pub extern fn pthread_mutexattr_setprioceiling(__attr: [*c]pthread_mutexattr_t, __prioceiling: c_int) c_int;
pub extern fn pthread_mutexattr_getrobust(__attr: [*c]const pthread_mutexattr_t, __robustness: [*c]c_int) c_int;
pub extern fn pthread_mutexattr_setrobust(__attr: [*c]pthread_mutexattr_t, __robustness: c_int) c_int;
pub extern fn pthread_rwlock_init(noalias __rwlock: [*c]pthread_rwlock_t, noalias __attr: [*c]const pthread_rwlockattr_t) c_int;
pub extern fn pthread_rwlock_destroy(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlock_rdlock(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlock_tryrdlock(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlock_timedrdlock(noalias __rwlock: [*c]pthread_rwlock_t, noalias __abstime: [*c]const struct_timespec) c_int;
pub extern fn pthread_rwlock_wrlock(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlock_trywrlock(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlock_timedwrlock(noalias __rwlock: [*c]pthread_rwlock_t, noalias __abstime: [*c]const struct_timespec) c_int;
pub extern fn pthread_rwlock_unlock(__rwlock: [*c]pthread_rwlock_t) c_int;
pub extern fn pthread_rwlockattr_init(__attr: [*c]pthread_rwlockattr_t) c_int;
pub extern fn pthread_rwlockattr_destroy(__attr: [*c]pthread_rwlockattr_t) c_int;
pub extern fn pthread_rwlockattr_getpshared(noalias __attr: [*c]const pthread_rwlockattr_t, noalias __pshared: [*c]c_int) c_int;
pub extern fn pthread_rwlockattr_setpshared(__attr: [*c]pthread_rwlockattr_t, __pshared: c_int) c_int;
pub extern fn pthread_rwlockattr_getkind_np(noalias __attr: [*c]const pthread_rwlockattr_t, noalias __pref: [*c]c_int) c_int;
pub extern fn pthread_rwlockattr_setkind_np(__attr: [*c]pthread_rwlockattr_t, __pref: c_int) c_int;
pub extern fn pthread_cond_init(noalias __cond: [*c]pthread_cond_t, noalias __cond_attr: [*c]const pthread_condattr_t) c_int;
pub extern fn pthread_cond_destroy(__cond: [*c]pthread_cond_t) c_int;
pub extern fn pthread_cond_signal(__cond: [*c]pthread_cond_t) c_int;
pub extern fn pthread_cond_broadcast(__cond: [*c]pthread_cond_t) c_int;
pub extern fn pthread_cond_wait(noalias __cond: [*c]pthread_cond_t, noalias __mutex: [*c]pthread_mutex_t) c_int;
pub extern fn pthread_cond_timedwait(noalias __cond: [*c]pthread_cond_t, noalias __mutex: [*c]pthread_mutex_t, noalias __abstime: [*c]const struct_timespec) c_int;
pub extern fn pthread_condattr_init(__attr: [*c]pthread_condattr_t) c_int;
pub extern fn pthread_condattr_destroy(__attr: [*c]pthread_condattr_t) c_int;
pub extern fn pthread_condattr_getpshared(noalias __attr: [*c]const pthread_condattr_t, noalias __pshared: [*c]c_int) c_int;
pub extern fn pthread_condattr_setpshared(__attr: [*c]pthread_condattr_t, __pshared: c_int) c_int;
pub extern fn pthread_condattr_getclock(noalias __attr: [*c]const pthread_condattr_t, noalias __clock_id: [*c]__clockid_t) c_int;
pub extern fn pthread_condattr_setclock(__attr: [*c]pthread_condattr_t, __clock_id: __clockid_t) c_int;
pub extern fn pthread_spin_init(__lock: [*c]volatile pthread_spinlock_t, __pshared: c_int) c_int;
pub extern fn pthread_spin_destroy(__lock: [*c]volatile pthread_spinlock_t) c_int;
pub extern fn pthread_spin_lock(__lock: [*c]volatile pthread_spinlock_t) c_int;
pub extern fn pthread_spin_trylock(__lock: [*c]volatile pthread_spinlock_t) c_int;
pub extern fn pthread_spin_unlock(__lock: [*c]volatile pthread_spinlock_t) c_int;
pub extern fn pthread_barrier_init(noalias __barrier: [*c]pthread_barrier_t, noalias __attr: [*c]const pthread_barrierattr_t, __count: c_uint) c_int;
pub extern fn pthread_barrier_destroy(__barrier: [*c]pthread_barrier_t) c_int;
pub extern fn pthread_barrier_wait(__barrier: [*c]pthread_barrier_t) c_int;
pub extern fn pthread_barrierattr_init(__attr: [*c]pthread_barrierattr_t) c_int;
pub extern fn pthread_barrierattr_destroy(__attr: [*c]pthread_barrierattr_t) c_int;
pub extern fn pthread_barrierattr_getpshared(noalias __attr: [*c]const pthread_barrierattr_t, noalias __pshared: [*c]c_int) c_int;
pub extern fn pthread_barrierattr_setpshared(__attr: [*c]pthread_barrierattr_t, __pshared: c_int) c_int;
pub extern fn pthread_key_create(__key: [*c]pthread_key_t, __destr_function: ?*const fn (?*anyopaque) callconv(.c) void) c_int;
pub extern fn pthread_key_delete(__key: pthread_key_t) c_int;
pub extern fn pthread_getspecific(__key: pthread_key_t) ?*anyopaque;
pub extern fn pthread_setspecific(__key: pthread_key_t, __pointer: ?*const anyopaque) c_int;
pub extern fn pthread_getcpuclockid(__thread_id: pthread_t, __clock_id: [*c]__clockid_t) c_int;
pub extern fn pthread_atfork(__prepare: ?*const fn () callconv(.c) void, __parent: ?*const fn () callconv(.c) void, __child: ?*const fn () callconv(.c) void) c_int;
pub const struct_xcb_connection_t = opaque {};
pub const xcb_connection_t = struct_xcb_connection_t;
pub const xcb_generic_iterator_t = extern struct {
    data: ?*anyopaque = @import("std").mem.zeroes(?*anyopaque),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_generic_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_generic_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    pad: [7]u32 = @import("std").mem.zeroes([7]u32),
    full_sequence: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_raw_generic_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    pad: [7]u32 = @import("std").mem.zeroes([7]u32),
};
pub const xcb_ge_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    event_type: u16 = @import("std").mem.zeroes(u16),
    pad1: u16 = @import("std").mem.zeroes(u16),
    pad: [5]u32 = @import("std").mem.zeroes([5]u32),
    full_sequence: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_generic_error_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    error_code: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    resource_id: u32 = @import("std").mem.zeroes(u32),
    minor_code: u16 = @import("std").mem.zeroes(u16),
    major_code: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    pad: [5]u32 = @import("std").mem.zeroes([5]u32),
    full_sequence: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_void_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const struct_xcb_char2b_t = extern struct {
    byte1: u8 = @import("std").mem.zeroes(u8),
    byte2: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_char2b_t = struct_xcb_char2b_t;
pub const struct_xcb_char2b_iterator_t = extern struct {
    data: [*c]xcb_char2b_t = @import("std").mem.zeroes([*c]xcb_char2b_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_char2b_iterator_t = struct_xcb_char2b_iterator_t;
pub const xcb_window_t = u32;
pub const struct_xcb_window_iterator_t = extern struct {
    data: [*c]xcb_window_t = @import("std").mem.zeroes([*c]xcb_window_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_window_iterator_t = struct_xcb_window_iterator_t;
pub const xcb_pixmap_t = u32;
pub const struct_xcb_pixmap_iterator_t = extern struct {
    data: [*c]xcb_pixmap_t = @import("std").mem.zeroes([*c]xcb_pixmap_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_pixmap_iterator_t = struct_xcb_pixmap_iterator_t;
pub const xcb_cursor_t = u32;
pub const struct_xcb_cursor_iterator_t = extern struct {
    data: [*c]xcb_cursor_t = @import("std").mem.zeroes([*c]xcb_cursor_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_cursor_iterator_t = struct_xcb_cursor_iterator_t;
pub const xcb_font_t = u32;
pub const struct_xcb_font_iterator_t = extern struct {
    data: [*c]xcb_font_t = @import("std").mem.zeroes([*c]xcb_font_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_font_iterator_t = struct_xcb_font_iterator_t;
pub const xcb_gcontext_t = u32;
pub const struct_xcb_gcontext_iterator_t = extern struct {
    data: [*c]xcb_gcontext_t = @import("std").mem.zeroes([*c]xcb_gcontext_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_gcontext_iterator_t = struct_xcb_gcontext_iterator_t;
pub const xcb_colormap_t = u32;
pub const struct_xcb_colormap_iterator_t = extern struct {
    data: [*c]xcb_colormap_t = @import("std").mem.zeroes([*c]xcb_colormap_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_colormap_iterator_t = struct_xcb_colormap_iterator_t;
pub const xcb_atom_t = u32;
pub const struct_xcb_atom_iterator_t = extern struct {
    data: [*c]xcb_atom_t = @import("std").mem.zeroes([*c]xcb_atom_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_atom_iterator_t = struct_xcb_atom_iterator_t;
pub const xcb_drawable_t = u32;
pub const struct_xcb_drawable_iterator_t = extern struct {
    data: [*c]xcb_drawable_t = @import("std").mem.zeroes([*c]xcb_drawable_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_drawable_iterator_t = struct_xcb_drawable_iterator_t;
pub const xcb_fontable_t = u32;
pub const struct_xcb_fontable_iterator_t = extern struct {
    data: [*c]xcb_fontable_t = @import("std").mem.zeroes([*c]xcb_fontable_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_fontable_iterator_t = struct_xcb_fontable_iterator_t;
pub const xcb_bool32_t = u32;
pub const struct_xcb_bool32_iterator_t = extern struct {
    data: [*c]xcb_bool32_t = @import("std").mem.zeroes([*c]xcb_bool32_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_bool32_iterator_t = struct_xcb_bool32_iterator_t;
pub const xcb_visualid_t = u32;
pub const struct_xcb_visualid_iterator_t = extern struct {
    data: [*c]xcb_visualid_t = @import("std").mem.zeroes([*c]xcb_visualid_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_visualid_iterator_t = struct_xcb_visualid_iterator_t;
pub const xcb_timestamp_t = u32;
pub const struct_xcb_timestamp_iterator_t = extern struct {
    data: [*c]xcb_timestamp_t = @import("std").mem.zeroes([*c]xcb_timestamp_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_timestamp_iterator_t = struct_xcb_timestamp_iterator_t;
pub const xcb_keysym_t = u32;
pub const struct_xcb_keysym_iterator_t = extern struct {
    data: [*c]xcb_keysym_t = @import("std").mem.zeroes([*c]xcb_keysym_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_keysym_iterator_t = struct_xcb_keysym_iterator_t;
pub const xcb_keycode_t = u8;
pub const struct_xcb_keycode_iterator_t = extern struct {
    data: [*c]xcb_keycode_t = @import("std").mem.zeroes([*c]xcb_keycode_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_keycode_iterator_t = struct_xcb_keycode_iterator_t;
pub const xcb_keycode32_t = u32;
pub const struct_xcb_keycode32_iterator_t = extern struct {
    data: [*c]xcb_keycode32_t = @import("std").mem.zeroes([*c]xcb_keycode32_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_keycode32_iterator_t = struct_xcb_keycode32_iterator_t;
pub const xcb_button_t = u8;
pub const struct_xcb_button_iterator_t = extern struct {
    data: [*c]xcb_button_t = @import("std").mem.zeroes([*c]xcb_button_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_button_iterator_t = struct_xcb_button_iterator_t;
pub const struct_xcb_point_t = extern struct {
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_point_t = struct_xcb_point_t;
pub const struct_xcb_point_iterator_t = extern struct {
    data: [*c]xcb_point_t = @import("std").mem.zeroes([*c]xcb_point_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_point_iterator_t = struct_xcb_point_iterator_t;
pub const struct_xcb_rectangle_t = extern struct {
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_rectangle_t = struct_xcb_rectangle_t;
pub const struct_xcb_rectangle_iterator_t = extern struct {
    data: [*c]xcb_rectangle_t = @import("std").mem.zeroes([*c]xcb_rectangle_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_rectangle_iterator_t = struct_xcb_rectangle_iterator_t;
pub const struct_xcb_arc_t = extern struct {
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    angle1: i16 = @import("std").mem.zeroes(i16),
    angle2: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_arc_t = struct_xcb_arc_t;
pub const struct_xcb_arc_iterator_t = extern struct {
    data: [*c]xcb_arc_t = @import("std").mem.zeroes([*c]xcb_arc_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_arc_iterator_t = struct_xcb_arc_iterator_t;
pub const struct_xcb_format_t = extern struct {
    depth: u8 = @import("std").mem.zeroes(u8),
    bits_per_pixel: u8 = @import("std").mem.zeroes(u8),
    scanline_pad: u8 = @import("std").mem.zeroes(u8),
    pad0: [5]u8 = @import("std").mem.zeroes([5]u8),
};
pub const xcb_format_t = struct_xcb_format_t;
pub const struct_xcb_format_iterator_t = extern struct {
    data: [*c]xcb_format_t = @import("std").mem.zeroes([*c]xcb_format_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_format_iterator_t = struct_xcb_format_iterator_t;
pub const XCB_VISUAL_CLASS_STATIC_GRAY: c_int = 0;
pub const XCB_VISUAL_CLASS_GRAY_SCALE: c_int = 1;
pub const XCB_VISUAL_CLASS_STATIC_COLOR: c_int = 2;
pub const XCB_VISUAL_CLASS_PSEUDO_COLOR: c_int = 3;
pub const XCB_VISUAL_CLASS_TRUE_COLOR: c_int = 4;
pub const XCB_VISUAL_CLASS_DIRECT_COLOR: c_int = 5;
pub const enum_xcb_visual_class_t = c_uint;
pub const xcb_visual_class_t = enum_xcb_visual_class_t;
pub const struct_xcb_visualtype_t = extern struct {
    visual_id: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
    _class: u8 = @import("std").mem.zeroes(u8),
    bits_per_rgb_value: u8 = @import("std").mem.zeroes(u8),
    colormap_entries: u16 = @import("std").mem.zeroes(u16),
    red_mask: u32 = @import("std").mem.zeroes(u32),
    green_mask: u32 = @import("std").mem.zeroes(u32),
    blue_mask: u32 = @import("std").mem.zeroes(u32),
    pad0: [4]u8 = @import("std").mem.zeroes([4]u8),
};
pub const xcb_visualtype_t = struct_xcb_visualtype_t;
pub const struct_xcb_visualtype_iterator_t = extern struct {
    data: [*c]xcb_visualtype_t = @import("std").mem.zeroes([*c]xcb_visualtype_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_visualtype_iterator_t = struct_xcb_visualtype_iterator_t;
pub const struct_xcb_depth_t = extern struct {
    depth: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    visuals_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [4]u8 = @import("std").mem.zeroes([4]u8),
};
pub const xcb_depth_t = struct_xcb_depth_t;
pub const struct_xcb_depth_iterator_t = extern struct {
    data: [*c]xcb_depth_t = @import("std").mem.zeroes([*c]xcb_depth_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_depth_iterator_t = struct_xcb_depth_iterator_t;
pub const XCB_EVENT_MASK_NO_EVENT: c_int = 0;
pub const XCB_EVENT_MASK_KEY_PRESS: c_int = 1;
pub const XCB_EVENT_MASK_KEY_RELEASE: c_int = 2;
pub const XCB_EVENT_MASK_BUTTON_PRESS: c_int = 4;
pub const XCB_EVENT_MASK_BUTTON_RELEASE: c_int = 8;
pub const XCB_EVENT_MASK_ENTER_WINDOW: c_int = 16;
pub const XCB_EVENT_MASK_LEAVE_WINDOW: c_int = 32;
pub const XCB_EVENT_MASK_POINTER_MOTION: c_int = 64;
pub const XCB_EVENT_MASK_POINTER_MOTION_HINT: c_int = 128;
pub const XCB_EVENT_MASK_BUTTON_1_MOTION: c_int = 256;
pub const XCB_EVENT_MASK_BUTTON_2_MOTION: c_int = 512;
pub const XCB_EVENT_MASK_BUTTON_3_MOTION: c_int = 1024;
pub const XCB_EVENT_MASK_BUTTON_4_MOTION: c_int = 2048;
pub const XCB_EVENT_MASK_BUTTON_5_MOTION: c_int = 4096;
pub const XCB_EVENT_MASK_BUTTON_MOTION: c_int = 8192;
pub const XCB_EVENT_MASK_KEYMAP_STATE: c_int = 16384;
pub const XCB_EVENT_MASK_EXPOSURE: c_int = 32768;
pub const XCB_EVENT_MASK_VISIBILITY_CHANGE: c_int = 65536;
pub const XCB_EVENT_MASK_STRUCTURE_NOTIFY: c_int = 131072;
pub const XCB_EVENT_MASK_RESIZE_REDIRECT: c_int = 262144;
pub const XCB_EVENT_MASK_SUBSTRUCTURE_NOTIFY: c_int = 524288;
pub const XCB_EVENT_MASK_SUBSTRUCTURE_REDIRECT: c_int = 1048576;
pub const XCB_EVENT_MASK_FOCUS_CHANGE: c_int = 2097152;
pub const XCB_EVENT_MASK_PROPERTY_CHANGE: c_int = 4194304;
pub const XCB_EVENT_MASK_COLOR_MAP_CHANGE: c_int = 8388608;
pub const XCB_EVENT_MASK_OWNER_GRAB_BUTTON: c_int = 16777216;
pub const enum_xcb_event_mask_t = c_uint;
pub const xcb_event_mask_t = enum_xcb_event_mask_t;
pub const XCB_BACKING_STORE_NOT_USEFUL: c_int = 0;
pub const XCB_BACKING_STORE_WHEN_MAPPED: c_int = 1;
pub const XCB_BACKING_STORE_ALWAYS: c_int = 2;
pub const enum_xcb_backing_store_t = c_uint;
pub const xcb_backing_store_t = enum_xcb_backing_store_t;
pub const struct_xcb_screen_t = extern struct {
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    default_colormap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    white_pixel: u32 = @import("std").mem.zeroes(u32),
    black_pixel: u32 = @import("std").mem.zeroes(u32),
    current_input_masks: u32 = @import("std").mem.zeroes(u32),
    width_in_pixels: u16 = @import("std").mem.zeroes(u16),
    height_in_pixels: u16 = @import("std").mem.zeroes(u16),
    width_in_millimeters: u16 = @import("std").mem.zeroes(u16),
    height_in_millimeters: u16 = @import("std").mem.zeroes(u16),
    min_installed_maps: u16 = @import("std").mem.zeroes(u16),
    max_installed_maps: u16 = @import("std").mem.zeroes(u16),
    root_visual: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
    backing_stores: u8 = @import("std").mem.zeroes(u8),
    save_unders: u8 = @import("std").mem.zeroes(u8),
    root_depth: u8 = @import("std").mem.zeroes(u8),
    allowed_depths_len: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_screen_t = struct_xcb_screen_t;
pub const struct_xcb_screen_iterator_t = extern struct {
    data: [*c]xcb_screen_t = @import("std").mem.zeroes([*c]xcb_screen_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_screen_iterator_t = struct_xcb_screen_iterator_t;
pub const struct_xcb_setup_request_t = extern struct {
    byte_order: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    protocol_major_version: u16 = @import("std").mem.zeroes(u16),
    protocol_minor_version: u16 = @import("std").mem.zeroes(u16),
    authorization_protocol_name_len: u16 = @import("std").mem.zeroes(u16),
    authorization_protocol_data_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_setup_request_t = struct_xcb_setup_request_t;
pub const struct_xcb_setup_request_iterator_t = extern struct {
    data: [*c]xcb_setup_request_t = @import("std").mem.zeroes([*c]xcb_setup_request_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_setup_request_iterator_t = struct_xcb_setup_request_iterator_t;
pub const struct_xcb_setup_failed_t = extern struct {
    status: u8 = @import("std").mem.zeroes(u8),
    reason_len: u8 = @import("std").mem.zeroes(u8),
    protocol_major_version: u16 = @import("std").mem.zeroes(u16),
    protocol_minor_version: u16 = @import("std").mem.zeroes(u16),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_setup_failed_t = struct_xcb_setup_failed_t;
pub const struct_xcb_setup_failed_iterator_t = extern struct {
    data: [*c]xcb_setup_failed_t = @import("std").mem.zeroes([*c]xcb_setup_failed_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_setup_failed_iterator_t = struct_xcb_setup_failed_iterator_t;
pub const struct_xcb_setup_authenticate_t = extern struct {
    status: u8 = @import("std").mem.zeroes(u8),
    pad0: [5]u8 = @import("std").mem.zeroes([5]u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_setup_authenticate_t = struct_xcb_setup_authenticate_t;
pub const struct_xcb_setup_authenticate_iterator_t = extern struct {
    data: [*c]xcb_setup_authenticate_t = @import("std").mem.zeroes([*c]xcb_setup_authenticate_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_setup_authenticate_iterator_t = struct_xcb_setup_authenticate_iterator_t;
pub const XCB_IMAGE_ORDER_LSB_FIRST: c_int = 0;
pub const XCB_IMAGE_ORDER_MSB_FIRST: c_int = 1;
pub const enum_xcb_image_order_t = c_uint;
pub const xcb_image_order_t = enum_xcb_image_order_t;
pub const struct_xcb_setup_t = extern struct {
    status: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    protocol_major_version: u16 = @import("std").mem.zeroes(u16),
    protocol_minor_version: u16 = @import("std").mem.zeroes(u16),
    length: u16 = @import("std").mem.zeroes(u16),
    release_number: u32 = @import("std").mem.zeroes(u32),
    resource_id_base: u32 = @import("std").mem.zeroes(u32),
    resource_id_mask: u32 = @import("std").mem.zeroes(u32),
    motion_buffer_size: u32 = @import("std").mem.zeroes(u32),
    vendor_len: u16 = @import("std").mem.zeroes(u16),
    maximum_request_length: u16 = @import("std").mem.zeroes(u16),
    roots_len: u8 = @import("std").mem.zeroes(u8),
    pixmap_formats_len: u8 = @import("std").mem.zeroes(u8),
    image_byte_order: u8 = @import("std").mem.zeroes(u8),
    bitmap_format_bit_order: u8 = @import("std").mem.zeroes(u8),
    bitmap_format_scanline_unit: u8 = @import("std").mem.zeroes(u8),
    bitmap_format_scanline_pad: u8 = @import("std").mem.zeroes(u8),
    min_keycode: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    max_keycode: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    pad1: [4]u8 = @import("std").mem.zeroes([4]u8),
};
pub const xcb_setup_t = struct_xcb_setup_t;
pub const struct_xcb_setup_iterator_t = extern struct {
    data: [*c]xcb_setup_t = @import("std").mem.zeroes([*c]xcb_setup_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_setup_iterator_t = struct_xcb_setup_iterator_t;
pub const XCB_MOD_MASK_SHIFT: c_int = 1;
pub const XCB_MOD_MASK_LOCK: c_int = 2;
pub const XCB_MOD_MASK_CONTROL: c_int = 4;
pub const XCB_MOD_MASK_1: c_int = 8;
pub const XCB_MOD_MASK_2: c_int = 16;
pub const XCB_MOD_MASK_3: c_int = 32;
pub const XCB_MOD_MASK_4: c_int = 64;
pub const XCB_MOD_MASK_5: c_int = 128;
pub const XCB_MOD_MASK_ANY: c_int = 32768;
pub const enum_xcb_mod_mask_t = c_uint;
pub const xcb_mod_mask_t = enum_xcb_mod_mask_t;
pub const XCB_KEY_BUT_MASK_SHIFT: c_int = 1;
pub const XCB_KEY_BUT_MASK_LOCK: c_int = 2;
pub const XCB_KEY_BUT_MASK_CONTROL: c_int = 4;
pub const XCB_KEY_BUT_MASK_MOD_1: c_int = 8;
pub const XCB_KEY_BUT_MASK_MOD_2: c_int = 16;
pub const XCB_KEY_BUT_MASK_MOD_3: c_int = 32;
pub const XCB_KEY_BUT_MASK_MOD_4: c_int = 64;
pub const XCB_KEY_BUT_MASK_MOD_5: c_int = 128;
pub const XCB_KEY_BUT_MASK_BUTTON_1: c_int = 256;
pub const XCB_KEY_BUT_MASK_BUTTON_2: c_int = 512;
pub const XCB_KEY_BUT_MASK_BUTTON_3: c_int = 1024;
pub const XCB_KEY_BUT_MASK_BUTTON_4: c_int = 2048;
pub const XCB_KEY_BUT_MASK_BUTTON_5: c_int = 4096;
pub const enum_xcb_key_but_mask_t = c_uint;
pub const xcb_key_but_mask_t = enum_xcb_key_but_mask_t;
pub const XCB_WINDOW_NONE: c_int = 0;
pub const enum_xcb_window_enum_t = c_uint;
pub const xcb_window_enum_t = enum_xcb_window_enum_t;
pub const struct_xcb_key_press_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    detail: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    root_x: i16 = @import("std").mem.zeroes(i16),
    root_y: i16 = @import("std").mem.zeroes(i16),
    event_x: i16 = @import("std").mem.zeroes(i16),
    event_y: i16 = @import("std").mem.zeroes(i16),
    state: u16 = @import("std").mem.zeroes(u16),
    same_screen: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_key_press_event_t = struct_xcb_key_press_event_t;
pub const xcb_key_release_event_t = xcb_key_press_event_t;
pub const XCB_BUTTON_MASK_1: c_int = 256;
pub const XCB_BUTTON_MASK_2: c_int = 512;
pub const XCB_BUTTON_MASK_3: c_int = 1024;
pub const XCB_BUTTON_MASK_4: c_int = 2048;
pub const XCB_BUTTON_MASK_5: c_int = 4096;
pub const XCB_BUTTON_MASK_ANY: c_int = 32768;
pub const enum_xcb_button_mask_t = c_uint;
pub const xcb_button_mask_t = enum_xcb_button_mask_t;
pub const struct_xcb_button_press_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    detail: xcb_button_t = @import("std").mem.zeroes(xcb_button_t),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    root_x: i16 = @import("std").mem.zeroes(i16),
    root_y: i16 = @import("std").mem.zeroes(i16),
    event_x: i16 = @import("std").mem.zeroes(i16),
    event_y: i16 = @import("std").mem.zeroes(i16),
    state: u16 = @import("std").mem.zeroes(u16),
    same_screen: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_button_press_event_t = struct_xcb_button_press_event_t;
pub const xcb_button_release_event_t = xcb_button_press_event_t;
pub const XCB_MOTION_NORMAL: c_int = 0;
pub const XCB_MOTION_HINT: c_int = 1;
pub const enum_xcb_motion_t = c_uint;
pub const xcb_motion_t = enum_xcb_motion_t;
pub const struct_xcb_motion_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    detail: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    root_x: i16 = @import("std").mem.zeroes(i16),
    root_y: i16 = @import("std").mem.zeroes(i16),
    event_x: i16 = @import("std").mem.zeroes(i16),
    event_y: i16 = @import("std").mem.zeroes(i16),
    state: u16 = @import("std").mem.zeroes(u16),
    same_screen: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_motion_notify_event_t = struct_xcb_motion_notify_event_t;
pub const XCB_NOTIFY_DETAIL_ANCESTOR: c_int = 0;
pub const XCB_NOTIFY_DETAIL_VIRTUAL: c_int = 1;
pub const XCB_NOTIFY_DETAIL_INFERIOR: c_int = 2;
pub const XCB_NOTIFY_DETAIL_NONLINEAR: c_int = 3;
pub const XCB_NOTIFY_DETAIL_NONLINEAR_VIRTUAL: c_int = 4;
pub const XCB_NOTIFY_DETAIL_POINTER: c_int = 5;
pub const XCB_NOTIFY_DETAIL_POINTER_ROOT: c_int = 6;
pub const XCB_NOTIFY_DETAIL_NONE: c_int = 7;
pub const enum_xcb_notify_detail_t = c_uint;
pub const xcb_notify_detail_t = enum_xcb_notify_detail_t;
pub const XCB_NOTIFY_MODE_NORMAL: c_int = 0;
pub const XCB_NOTIFY_MODE_GRAB: c_int = 1;
pub const XCB_NOTIFY_MODE_UNGRAB: c_int = 2;
pub const XCB_NOTIFY_MODE_WHILE_GRABBED: c_int = 3;
pub const enum_xcb_notify_mode_t = c_uint;
pub const xcb_notify_mode_t = enum_xcb_notify_mode_t;
pub const struct_xcb_enter_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    detail: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    root_x: i16 = @import("std").mem.zeroes(i16),
    root_y: i16 = @import("std").mem.zeroes(i16),
    event_x: i16 = @import("std").mem.zeroes(i16),
    event_y: i16 = @import("std").mem.zeroes(i16),
    state: u16 = @import("std").mem.zeroes(u16),
    mode: u8 = @import("std").mem.zeroes(u8),
    same_screen_focus: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_enter_notify_event_t = struct_xcb_enter_notify_event_t;
pub const xcb_leave_notify_event_t = xcb_enter_notify_event_t;
pub const struct_xcb_focus_in_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    detail: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    mode: u8 = @import("std").mem.zeroes(u8),
    pad0: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_focus_in_event_t = struct_xcb_focus_in_event_t;
pub const xcb_focus_out_event_t = xcb_focus_in_event_t;
pub const struct_xcb_keymap_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    keys: [31]u8 = @import("std").mem.zeroes([31]u8),
};
pub const xcb_keymap_notify_event_t = struct_xcb_keymap_notify_event_t;
pub const struct_xcb_expose_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: u16 = @import("std").mem.zeroes(u16),
    y: u16 = @import("std").mem.zeroes(u16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    count: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_expose_event_t = struct_xcb_expose_event_t;
pub const struct_xcb_graphics_exposure_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    x: u16 = @import("std").mem.zeroes(u16),
    y: u16 = @import("std").mem.zeroes(u16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    minor_opcode: u16 = @import("std").mem.zeroes(u16),
    count: u16 = @import("std").mem.zeroes(u16),
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_graphics_exposure_event_t = struct_xcb_graphics_exposure_event_t;
pub const struct_xcb_no_exposure_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    minor_opcode: u16 = @import("std").mem.zeroes(u16),
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad1: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_no_exposure_event_t = struct_xcb_no_exposure_event_t;
pub const XCB_VISIBILITY_UNOBSCURED: c_int = 0;
pub const XCB_VISIBILITY_PARTIALLY_OBSCURED: c_int = 1;
pub const XCB_VISIBILITY_FULLY_OBSCURED: c_int = 2;
pub const enum_xcb_visibility_t = c_uint;
pub const xcb_visibility_t = enum_xcb_visibility_t;
pub const struct_xcb_visibility_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    state: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_visibility_notify_event_t = struct_xcb_visibility_notify_event_t;
pub const struct_xcb_create_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    border_width: u16 = @import("std").mem.zeroes(u16),
    override_redirect: u8 = @import("std").mem.zeroes(u8),
    pad1: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_create_notify_event_t = struct_xcb_create_notify_event_t;
pub const struct_xcb_destroy_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_destroy_notify_event_t = struct_xcb_destroy_notify_event_t;
pub const struct_xcb_unmap_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    from_configure: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_unmap_notify_event_t = struct_xcb_unmap_notify_event_t;
pub const struct_xcb_map_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    override_redirect: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_map_notify_event_t = struct_xcb_map_notify_event_t;
pub const struct_xcb_map_request_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_map_request_event_t = struct_xcb_map_request_event_t;
pub const struct_xcb_reparent_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    override_redirect: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_reparent_notify_event_t = struct_xcb_reparent_notify_event_t;
pub const struct_xcb_configure_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    above_sibling: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    border_width: u16 = @import("std").mem.zeroes(u16),
    override_redirect: u8 = @import("std").mem.zeroes(u8),
    pad1: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_configure_notify_event_t = struct_xcb_configure_notify_event_t;
pub const struct_xcb_configure_request_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    stack_mode: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    sibling: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    border_width: u16 = @import("std").mem.zeroes(u16),
    value_mask: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_configure_request_event_t = struct_xcb_configure_request_event_t;
pub const struct_xcb_gravity_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_gravity_notify_event_t = struct_xcb_gravity_notify_event_t;
pub const struct_xcb_resize_request_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_resize_request_event_t = struct_xcb_resize_request_event_t;
pub const XCB_PLACE_ON_TOP: c_int = 0;
pub const XCB_PLACE_ON_BOTTOM: c_int = 1;
pub const enum_xcb_place_t = c_uint;
pub const xcb_place_t = enum_xcb_place_t;
pub const struct_xcb_circulate_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    event: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    pad1: [4]u8 = @import("std").mem.zeroes([4]u8),
    place: u8 = @import("std").mem.zeroes(u8),
    pad2: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_circulate_notify_event_t = struct_xcb_circulate_notify_event_t;
pub const xcb_circulate_request_event_t = xcb_circulate_notify_event_t;
pub const XCB_PROPERTY_NEW_VALUE: c_int = 0;
pub const XCB_PROPERTY_DELETE: c_int = 1;
pub const enum_xcb_property_t = c_uint;
pub const xcb_property_t = enum_xcb_property_t;
pub const struct_xcb_property_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    atom: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    state: u8 = @import("std").mem.zeroes(u8),
    pad1: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_property_notify_event_t = struct_xcb_property_notify_event_t;
pub const struct_xcb_selection_clear_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    owner: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_selection_clear_event_t = struct_xcb_selection_clear_event_t;
pub const XCB_TIME_CURRENT_TIME: c_int = 0;
pub const enum_xcb_time_t = c_uint;
pub const xcb_time_t = enum_xcb_time_t;
pub const XCB_ATOM_NONE: c_int = 0;
pub const XCB_ATOM_ANY: c_int = 0;
pub const XCB_ATOM_PRIMARY: c_int = 1;
pub const XCB_ATOM_SECONDARY: c_int = 2;
pub const XCB_ATOM_ARC: c_int = 3;
pub const XCB_ATOM_ATOM: c_int = 4;
pub const XCB_ATOM_BITMAP: c_int = 5;
pub const XCB_ATOM_CARDINAL: c_int = 6;
pub const XCB_ATOM_COLORMAP: c_int = 7;
pub const XCB_ATOM_CURSOR: c_int = 8;
pub const XCB_ATOM_CUT_BUFFER0: c_int = 9;
pub const XCB_ATOM_CUT_BUFFER1: c_int = 10;
pub const XCB_ATOM_CUT_BUFFER2: c_int = 11;
pub const XCB_ATOM_CUT_BUFFER3: c_int = 12;
pub const XCB_ATOM_CUT_BUFFER4: c_int = 13;
pub const XCB_ATOM_CUT_BUFFER5: c_int = 14;
pub const XCB_ATOM_CUT_BUFFER6: c_int = 15;
pub const XCB_ATOM_CUT_BUFFER7: c_int = 16;
pub const XCB_ATOM_DRAWABLE: c_int = 17;
pub const XCB_ATOM_FONT: c_int = 18;
pub const XCB_ATOM_INTEGER: c_int = 19;
pub const XCB_ATOM_PIXMAP: c_int = 20;
pub const XCB_ATOM_POINT: c_int = 21;
pub const XCB_ATOM_RECTANGLE: c_int = 22;
pub const XCB_ATOM_RESOURCE_MANAGER: c_int = 23;
pub const XCB_ATOM_RGB_COLOR_MAP: c_int = 24;
pub const XCB_ATOM_RGB_BEST_MAP: c_int = 25;
pub const XCB_ATOM_RGB_BLUE_MAP: c_int = 26;
pub const XCB_ATOM_RGB_DEFAULT_MAP: c_int = 27;
pub const XCB_ATOM_RGB_GRAY_MAP: c_int = 28;
pub const XCB_ATOM_RGB_GREEN_MAP: c_int = 29;
pub const XCB_ATOM_RGB_RED_MAP: c_int = 30;
pub const XCB_ATOM_STRING: c_int = 31;
pub const XCB_ATOM_VISUALID: c_int = 32;
pub const XCB_ATOM_WINDOW: c_int = 33;
pub const XCB_ATOM_WM_COMMAND: c_int = 34;
pub const XCB_ATOM_WM_HINTS: c_int = 35;
pub const XCB_ATOM_WM_CLIENT_MACHINE: c_int = 36;
pub const XCB_ATOM_WM_ICON_NAME: c_int = 37;
pub const XCB_ATOM_WM_ICON_SIZE: c_int = 38;
pub const XCB_ATOM_WM_NAME: c_int = 39;
pub const XCB_ATOM_WM_NORMAL_HINTS: c_int = 40;
pub const XCB_ATOM_WM_SIZE_HINTS: c_int = 41;
pub const XCB_ATOM_WM_ZOOM_HINTS: c_int = 42;
pub const XCB_ATOM_MIN_SPACE: c_int = 43;
pub const XCB_ATOM_NORM_SPACE: c_int = 44;
pub const XCB_ATOM_MAX_SPACE: c_int = 45;
pub const XCB_ATOM_END_SPACE: c_int = 46;
pub const XCB_ATOM_SUPERSCRIPT_X: c_int = 47;
pub const XCB_ATOM_SUPERSCRIPT_Y: c_int = 48;
pub const XCB_ATOM_SUBSCRIPT_X: c_int = 49;
pub const XCB_ATOM_SUBSCRIPT_Y: c_int = 50;
pub const XCB_ATOM_UNDERLINE_POSITION: c_int = 51;
pub const XCB_ATOM_UNDERLINE_THICKNESS: c_int = 52;
pub const XCB_ATOM_STRIKEOUT_ASCENT: c_int = 53;
pub const XCB_ATOM_STRIKEOUT_DESCENT: c_int = 54;
pub const XCB_ATOM_ITALIC_ANGLE: c_int = 55;
pub const XCB_ATOM_X_HEIGHT: c_int = 56;
pub const XCB_ATOM_QUAD_WIDTH: c_int = 57;
pub const XCB_ATOM_WEIGHT: c_int = 58;
pub const XCB_ATOM_POINT_SIZE: c_int = 59;
pub const XCB_ATOM_RESOLUTION: c_int = 60;
pub const XCB_ATOM_COPYRIGHT: c_int = 61;
pub const XCB_ATOM_NOTICE: c_int = 62;
pub const XCB_ATOM_FONT_NAME: c_int = 63;
pub const XCB_ATOM_FAMILY_NAME: c_int = 64;
pub const XCB_ATOM_FULL_NAME: c_int = 65;
pub const XCB_ATOM_CAP_HEIGHT: c_int = 66;
pub const XCB_ATOM_WM_CLASS: c_int = 67;
pub const XCB_ATOM_WM_TRANSIENT_FOR: c_int = 68;
pub const enum_xcb_atom_enum_t = c_uint;
pub const xcb_atom_enum_t = enum_xcb_atom_enum_t;
pub const struct_xcb_selection_request_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    owner: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    requestor: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    target: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_selection_request_event_t = struct_xcb_selection_request_event_t;
pub const struct_xcb_selection_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    requestor: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    target: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_selection_notify_event_t = struct_xcb_selection_notify_event_t;
pub const XCB_COLORMAP_STATE_UNINSTALLED: c_int = 0;
pub const XCB_COLORMAP_STATE_INSTALLED: c_int = 1;
pub const enum_xcb_colormap_state_t = c_uint;
pub const xcb_colormap_state_t = enum_xcb_colormap_state_t;
pub const XCB_COLORMAP_NONE: c_int = 0;
pub const enum_xcb_colormap_enum_t = c_uint;
pub const xcb_colormap_enum_t = enum_xcb_colormap_enum_t;
pub const struct_xcb_colormap_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    colormap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    _new: u8 = @import("std").mem.zeroes(u8),
    state: u8 = @import("std").mem.zeroes(u8),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_colormap_notify_event_t = struct_xcb_colormap_notify_event_t;
pub const union_xcb_client_message_data_t = extern union {
    data8: [20]u8,
    data16: [10]u16,
    data32: [5]u32,
};
pub const xcb_client_message_data_t = union_xcb_client_message_data_t;
pub const struct_xcb_client_message_data_iterator_t = extern struct {
    data: [*c]xcb_client_message_data_t = @import("std").mem.zeroes([*c]xcb_client_message_data_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_client_message_data_iterator_t = struct_xcb_client_message_data_iterator_t;
pub const struct_xcb_client_message_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    format: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    type: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    data: xcb_client_message_data_t = @import("std").mem.zeroes(xcb_client_message_data_t),
};
pub const xcb_client_message_event_t = struct_xcb_client_message_event_t;
pub const XCB_MAPPING_MODIFIER: c_int = 0;
pub const XCB_MAPPING_KEYBOARD: c_int = 1;
pub const XCB_MAPPING_POINTER: c_int = 2;
pub const enum_xcb_mapping_t = c_uint;
pub const xcb_mapping_t = enum_xcb_mapping_t;
pub const struct_xcb_mapping_notify_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    request: u8 = @import("std").mem.zeroes(u8),
    first_keycode: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    count: u8 = @import("std").mem.zeroes(u8),
    pad1: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_mapping_notify_event_t = struct_xcb_mapping_notify_event_t;
pub const struct_xcb_ge_generic_event_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    extension: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    event_type: u16 = @import("std").mem.zeroes(u16),
    pad0: [22]u8 = @import("std").mem.zeroes([22]u8),
    full_sequence: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_ge_generic_event_t = struct_xcb_ge_generic_event_t;
pub const struct_xcb_request_error_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    error_code: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    bad_value: u32 = @import("std").mem.zeroes(u32),
    minor_opcode: u16 = @import("std").mem.zeroes(u16),
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_request_error_t = struct_xcb_request_error_t;
pub const struct_xcb_value_error_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    error_code: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    bad_value: u32 = @import("std").mem.zeroes(u32),
    minor_opcode: u16 = @import("std").mem.zeroes(u16),
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_value_error_t = struct_xcb_value_error_t;
pub const xcb_window_error_t = xcb_value_error_t;
pub const xcb_pixmap_error_t = xcb_value_error_t;
pub const xcb_atom_error_t = xcb_value_error_t;
pub const xcb_cursor_error_t = xcb_value_error_t;
pub const xcb_font_error_t = xcb_value_error_t;
pub const xcb_match_error_t = xcb_request_error_t;
pub const xcb_drawable_error_t = xcb_value_error_t;
pub const xcb_access_error_t = xcb_request_error_t;
pub const xcb_alloc_error_t = xcb_request_error_t;
pub const xcb_colormap_error_t = xcb_value_error_t;
pub const xcb_g_context_error_t = xcb_value_error_t;
pub const xcb_id_choice_error_t = xcb_value_error_t;
pub const xcb_name_error_t = xcb_request_error_t;
pub const xcb_length_error_t = xcb_request_error_t;
pub const xcb_implementation_error_t = xcb_request_error_t;
pub const XCB_WINDOW_CLASS_COPY_FROM_PARENT: c_int = 0;
pub const XCB_WINDOW_CLASS_INPUT_OUTPUT: c_int = 1;
pub const XCB_WINDOW_CLASS_INPUT_ONLY: c_int = 2;
pub const enum_xcb_window_class_t = c_uint;
pub const xcb_window_class_t = enum_xcb_window_class_t;
pub const XCB_CW_BACK_PIXMAP: c_int = 1;
pub const XCB_CW_BACK_PIXEL: c_int = 2;
pub const XCB_CW_BORDER_PIXMAP: c_int = 4;
pub const XCB_CW_BORDER_PIXEL: c_int = 8;
pub const XCB_CW_BIT_GRAVITY: c_int = 16;
pub const XCB_CW_WIN_GRAVITY: c_int = 32;
pub const XCB_CW_BACKING_STORE: c_int = 64;
pub const XCB_CW_BACKING_PLANES: c_int = 128;
pub const XCB_CW_BACKING_PIXEL: c_int = 256;
pub const XCB_CW_OVERRIDE_REDIRECT: c_int = 512;
pub const XCB_CW_SAVE_UNDER: c_int = 1024;
pub const XCB_CW_EVENT_MASK: c_int = 2048;
pub const XCB_CW_DONT_PROPAGATE: c_int = 4096;
pub const XCB_CW_COLORMAP: c_int = 8192;
pub const XCB_CW_CURSOR: c_int = 16384;
pub const enum_xcb_cw_t = c_uint;
pub const xcb_cw_t = enum_xcb_cw_t;
pub const XCB_BACK_PIXMAP_NONE: c_int = 0;
pub const XCB_BACK_PIXMAP_PARENT_RELATIVE: c_int = 1;
pub const enum_xcb_back_pixmap_t = c_uint;
pub const xcb_back_pixmap_t = enum_xcb_back_pixmap_t;
pub const XCB_GRAVITY_BIT_FORGET: c_int = 0;
pub const XCB_GRAVITY_WIN_UNMAP: c_int = 0;
pub const XCB_GRAVITY_NORTH_WEST: c_int = 1;
pub const XCB_GRAVITY_NORTH: c_int = 2;
pub const XCB_GRAVITY_NORTH_EAST: c_int = 3;
pub const XCB_GRAVITY_WEST: c_int = 4;
pub const XCB_GRAVITY_CENTER: c_int = 5;
pub const XCB_GRAVITY_EAST: c_int = 6;
pub const XCB_GRAVITY_SOUTH_WEST: c_int = 7;
pub const XCB_GRAVITY_SOUTH: c_int = 8;
pub const XCB_GRAVITY_SOUTH_EAST: c_int = 9;
pub const XCB_GRAVITY_STATIC: c_int = 10;
pub const enum_xcb_gravity_t = c_uint;
pub const xcb_gravity_t = enum_xcb_gravity_t;
pub const struct_xcb_create_window_value_list_t = extern struct {
    background_pixmap: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    background_pixel: u32 = @import("std").mem.zeroes(u32),
    border_pixmap: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    border_pixel: u32 = @import("std").mem.zeroes(u32),
    bit_gravity: u32 = @import("std").mem.zeroes(u32),
    win_gravity: u32 = @import("std").mem.zeroes(u32),
    backing_store: u32 = @import("std").mem.zeroes(u32),
    backing_planes: u32 = @import("std").mem.zeroes(u32),
    backing_pixel: u32 = @import("std").mem.zeroes(u32),
    override_redirect: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    save_under: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    event_mask: u32 = @import("std").mem.zeroes(u32),
    do_not_propogate_mask: u32 = @import("std").mem.zeroes(u32),
    colormap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
};
pub const xcb_create_window_value_list_t = struct_xcb_create_window_value_list_t;
pub const struct_xcb_create_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    depth: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    wid: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    border_width: u16 = @import("std").mem.zeroes(u16),
    _class: u16 = @import("std").mem.zeroes(u16),
    visual: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_create_window_request_t = struct_xcb_create_window_request_t;
pub const struct_xcb_change_window_attributes_value_list_t = extern struct {
    background_pixmap: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    background_pixel: u32 = @import("std").mem.zeroes(u32),
    border_pixmap: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    border_pixel: u32 = @import("std").mem.zeroes(u32),
    bit_gravity: u32 = @import("std").mem.zeroes(u32),
    win_gravity: u32 = @import("std").mem.zeroes(u32),
    backing_store: u32 = @import("std").mem.zeroes(u32),
    backing_planes: u32 = @import("std").mem.zeroes(u32),
    backing_pixel: u32 = @import("std").mem.zeroes(u32),
    override_redirect: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    save_under: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    event_mask: u32 = @import("std").mem.zeroes(u32),
    do_not_propogate_mask: u32 = @import("std").mem.zeroes(u32),
    colormap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
};
pub const xcb_change_window_attributes_value_list_t = struct_xcb_change_window_attributes_value_list_t;
pub const struct_xcb_change_window_attributes_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_window_attributes_request_t = struct_xcb_change_window_attributes_request_t;
pub const XCB_MAP_STATE_UNMAPPED: c_int = 0;
pub const XCB_MAP_STATE_UNVIEWABLE: c_int = 1;
pub const XCB_MAP_STATE_VIEWABLE: c_int = 2;
pub const enum_xcb_map_state_t = c_uint;
pub const xcb_map_state_t = enum_xcb_map_state_t;
pub const struct_xcb_get_window_attributes_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_window_attributes_cookie_t = struct_xcb_get_window_attributes_cookie_t;
pub const struct_xcb_get_window_attributes_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_get_window_attributes_request_t = struct_xcb_get_window_attributes_request_t;
pub const struct_xcb_get_window_attributes_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    backing_store: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    visual: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
    _class: u16 = @import("std").mem.zeroes(u16),
    bit_gravity: u8 = @import("std").mem.zeroes(u8),
    win_gravity: u8 = @import("std").mem.zeroes(u8),
    backing_planes: u32 = @import("std").mem.zeroes(u32),
    backing_pixel: u32 = @import("std").mem.zeroes(u32),
    save_under: u8 = @import("std").mem.zeroes(u8),
    map_is_installed: u8 = @import("std").mem.zeroes(u8),
    map_state: u8 = @import("std").mem.zeroes(u8),
    override_redirect: u8 = @import("std").mem.zeroes(u8),
    colormap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    all_event_masks: u32 = @import("std").mem.zeroes(u32),
    your_event_mask: u32 = @import("std").mem.zeroes(u32),
    do_not_propagate_mask: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_get_window_attributes_reply_t = struct_xcb_get_window_attributes_reply_t;
pub const struct_xcb_destroy_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_destroy_window_request_t = struct_xcb_destroy_window_request_t;
pub const struct_xcb_destroy_subwindows_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_destroy_subwindows_request_t = struct_xcb_destroy_subwindows_request_t;
pub const XCB_SET_MODE_INSERT: c_int = 0;
pub const XCB_SET_MODE_DELETE: c_int = 1;
pub const enum_xcb_set_mode_t = c_uint;
pub const xcb_set_mode_t = enum_xcb_set_mode_t;
pub const struct_xcb_change_save_set_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_change_save_set_request_t = struct_xcb_change_save_set_request_t;
pub const struct_xcb_reparent_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_reparent_window_request_t = struct_xcb_reparent_window_request_t;
pub const struct_xcb_map_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_map_window_request_t = struct_xcb_map_window_request_t;
pub const struct_xcb_map_subwindows_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_map_subwindows_request_t = struct_xcb_map_subwindows_request_t;
pub const struct_xcb_unmap_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_unmap_window_request_t = struct_xcb_unmap_window_request_t;
pub const struct_xcb_unmap_subwindows_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_unmap_subwindows_request_t = struct_xcb_unmap_subwindows_request_t;
pub const XCB_CONFIG_WINDOW_X: c_int = 1;
pub const XCB_CONFIG_WINDOW_Y: c_int = 2;
pub const XCB_CONFIG_WINDOW_WIDTH: c_int = 4;
pub const XCB_CONFIG_WINDOW_HEIGHT: c_int = 8;
pub const XCB_CONFIG_WINDOW_BORDER_WIDTH: c_int = 16;
pub const XCB_CONFIG_WINDOW_SIBLING: c_int = 32;
pub const XCB_CONFIG_WINDOW_STACK_MODE: c_int = 64;
pub const enum_xcb_config_window_t = c_uint;
pub const xcb_config_window_t = enum_xcb_config_window_t;
pub const XCB_STACK_MODE_ABOVE: c_int = 0;
pub const XCB_STACK_MODE_BELOW: c_int = 1;
pub const XCB_STACK_MODE_TOP_IF: c_int = 2;
pub const XCB_STACK_MODE_BOTTOM_IF: c_int = 3;
pub const XCB_STACK_MODE_OPPOSITE: c_int = 4;
pub const enum_xcb_stack_mode_t = c_uint;
pub const xcb_stack_mode_t = enum_xcb_stack_mode_t;
pub const struct_xcb_configure_window_value_list_t = extern struct {
    x: i32 = @import("std").mem.zeroes(i32),
    y: i32 = @import("std").mem.zeroes(i32),
    width: u32 = @import("std").mem.zeroes(u32),
    height: u32 = @import("std").mem.zeroes(u32),
    border_width: u32 = @import("std").mem.zeroes(u32),
    sibling: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    stack_mode: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_configure_window_value_list_t = struct_xcb_configure_window_value_list_t;
pub const struct_xcb_configure_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    value_mask: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_configure_window_request_t = struct_xcb_configure_window_request_t;
pub const XCB_CIRCULATE_RAISE_LOWEST: c_int = 0;
pub const XCB_CIRCULATE_LOWER_HIGHEST: c_int = 1;
pub const enum_xcb_circulate_t = c_uint;
pub const xcb_circulate_t = enum_xcb_circulate_t;
pub const struct_xcb_circulate_window_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    direction: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_circulate_window_request_t = struct_xcb_circulate_window_request_t;
pub const struct_xcb_get_geometry_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_geometry_cookie_t = struct_xcb_get_geometry_cookie_t;
pub const struct_xcb_get_geometry_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
};
pub const xcb_get_geometry_request_t = struct_xcb_get_geometry_request_t;
pub const struct_xcb_get_geometry_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    depth: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    border_width: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_get_geometry_reply_t = struct_xcb_get_geometry_reply_t;
pub const struct_xcb_query_tree_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_tree_cookie_t = struct_xcb_query_tree_cookie_t;
pub const struct_xcb_query_tree_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_query_tree_request_t = struct_xcb_query_tree_request_t;
pub const struct_xcb_query_tree_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    parent: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    children_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [14]u8 = @import("std").mem.zeroes([14]u8),
};
pub const xcb_query_tree_reply_t = struct_xcb_query_tree_reply_t;
pub const struct_xcb_intern_atom_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_intern_atom_cookie_t = struct_xcb_intern_atom_cookie_t;
pub const struct_xcb_intern_atom_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    only_if_exists: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_intern_atom_request_t = struct_xcb_intern_atom_request_t;
pub const struct_xcb_intern_atom_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    atom: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_intern_atom_reply_t = struct_xcb_intern_atom_reply_t;
pub const struct_xcb_get_atom_name_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_atom_name_cookie_t = struct_xcb_get_atom_name_cookie_t;
pub const struct_xcb_get_atom_name_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    atom: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_get_atom_name_request_t = struct_xcb_get_atom_name_request_t;
pub const struct_xcb_get_atom_name_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_get_atom_name_reply_t = struct_xcb_get_atom_name_reply_t;
pub const XCB_PROP_MODE_REPLACE: c_int = 0;
pub const XCB_PROP_MODE_PREPEND: c_int = 1;
pub const XCB_PROP_MODE_APPEND: c_int = 2;
pub const enum_xcb_prop_mode_t = c_uint;
pub const xcb_prop_mode_t = enum_xcb_prop_mode_t;
pub const struct_xcb_change_property_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    type: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    format: u8 = @import("std").mem.zeroes(u8),
    pad0: [3]u8 = @import("std").mem.zeroes([3]u8),
    data_len: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_property_request_t = struct_xcb_change_property_request_t;
pub const struct_xcb_delete_property_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_delete_property_request_t = struct_xcb_delete_property_request_t;
pub const XCB_GET_PROPERTY_TYPE_ANY: c_int = 0;
pub const enum_xcb_get_property_type_t = c_uint;
pub const xcb_get_property_type_t = enum_xcb_get_property_type_t;
pub const struct_xcb_get_property_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_property_cookie_t = struct_xcb_get_property_cookie_t;
pub const struct_xcb_get_property_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    _delete: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    type: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    long_offset: u32 = @import("std").mem.zeroes(u32),
    long_length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_get_property_request_t = struct_xcb_get_property_request_t;
pub const struct_xcb_get_property_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    format: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    type: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    bytes_after: u32 = @import("std").mem.zeroes(u32),
    value_len: u32 = @import("std").mem.zeroes(u32),
    pad0: [12]u8 = @import("std").mem.zeroes([12]u8),
};
pub const xcb_get_property_reply_t = struct_xcb_get_property_reply_t;
pub const struct_xcb_list_properties_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_properties_cookie_t = struct_xcb_list_properties_cookie_t;
pub const struct_xcb_list_properties_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_list_properties_request_t = struct_xcb_list_properties_request_t;
pub const struct_xcb_list_properties_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    atoms_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_list_properties_reply_t = struct_xcb_list_properties_reply_t;
pub const struct_xcb_set_selection_owner_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    owner: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_set_selection_owner_request_t = struct_xcb_set_selection_owner_request_t;
pub const struct_xcb_get_selection_owner_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_selection_owner_cookie_t = struct_xcb_get_selection_owner_cookie_t;
pub const struct_xcb_get_selection_owner_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
};
pub const xcb_get_selection_owner_request_t = struct_xcb_get_selection_owner_request_t;
pub const struct_xcb_get_selection_owner_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    owner: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_get_selection_owner_reply_t = struct_xcb_get_selection_owner_reply_t;
pub const struct_xcb_convert_selection_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    requestor: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    selection: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    target: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    property: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_convert_selection_request_t = struct_xcb_convert_selection_request_t;
pub const XCB_SEND_EVENT_DEST_POINTER_WINDOW: c_int = 0;
pub const XCB_SEND_EVENT_DEST_ITEM_FOCUS: c_int = 1;
pub const enum_xcb_send_event_dest_t = c_uint;
pub const xcb_send_event_dest_t = enum_xcb_send_event_dest_t;
pub const struct_xcb_send_event_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    propagate: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    destination: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event_mask: u32 = @import("std").mem.zeroes(u32),
    event: [32]u8 = @import("std").mem.zeroes([32]u8),
};
pub const xcb_send_event_request_t = struct_xcb_send_event_request_t;
pub const XCB_GRAB_MODE_SYNC: c_int = 0;
pub const XCB_GRAB_MODE_ASYNC: c_int = 1;
pub const enum_xcb_grab_mode_t = c_uint;
pub const xcb_grab_mode_t = enum_xcb_grab_mode_t;
pub const XCB_GRAB_STATUS_SUCCESS: c_int = 0;
pub const XCB_GRAB_STATUS_ALREADY_GRABBED: c_int = 1;
pub const XCB_GRAB_STATUS_INVALID_TIME: c_int = 2;
pub const XCB_GRAB_STATUS_NOT_VIEWABLE: c_int = 3;
pub const XCB_GRAB_STATUS_FROZEN: c_int = 4;
pub const enum_xcb_grab_status_t = c_uint;
pub const xcb_grab_status_t = enum_xcb_grab_status_t;
pub const XCB_CURSOR_NONE: c_int = 0;
pub const enum_xcb_cursor_enum_t = c_uint;
pub const xcb_cursor_enum_t = enum_xcb_cursor_enum_t;
pub const struct_xcb_grab_pointer_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_grab_pointer_cookie_t = struct_xcb_grab_pointer_cookie_t;
pub const struct_xcb_grab_pointer_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    owner_events: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event_mask: u16 = @import("std").mem.zeroes(u16),
    pointer_mode: u8 = @import("std").mem.zeroes(u8),
    keyboard_mode: u8 = @import("std").mem.zeroes(u8),
    confine_to: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_grab_pointer_request_t = struct_xcb_grab_pointer_request_t;
pub const struct_xcb_grab_pointer_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    status: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_grab_pointer_reply_t = struct_xcb_grab_pointer_reply_t;
pub const struct_xcb_ungrab_pointer_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_ungrab_pointer_request_t = struct_xcb_ungrab_pointer_request_t;
pub const XCB_BUTTON_INDEX_ANY: c_int = 0;
pub const XCB_BUTTON_INDEX_1: c_int = 1;
pub const XCB_BUTTON_INDEX_2: c_int = 2;
pub const XCB_BUTTON_INDEX_3: c_int = 3;
pub const XCB_BUTTON_INDEX_4: c_int = 4;
pub const XCB_BUTTON_INDEX_5: c_int = 5;
pub const enum_xcb_button_index_t = c_uint;
pub const xcb_button_index_t = enum_xcb_button_index_t;
pub const struct_xcb_grab_button_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    owner_events: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    event_mask: u16 = @import("std").mem.zeroes(u16),
    pointer_mode: u8 = @import("std").mem.zeroes(u8),
    keyboard_mode: u8 = @import("std").mem.zeroes(u8),
    confine_to: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    button: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    modifiers: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_grab_button_request_t = struct_xcb_grab_button_request_t;
pub const struct_xcb_ungrab_button_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    button: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    modifiers: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_ungrab_button_request_t = struct_xcb_ungrab_button_request_t;
pub const struct_xcb_change_active_pointer_grab_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    event_mask: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_change_active_pointer_grab_request_t = struct_xcb_change_active_pointer_grab_request_t;
pub const struct_xcb_grab_keyboard_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_grab_keyboard_cookie_t = struct_xcb_grab_keyboard_cookie_t;
pub const struct_xcb_grab_keyboard_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    owner_events: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    pointer_mode: u8 = @import("std").mem.zeroes(u8),
    keyboard_mode: u8 = @import("std").mem.zeroes(u8),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_grab_keyboard_request_t = struct_xcb_grab_keyboard_request_t;
pub const struct_xcb_grab_keyboard_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    status: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_grab_keyboard_reply_t = struct_xcb_grab_keyboard_reply_t;
pub const struct_xcb_ungrab_keyboard_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_ungrab_keyboard_request_t = struct_xcb_ungrab_keyboard_request_t;
pub const XCB_GRAB_ANY: c_int = 0;
pub const enum_xcb_grab_t = c_uint;
pub const xcb_grab_t = enum_xcb_grab_t;
pub const struct_xcb_grab_key_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    owner_events: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    modifiers: u16 = @import("std").mem.zeroes(u16),
    key: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    pointer_mode: u8 = @import("std").mem.zeroes(u8),
    keyboard_mode: u8 = @import("std").mem.zeroes(u8),
    pad0: [3]u8 = @import("std").mem.zeroes([3]u8),
};
pub const xcb_grab_key_request_t = struct_xcb_grab_key_request_t;
pub const struct_xcb_ungrab_key_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    key: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    length: u16 = @import("std").mem.zeroes(u16),
    grab_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    modifiers: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_ungrab_key_request_t = struct_xcb_ungrab_key_request_t;
pub const XCB_ALLOW_ASYNC_POINTER: c_int = 0;
pub const XCB_ALLOW_SYNC_POINTER: c_int = 1;
pub const XCB_ALLOW_REPLAY_POINTER: c_int = 2;
pub const XCB_ALLOW_ASYNC_KEYBOARD: c_int = 3;
pub const XCB_ALLOW_SYNC_KEYBOARD: c_int = 4;
pub const XCB_ALLOW_REPLAY_KEYBOARD: c_int = 5;
pub const XCB_ALLOW_ASYNC_BOTH: c_int = 6;
pub const XCB_ALLOW_SYNC_BOTH: c_int = 7;
pub const enum_xcb_allow_t = c_uint;
pub const xcb_allow_t = enum_xcb_allow_t;
pub const struct_xcb_allow_events_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_allow_events_request_t = struct_xcb_allow_events_request_t;
pub const struct_xcb_grab_server_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_grab_server_request_t = struct_xcb_grab_server_request_t;
pub const struct_xcb_ungrab_server_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_ungrab_server_request_t = struct_xcb_ungrab_server_request_t;
pub const struct_xcb_query_pointer_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_pointer_cookie_t = struct_xcb_query_pointer_cookie_t;
pub const struct_xcb_query_pointer_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_query_pointer_request_t = struct_xcb_query_pointer_request_t;
pub const struct_xcb_query_pointer_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    same_screen: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    root: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    root_x: i16 = @import("std").mem.zeroes(i16),
    root_y: i16 = @import("std").mem.zeroes(i16),
    win_x: i16 = @import("std").mem.zeroes(i16),
    win_y: i16 = @import("std").mem.zeroes(i16),
    mask: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_query_pointer_reply_t = struct_xcb_query_pointer_reply_t;
pub const struct_xcb_timecoord_t = extern struct {
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_timecoord_t = struct_xcb_timecoord_t;
pub const struct_xcb_timecoord_iterator_t = extern struct {
    data: [*c]xcb_timecoord_t = @import("std").mem.zeroes([*c]xcb_timecoord_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_timecoord_iterator_t = struct_xcb_timecoord_iterator_t;
pub const struct_xcb_get_motion_events_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_motion_events_cookie_t = struct_xcb_get_motion_events_cookie_t;
pub const struct_xcb_get_motion_events_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    start: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
    stop: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_get_motion_events_request_t = struct_xcb_get_motion_events_request_t;
pub const struct_xcb_get_motion_events_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    events_len: u32 = @import("std").mem.zeroes(u32),
    pad1: [20]u8 = @import("std").mem.zeroes([20]u8),
};
pub const xcb_get_motion_events_reply_t = struct_xcb_get_motion_events_reply_t;
pub const struct_xcb_translate_coordinates_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_translate_coordinates_cookie_t = struct_xcb_translate_coordinates_cookie_t;
pub const struct_xcb_translate_coordinates_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    src_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    dst_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    src_x: i16 = @import("std").mem.zeroes(i16),
    src_y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_translate_coordinates_request_t = struct_xcb_translate_coordinates_request_t;
pub const struct_xcb_translate_coordinates_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    same_screen: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    child: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    dst_x: i16 = @import("std").mem.zeroes(i16),
    dst_y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_translate_coordinates_reply_t = struct_xcb_translate_coordinates_reply_t;
pub const struct_xcb_warp_pointer_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    src_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    dst_window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    src_x: i16 = @import("std").mem.zeroes(i16),
    src_y: i16 = @import("std").mem.zeroes(i16),
    src_width: u16 = @import("std").mem.zeroes(u16),
    src_height: u16 = @import("std").mem.zeroes(u16),
    dst_x: i16 = @import("std").mem.zeroes(i16),
    dst_y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_warp_pointer_request_t = struct_xcb_warp_pointer_request_t;
pub const XCB_INPUT_FOCUS_NONE: c_int = 0;
pub const XCB_INPUT_FOCUS_POINTER_ROOT: c_int = 1;
pub const XCB_INPUT_FOCUS_PARENT: c_int = 2;
pub const XCB_INPUT_FOCUS_FOLLOW_KEYBOARD: c_int = 3;
pub const enum_xcb_input_focus_t = c_uint;
pub const xcb_input_focus_t = enum_xcb_input_focus_t;
pub const struct_xcb_set_input_focus_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    revert_to: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    focus: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    time: xcb_timestamp_t = @import("std").mem.zeroes(xcb_timestamp_t),
};
pub const xcb_set_input_focus_request_t = struct_xcb_set_input_focus_request_t;
pub const struct_xcb_get_input_focus_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_input_focus_cookie_t = struct_xcb_get_input_focus_cookie_t;
pub const struct_xcb_get_input_focus_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_input_focus_request_t = struct_xcb_get_input_focus_request_t;
pub const struct_xcb_get_input_focus_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    revert_to: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    focus: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_get_input_focus_reply_t = struct_xcb_get_input_focus_reply_t;
pub const struct_xcb_query_keymap_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_keymap_cookie_t = struct_xcb_query_keymap_cookie_t;
pub const struct_xcb_query_keymap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_query_keymap_request_t = struct_xcb_query_keymap_request_t;
pub const struct_xcb_query_keymap_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    keys: [32]u8 = @import("std").mem.zeroes([32]u8),
};
pub const xcb_query_keymap_reply_t = struct_xcb_query_keymap_reply_t;
pub const struct_xcb_open_font_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    fid: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_open_font_request_t = struct_xcb_open_font_request_t;
pub const struct_xcb_close_font_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    font: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
};
pub const xcb_close_font_request_t = struct_xcb_close_font_request_t;
pub const XCB_FONT_DRAW_LEFT_TO_RIGHT: c_int = 0;
pub const XCB_FONT_DRAW_RIGHT_TO_LEFT: c_int = 1;
pub const enum_xcb_font_draw_t = c_uint;
pub const xcb_font_draw_t = enum_xcb_font_draw_t;
pub const struct_xcb_fontprop_t = extern struct {
    name: xcb_atom_t = @import("std").mem.zeroes(xcb_atom_t),
    value: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_fontprop_t = struct_xcb_fontprop_t;
pub const struct_xcb_fontprop_iterator_t = extern struct {
    data: [*c]xcb_fontprop_t = @import("std").mem.zeroes([*c]xcb_fontprop_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_fontprop_iterator_t = struct_xcb_fontprop_iterator_t;
pub const struct_xcb_charinfo_t = extern struct {
    left_side_bearing: i16 = @import("std").mem.zeroes(i16),
    right_side_bearing: i16 = @import("std").mem.zeroes(i16),
    character_width: i16 = @import("std").mem.zeroes(i16),
    ascent: i16 = @import("std").mem.zeroes(i16),
    descent: i16 = @import("std").mem.zeroes(i16),
    attributes: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_charinfo_t = struct_xcb_charinfo_t;
pub const struct_xcb_charinfo_iterator_t = extern struct {
    data: [*c]xcb_charinfo_t = @import("std").mem.zeroes([*c]xcb_charinfo_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_charinfo_iterator_t = struct_xcb_charinfo_iterator_t;
pub const struct_xcb_query_font_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_font_cookie_t = struct_xcb_query_font_cookie_t;
pub const struct_xcb_query_font_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    font: xcb_fontable_t = @import("std").mem.zeroes(xcb_fontable_t),
};
pub const xcb_query_font_request_t = struct_xcb_query_font_request_t;
pub const struct_xcb_query_font_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    min_bounds: xcb_charinfo_t = @import("std").mem.zeroes(xcb_charinfo_t),
    pad1: [4]u8 = @import("std").mem.zeroes([4]u8),
    max_bounds: xcb_charinfo_t = @import("std").mem.zeroes(xcb_charinfo_t),
    pad2: [4]u8 = @import("std").mem.zeroes([4]u8),
    min_char_or_byte2: u16 = @import("std").mem.zeroes(u16),
    max_char_or_byte2: u16 = @import("std").mem.zeroes(u16),
    default_char: u16 = @import("std").mem.zeroes(u16),
    properties_len: u16 = @import("std").mem.zeroes(u16),
    draw_direction: u8 = @import("std").mem.zeroes(u8),
    min_byte1: u8 = @import("std").mem.zeroes(u8),
    max_byte1: u8 = @import("std").mem.zeroes(u8),
    all_chars_exist: u8 = @import("std").mem.zeroes(u8),
    font_ascent: i16 = @import("std").mem.zeroes(i16),
    font_descent: i16 = @import("std").mem.zeroes(i16),
    char_infos_len: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_query_font_reply_t = struct_xcb_query_font_reply_t;
pub const struct_xcb_query_text_extents_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_text_extents_cookie_t = struct_xcb_query_text_extents_cookie_t;
pub const struct_xcb_query_text_extents_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    odd_length: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    font: xcb_fontable_t = @import("std").mem.zeroes(xcb_fontable_t),
};
pub const xcb_query_text_extents_request_t = struct_xcb_query_text_extents_request_t;
pub const struct_xcb_query_text_extents_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    draw_direction: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    font_ascent: i16 = @import("std").mem.zeroes(i16),
    font_descent: i16 = @import("std").mem.zeroes(i16),
    overall_ascent: i16 = @import("std").mem.zeroes(i16),
    overall_descent: i16 = @import("std").mem.zeroes(i16),
    overall_width: i32 = @import("std").mem.zeroes(i32),
    overall_left: i32 = @import("std").mem.zeroes(i32),
    overall_right: i32 = @import("std").mem.zeroes(i32),
};
pub const xcb_query_text_extents_reply_t = struct_xcb_query_text_extents_reply_t;
pub const struct_xcb_str_t = extern struct {
    name_len: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_str_t = struct_xcb_str_t;
pub const struct_xcb_str_iterator_t = extern struct {
    data: [*c]xcb_str_t = @import("std").mem.zeroes([*c]xcb_str_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_str_iterator_t = struct_xcb_str_iterator_t;
pub const struct_xcb_list_fonts_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_fonts_cookie_t = struct_xcb_list_fonts_cookie_t;
pub const struct_xcb_list_fonts_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    max_names: u16 = @import("std").mem.zeroes(u16),
    pattern_len: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_list_fonts_request_t = struct_xcb_list_fonts_request_t;
pub const struct_xcb_list_fonts_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    names_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_list_fonts_reply_t = struct_xcb_list_fonts_reply_t;
pub const struct_xcb_list_fonts_with_info_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_fonts_with_info_cookie_t = struct_xcb_list_fonts_with_info_cookie_t;
pub const struct_xcb_list_fonts_with_info_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    max_names: u16 = @import("std").mem.zeroes(u16),
    pattern_len: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_list_fonts_with_info_request_t = struct_xcb_list_fonts_with_info_request_t;
pub const struct_xcb_list_fonts_with_info_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    name_len: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    min_bounds: xcb_charinfo_t = @import("std").mem.zeroes(xcb_charinfo_t),
    pad0: [4]u8 = @import("std").mem.zeroes([4]u8),
    max_bounds: xcb_charinfo_t = @import("std").mem.zeroes(xcb_charinfo_t),
    pad1: [4]u8 = @import("std").mem.zeroes([4]u8),
    min_char_or_byte2: u16 = @import("std").mem.zeroes(u16),
    max_char_or_byte2: u16 = @import("std").mem.zeroes(u16),
    default_char: u16 = @import("std").mem.zeroes(u16),
    properties_len: u16 = @import("std").mem.zeroes(u16),
    draw_direction: u8 = @import("std").mem.zeroes(u8),
    min_byte1: u8 = @import("std").mem.zeroes(u8),
    max_byte1: u8 = @import("std").mem.zeroes(u8),
    all_chars_exist: u8 = @import("std").mem.zeroes(u8),
    font_ascent: i16 = @import("std").mem.zeroes(i16),
    font_descent: i16 = @import("std").mem.zeroes(i16),
    replies_hint: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_list_fonts_with_info_reply_t = struct_xcb_list_fonts_with_info_reply_t;
pub const struct_xcb_set_font_path_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    font_qty: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_set_font_path_request_t = struct_xcb_set_font_path_request_t;
pub const struct_xcb_get_font_path_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_font_path_cookie_t = struct_xcb_get_font_path_cookie_t;
pub const struct_xcb_get_font_path_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_font_path_request_t = struct_xcb_get_font_path_request_t;
pub const struct_xcb_get_font_path_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    path_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_get_font_path_reply_t = struct_xcb_get_font_path_reply_t;
pub const struct_xcb_create_pixmap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    depth: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    pid: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_create_pixmap_request_t = struct_xcb_create_pixmap_request_t;
pub const struct_xcb_free_pixmap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    pixmap: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
};
pub const xcb_free_pixmap_request_t = struct_xcb_free_pixmap_request_t;
pub const XCB_GC_FUNCTION: c_int = 1;
pub const XCB_GC_PLANE_MASK: c_int = 2;
pub const XCB_GC_FOREGROUND: c_int = 4;
pub const XCB_GC_BACKGROUND: c_int = 8;
pub const XCB_GC_LINE_WIDTH: c_int = 16;
pub const XCB_GC_LINE_STYLE: c_int = 32;
pub const XCB_GC_CAP_STYLE: c_int = 64;
pub const XCB_GC_JOIN_STYLE: c_int = 128;
pub const XCB_GC_FILL_STYLE: c_int = 256;
pub const XCB_GC_FILL_RULE: c_int = 512;
pub const XCB_GC_TILE: c_int = 1024;
pub const XCB_GC_STIPPLE: c_int = 2048;
pub const XCB_GC_TILE_STIPPLE_ORIGIN_X: c_int = 4096;
pub const XCB_GC_TILE_STIPPLE_ORIGIN_Y: c_int = 8192;
pub const XCB_GC_FONT: c_int = 16384;
pub const XCB_GC_SUBWINDOW_MODE: c_int = 32768;
pub const XCB_GC_GRAPHICS_EXPOSURES: c_int = 65536;
pub const XCB_GC_CLIP_ORIGIN_X: c_int = 131072;
pub const XCB_GC_CLIP_ORIGIN_Y: c_int = 262144;
pub const XCB_GC_CLIP_MASK: c_int = 524288;
pub const XCB_GC_DASH_OFFSET: c_int = 1048576;
pub const XCB_GC_DASH_LIST: c_int = 2097152;
pub const XCB_GC_ARC_MODE: c_int = 4194304;
pub const enum_xcb_gc_t = c_uint;
pub const xcb_gc_t = enum_xcb_gc_t;
pub const XCB_GX_CLEAR: c_int = 0;
pub const XCB_GX_AND: c_int = 1;
pub const XCB_GX_AND_REVERSE: c_int = 2;
pub const XCB_GX_COPY: c_int = 3;
pub const XCB_GX_AND_INVERTED: c_int = 4;
pub const XCB_GX_NOOP: c_int = 5;
pub const XCB_GX_XOR: c_int = 6;
pub const XCB_GX_OR: c_int = 7;
pub const XCB_GX_NOR: c_int = 8;
pub const XCB_GX_EQUIV: c_int = 9;
pub const XCB_GX_INVERT: c_int = 10;
pub const XCB_GX_OR_REVERSE: c_int = 11;
pub const XCB_GX_COPY_INVERTED: c_int = 12;
pub const XCB_GX_OR_INVERTED: c_int = 13;
pub const XCB_GX_NAND: c_int = 14;
pub const XCB_GX_SET: c_int = 15;
pub const enum_xcb_gx_t = c_uint;
pub const xcb_gx_t = enum_xcb_gx_t;
pub const XCB_LINE_STYLE_SOLID: c_int = 0;
pub const XCB_LINE_STYLE_ON_OFF_DASH: c_int = 1;
pub const XCB_LINE_STYLE_DOUBLE_DASH: c_int = 2;
pub const enum_xcb_line_style_t = c_uint;
pub const xcb_line_style_t = enum_xcb_line_style_t;
pub const XCB_CAP_STYLE_NOT_LAST: c_int = 0;
pub const XCB_CAP_STYLE_BUTT: c_int = 1;
pub const XCB_CAP_STYLE_ROUND: c_int = 2;
pub const XCB_CAP_STYLE_PROJECTING: c_int = 3;
pub const enum_xcb_cap_style_t = c_uint;
pub const xcb_cap_style_t = enum_xcb_cap_style_t;
pub const XCB_JOIN_STYLE_MITER: c_int = 0;
pub const XCB_JOIN_STYLE_ROUND: c_int = 1;
pub const XCB_JOIN_STYLE_BEVEL: c_int = 2;
pub const enum_xcb_join_style_t = c_uint;
pub const xcb_join_style_t = enum_xcb_join_style_t;
pub const XCB_FILL_STYLE_SOLID: c_int = 0;
pub const XCB_FILL_STYLE_TILED: c_int = 1;
pub const XCB_FILL_STYLE_STIPPLED: c_int = 2;
pub const XCB_FILL_STYLE_OPAQUE_STIPPLED: c_int = 3;
pub const enum_xcb_fill_style_t = c_uint;
pub const xcb_fill_style_t = enum_xcb_fill_style_t;
pub const XCB_FILL_RULE_EVEN_ODD: c_int = 0;
pub const XCB_FILL_RULE_WINDING: c_int = 1;
pub const enum_xcb_fill_rule_t = c_uint;
pub const xcb_fill_rule_t = enum_xcb_fill_rule_t;
pub const XCB_SUBWINDOW_MODE_CLIP_BY_CHILDREN: c_int = 0;
pub const XCB_SUBWINDOW_MODE_INCLUDE_INFERIORS: c_int = 1;
pub const enum_xcb_subwindow_mode_t = c_uint;
pub const xcb_subwindow_mode_t = enum_xcb_subwindow_mode_t;
pub const XCB_ARC_MODE_CHORD: c_int = 0;
pub const XCB_ARC_MODE_PIE_SLICE: c_int = 1;
pub const enum_xcb_arc_mode_t = c_uint;
pub const xcb_arc_mode_t = enum_xcb_arc_mode_t;
pub const struct_xcb_create_gc_value_list_t = extern struct {
    function: u32 = @import("std").mem.zeroes(u32),
    plane_mask: u32 = @import("std").mem.zeroes(u32),
    foreground: u32 = @import("std").mem.zeroes(u32),
    background: u32 = @import("std").mem.zeroes(u32),
    line_width: u32 = @import("std").mem.zeroes(u32),
    line_style: u32 = @import("std").mem.zeroes(u32),
    cap_style: u32 = @import("std").mem.zeroes(u32),
    join_style: u32 = @import("std").mem.zeroes(u32),
    fill_style: u32 = @import("std").mem.zeroes(u32),
    fill_rule: u32 = @import("std").mem.zeroes(u32),
    tile: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    stipple: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    tile_stipple_x_origin: i32 = @import("std").mem.zeroes(i32),
    tile_stipple_y_origin: i32 = @import("std").mem.zeroes(i32),
    font: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
    subwindow_mode: u32 = @import("std").mem.zeroes(u32),
    graphics_exposures: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    clip_x_origin: i32 = @import("std").mem.zeroes(i32),
    clip_y_origin: i32 = @import("std").mem.zeroes(i32),
    clip_mask: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    dash_offset: u32 = @import("std").mem.zeroes(u32),
    dashes: u32 = @import("std").mem.zeroes(u32),
    arc_mode: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_create_gc_value_list_t = struct_xcb_create_gc_value_list_t;
pub const struct_xcb_create_gc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cid: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_create_gc_request_t = struct_xcb_create_gc_request_t;
pub const struct_xcb_change_gc_value_list_t = extern struct {
    function: u32 = @import("std").mem.zeroes(u32),
    plane_mask: u32 = @import("std").mem.zeroes(u32),
    foreground: u32 = @import("std").mem.zeroes(u32),
    background: u32 = @import("std").mem.zeroes(u32),
    line_width: u32 = @import("std").mem.zeroes(u32),
    line_style: u32 = @import("std").mem.zeroes(u32),
    cap_style: u32 = @import("std").mem.zeroes(u32),
    join_style: u32 = @import("std").mem.zeroes(u32),
    fill_style: u32 = @import("std").mem.zeroes(u32),
    fill_rule: u32 = @import("std").mem.zeroes(u32),
    tile: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    stipple: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    tile_stipple_x_origin: i32 = @import("std").mem.zeroes(i32),
    tile_stipple_y_origin: i32 = @import("std").mem.zeroes(i32),
    font: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
    subwindow_mode: u32 = @import("std").mem.zeroes(u32),
    graphics_exposures: xcb_bool32_t = @import("std").mem.zeroes(xcb_bool32_t),
    clip_x_origin: i32 = @import("std").mem.zeroes(i32),
    clip_y_origin: i32 = @import("std").mem.zeroes(i32),
    clip_mask: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    dash_offset: u32 = @import("std").mem.zeroes(u32),
    dashes: u32 = @import("std").mem.zeroes(u32),
    arc_mode: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_gc_value_list_t = struct_xcb_change_gc_value_list_t;
pub const struct_xcb_change_gc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_gc_request_t = struct_xcb_change_gc_request_t;
pub const struct_xcb_copy_gc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    src_gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    dst_gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_copy_gc_request_t = struct_xcb_copy_gc_request_t;
pub const struct_xcb_set_dashes_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    dash_offset: u16 = @import("std").mem.zeroes(u16),
    dashes_len: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_set_dashes_request_t = struct_xcb_set_dashes_request_t;
pub const XCB_CLIP_ORDERING_UNSORTED: c_int = 0;
pub const XCB_CLIP_ORDERING_Y_SORTED: c_int = 1;
pub const XCB_CLIP_ORDERING_YX_SORTED: c_int = 2;
pub const XCB_CLIP_ORDERING_YX_BANDED: c_int = 3;
pub const enum_xcb_clip_ordering_t = c_uint;
pub const xcb_clip_ordering_t = enum_xcb_clip_ordering_t;
pub const struct_xcb_set_clip_rectangles_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    ordering: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    clip_x_origin: i16 = @import("std").mem.zeroes(i16),
    clip_y_origin: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_set_clip_rectangles_request_t = struct_xcb_set_clip_rectangles_request_t;
pub const struct_xcb_free_gc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_free_gc_request_t = struct_xcb_free_gc_request_t;
pub const struct_xcb_clear_area_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    exposures: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_clear_area_request_t = struct_xcb_clear_area_request_t;
pub const struct_xcb_copy_area_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    src_drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    dst_drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    src_x: i16 = @import("std").mem.zeroes(i16),
    src_y: i16 = @import("std").mem.zeroes(i16),
    dst_x: i16 = @import("std").mem.zeroes(i16),
    dst_y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_copy_area_request_t = struct_xcb_copy_area_request_t;
pub const struct_xcb_copy_plane_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    src_drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    dst_drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    src_x: i16 = @import("std").mem.zeroes(i16),
    src_y: i16 = @import("std").mem.zeroes(i16),
    dst_x: i16 = @import("std").mem.zeroes(i16),
    dst_y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    bit_plane: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_copy_plane_request_t = struct_xcb_copy_plane_request_t;
pub const XCB_COORD_MODE_ORIGIN: c_int = 0;
pub const XCB_COORD_MODE_PREVIOUS: c_int = 1;
pub const enum_xcb_coord_mode_t = c_uint;
pub const xcb_coord_mode_t = enum_xcb_coord_mode_t;
pub const struct_xcb_poly_point_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    coordinate_mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_point_request_t = struct_xcb_poly_point_request_t;
pub const struct_xcb_poly_line_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    coordinate_mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_line_request_t = struct_xcb_poly_line_request_t;
pub const struct_xcb_segment_t = extern struct {
    x1: i16 = @import("std").mem.zeroes(i16),
    y1: i16 = @import("std").mem.zeroes(i16),
    x2: i16 = @import("std").mem.zeroes(i16),
    y2: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_segment_t = struct_xcb_segment_t;
pub const struct_xcb_segment_iterator_t = extern struct {
    data: [*c]xcb_segment_t = @import("std").mem.zeroes([*c]xcb_segment_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_segment_iterator_t = struct_xcb_segment_iterator_t;
pub const struct_xcb_poly_segment_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_segment_request_t = struct_xcb_poly_segment_request_t;
pub const struct_xcb_poly_rectangle_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_rectangle_request_t = struct_xcb_poly_rectangle_request_t;
pub const struct_xcb_poly_arc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_arc_request_t = struct_xcb_poly_arc_request_t;
pub const XCB_POLY_SHAPE_COMPLEX: c_int = 0;
pub const XCB_POLY_SHAPE_NONCONVEX: c_int = 1;
pub const XCB_POLY_SHAPE_CONVEX: c_int = 2;
pub const enum_xcb_poly_shape_t = c_uint;
pub const xcb_poly_shape_t = enum_xcb_poly_shape_t;
pub const struct_xcb_fill_poly_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    shape: u8 = @import("std").mem.zeroes(u8),
    coordinate_mode: u8 = @import("std").mem.zeroes(u8),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_fill_poly_request_t = struct_xcb_fill_poly_request_t;
pub const struct_xcb_poly_fill_rectangle_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_fill_rectangle_request_t = struct_xcb_poly_fill_rectangle_request_t;
pub const struct_xcb_poly_fill_arc_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
};
pub const xcb_poly_fill_arc_request_t = struct_xcb_poly_fill_arc_request_t;
pub const XCB_IMAGE_FORMAT_XY_BITMAP: c_int = 0;
pub const XCB_IMAGE_FORMAT_XY_PIXMAP: c_int = 1;
pub const XCB_IMAGE_FORMAT_Z_PIXMAP: c_int = 2;
pub const enum_xcb_image_format_t = c_uint;
pub const xcb_image_format_t = enum_xcb_image_format_t;
pub const struct_xcb_put_image_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    format: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    dst_x: i16 = @import("std").mem.zeroes(i16),
    dst_y: i16 = @import("std").mem.zeroes(i16),
    left_pad: u8 = @import("std").mem.zeroes(u8),
    depth: u8 = @import("std").mem.zeroes(u8),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_put_image_request_t = struct_xcb_put_image_request_t;
pub const struct_xcb_get_image_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_image_cookie_t = struct_xcb_get_image_cookie_t;
pub const struct_xcb_get_image_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    format: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
    plane_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_get_image_request_t = struct_xcb_get_image_request_t;
pub const struct_xcb_get_image_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    depth: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    visual: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
    pad0: [20]u8 = @import("std").mem.zeroes([20]u8),
};
pub const xcb_get_image_reply_t = struct_xcb_get_image_reply_t;
pub const struct_xcb_poly_text_8_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_poly_text_8_request_t = struct_xcb_poly_text_8_request_t;
pub const struct_xcb_poly_text_16_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_poly_text_16_request_t = struct_xcb_poly_text_16_request_t;
pub const struct_xcb_image_text_8_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    string_len: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_image_text_8_request_t = struct_xcb_image_text_8_request_t;
pub const struct_xcb_image_text_16_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    string_len: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    gc: xcb_gcontext_t = @import("std").mem.zeroes(xcb_gcontext_t),
    x: i16 = @import("std").mem.zeroes(i16),
    y: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_image_text_16_request_t = struct_xcb_image_text_16_request_t;
pub const XCB_COLORMAP_ALLOC_NONE: c_int = 0;
pub const XCB_COLORMAP_ALLOC_ALL: c_int = 1;
pub const enum_xcb_colormap_alloc_t = c_uint;
pub const xcb_colormap_alloc_t = enum_xcb_colormap_alloc_t;
pub const struct_xcb_create_colormap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    alloc: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    mid: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    visual: xcb_visualid_t = @import("std").mem.zeroes(xcb_visualid_t),
};
pub const xcb_create_colormap_request_t = struct_xcb_create_colormap_request_t;
pub const struct_xcb_free_colormap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_free_colormap_request_t = struct_xcb_free_colormap_request_t;
pub const struct_xcb_copy_colormap_and_free_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    mid: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    src_cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_copy_colormap_and_free_request_t = struct_xcb_copy_colormap_and_free_request_t;
pub const struct_xcb_install_colormap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_install_colormap_request_t = struct_xcb_install_colormap_request_t;
pub const struct_xcb_uninstall_colormap_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_uninstall_colormap_request_t = struct_xcb_uninstall_colormap_request_t;
pub const struct_xcb_list_installed_colormaps_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_installed_colormaps_cookie_t = struct_xcb_list_installed_colormaps_cookie_t;
pub const struct_xcb_list_installed_colormaps_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
};
pub const xcb_list_installed_colormaps_request_t = struct_xcb_list_installed_colormaps_request_t;
pub const struct_xcb_list_installed_colormaps_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    cmaps_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_list_installed_colormaps_reply_t = struct_xcb_list_installed_colormaps_reply_t;
pub const struct_xcb_alloc_color_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_alloc_color_cookie_t = struct_xcb_alloc_color_cookie_t;
pub const struct_xcb_alloc_color_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    red: u16 = @import("std").mem.zeroes(u16),
    green: u16 = @import("std").mem.zeroes(u16),
    blue: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_alloc_color_request_t = struct_xcb_alloc_color_request_t;
pub const struct_xcb_alloc_color_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    red: u16 = @import("std").mem.zeroes(u16),
    green: u16 = @import("std").mem.zeroes(u16),
    blue: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
    pixel: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_alloc_color_reply_t = struct_xcb_alloc_color_reply_t;
pub const struct_xcb_alloc_named_color_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_alloc_named_color_cookie_t = struct_xcb_alloc_named_color_cookie_t;
pub const struct_xcb_alloc_named_color_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_alloc_named_color_request_t = struct_xcb_alloc_named_color_request_t;
pub const struct_xcb_alloc_named_color_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pixel: u32 = @import("std").mem.zeroes(u32),
    exact_red: u16 = @import("std").mem.zeroes(u16),
    exact_green: u16 = @import("std").mem.zeroes(u16),
    exact_blue: u16 = @import("std").mem.zeroes(u16),
    visual_red: u16 = @import("std").mem.zeroes(u16),
    visual_green: u16 = @import("std").mem.zeroes(u16),
    visual_blue: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_alloc_named_color_reply_t = struct_xcb_alloc_named_color_reply_t;
pub const struct_xcb_alloc_color_cells_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_alloc_color_cells_cookie_t = struct_xcb_alloc_color_cells_cookie_t;
pub const struct_xcb_alloc_color_cells_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    contiguous: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    colors: u16 = @import("std").mem.zeroes(u16),
    planes: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_alloc_color_cells_request_t = struct_xcb_alloc_color_cells_request_t;
pub const struct_xcb_alloc_color_cells_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pixels_len: u16 = @import("std").mem.zeroes(u16),
    masks_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [20]u8 = @import("std").mem.zeroes([20]u8),
};
pub const xcb_alloc_color_cells_reply_t = struct_xcb_alloc_color_cells_reply_t;
pub const struct_xcb_alloc_color_planes_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_alloc_color_planes_cookie_t = struct_xcb_alloc_color_planes_cookie_t;
pub const struct_xcb_alloc_color_planes_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    contiguous: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    colors: u16 = @import("std").mem.zeroes(u16),
    reds: u16 = @import("std").mem.zeroes(u16),
    greens: u16 = @import("std").mem.zeroes(u16),
    blues: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_alloc_color_planes_request_t = struct_xcb_alloc_color_planes_request_t;
pub const struct_xcb_alloc_color_planes_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pixels_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
    red_mask: u32 = @import("std").mem.zeroes(u32),
    green_mask: u32 = @import("std").mem.zeroes(u32),
    blue_mask: u32 = @import("std").mem.zeroes(u32),
    pad2: [8]u8 = @import("std").mem.zeroes([8]u8),
};
pub const xcb_alloc_color_planes_reply_t = struct_xcb_alloc_color_planes_reply_t;
pub const struct_xcb_free_colors_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    plane_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_free_colors_request_t = struct_xcb_free_colors_request_t;
pub const XCB_COLOR_FLAG_RED: c_int = 1;
pub const XCB_COLOR_FLAG_GREEN: c_int = 2;
pub const XCB_COLOR_FLAG_BLUE: c_int = 4;
pub const enum_xcb_color_flag_t = c_uint;
pub const xcb_color_flag_t = enum_xcb_color_flag_t;
pub const struct_xcb_coloritem_t = extern struct {
    pixel: u32 = @import("std").mem.zeroes(u32),
    red: u16 = @import("std").mem.zeroes(u16),
    green: u16 = @import("std").mem.zeroes(u16),
    blue: u16 = @import("std").mem.zeroes(u16),
    flags: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_coloritem_t = struct_xcb_coloritem_t;
pub const struct_xcb_coloritem_iterator_t = extern struct {
    data: [*c]xcb_coloritem_t = @import("std").mem.zeroes([*c]xcb_coloritem_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_coloritem_iterator_t = struct_xcb_coloritem_iterator_t;
pub const struct_xcb_store_colors_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_store_colors_request_t = struct_xcb_store_colors_request_t;
pub const struct_xcb_store_named_color_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    flags: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    pixel: u32 = @import("std").mem.zeroes(u32),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_store_named_color_request_t = struct_xcb_store_named_color_request_t;
pub const struct_xcb_rgb_t = extern struct {
    red: u16 = @import("std").mem.zeroes(u16),
    green: u16 = @import("std").mem.zeroes(u16),
    blue: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_rgb_t = struct_xcb_rgb_t;
pub const struct_xcb_rgb_iterator_t = extern struct {
    data: [*c]xcb_rgb_t = @import("std").mem.zeroes([*c]xcb_rgb_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_rgb_iterator_t = struct_xcb_rgb_iterator_t;
pub const struct_xcb_query_colors_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_colors_cookie_t = struct_xcb_query_colors_cookie_t;
pub const struct_xcb_query_colors_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
};
pub const xcb_query_colors_request_t = struct_xcb_query_colors_request_t;
pub const struct_xcb_query_colors_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    colors_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_query_colors_reply_t = struct_xcb_query_colors_reply_t;
pub const struct_xcb_lookup_color_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_lookup_color_cookie_t = struct_xcb_lookup_color_cookie_t;
pub const struct_xcb_lookup_color_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cmap: xcb_colormap_t = @import("std").mem.zeroes(xcb_colormap_t),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_lookup_color_request_t = struct_xcb_lookup_color_request_t;
pub const struct_xcb_lookup_color_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    exact_red: u16 = @import("std").mem.zeroes(u16),
    exact_green: u16 = @import("std").mem.zeroes(u16),
    exact_blue: u16 = @import("std").mem.zeroes(u16),
    visual_red: u16 = @import("std").mem.zeroes(u16),
    visual_green: u16 = @import("std").mem.zeroes(u16),
    visual_blue: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_lookup_color_reply_t = struct_xcb_lookup_color_reply_t;
pub const XCB_PIXMAP_NONE: c_int = 0;
pub const enum_xcb_pixmap_enum_t = c_uint;
pub const xcb_pixmap_enum_t = enum_xcb_pixmap_enum_t;
pub const struct_xcb_create_cursor_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cid: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    source: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    mask: xcb_pixmap_t = @import("std").mem.zeroes(xcb_pixmap_t),
    fore_red: u16 = @import("std").mem.zeroes(u16),
    fore_green: u16 = @import("std").mem.zeroes(u16),
    fore_blue: u16 = @import("std").mem.zeroes(u16),
    back_red: u16 = @import("std").mem.zeroes(u16),
    back_green: u16 = @import("std").mem.zeroes(u16),
    back_blue: u16 = @import("std").mem.zeroes(u16),
    x: u16 = @import("std").mem.zeroes(u16),
    y: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_create_cursor_request_t = struct_xcb_create_cursor_request_t;
pub const XCB_FONT_NONE: c_int = 0;
pub const enum_xcb_font_enum_t = c_uint;
pub const xcb_font_enum_t = enum_xcb_font_enum_t;
pub const struct_xcb_create_glyph_cursor_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cid: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    source_font: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
    mask_font: xcb_font_t = @import("std").mem.zeroes(xcb_font_t),
    source_char: u16 = @import("std").mem.zeroes(u16),
    mask_char: u16 = @import("std").mem.zeroes(u16),
    fore_red: u16 = @import("std").mem.zeroes(u16),
    fore_green: u16 = @import("std").mem.zeroes(u16),
    fore_blue: u16 = @import("std").mem.zeroes(u16),
    back_red: u16 = @import("std").mem.zeroes(u16),
    back_green: u16 = @import("std").mem.zeroes(u16),
    back_blue: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_create_glyph_cursor_request_t = struct_xcb_create_glyph_cursor_request_t;
pub const struct_xcb_free_cursor_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
};
pub const xcb_free_cursor_request_t = struct_xcb_free_cursor_request_t;
pub const struct_xcb_recolor_cursor_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    cursor: xcb_cursor_t = @import("std").mem.zeroes(xcb_cursor_t),
    fore_red: u16 = @import("std").mem.zeroes(u16),
    fore_green: u16 = @import("std").mem.zeroes(u16),
    fore_blue: u16 = @import("std").mem.zeroes(u16),
    back_red: u16 = @import("std").mem.zeroes(u16),
    back_green: u16 = @import("std").mem.zeroes(u16),
    back_blue: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_recolor_cursor_request_t = struct_xcb_recolor_cursor_request_t;
pub const XCB_QUERY_SHAPE_OF_LARGEST_CURSOR: c_int = 0;
pub const XCB_QUERY_SHAPE_OF_FASTEST_TILE: c_int = 1;
pub const XCB_QUERY_SHAPE_OF_FASTEST_STIPPLE: c_int = 2;
pub const enum_xcb_query_shape_of_t = c_uint;
pub const xcb_query_shape_of_t = enum_xcb_query_shape_of_t;
pub const struct_xcb_query_best_size_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_best_size_cookie_t = struct_xcb_query_best_size_cookie_t;
pub const struct_xcb_query_best_size_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    _class: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    drawable: xcb_drawable_t = @import("std").mem.zeroes(xcb_drawable_t),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_query_best_size_request_t = struct_xcb_query_best_size_request_t;
pub const struct_xcb_query_best_size_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    width: u16 = @import("std").mem.zeroes(u16),
    height: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_query_best_size_reply_t = struct_xcb_query_best_size_reply_t;
pub const struct_xcb_query_extension_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_query_extension_cookie_t = struct_xcb_query_extension_cookie_t;
pub const struct_xcb_query_extension_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    name_len: u16 = @import("std").mem.zeroes(u16),
    pad1: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_query_extension_request_t = struct_xcb_query_extension_request_t;
pub const struct_xcb_query_extension_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    present: u8 = @import("std").mem.zeroes(u8),
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    first_event: u8 = @import("std").mem.zeroes(u8),
    first_error: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_query_extension_reply_t = struct_xcb_query_extension_reply_t;
pub const struct_xcb_list_extensions_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_extensions_cookie_t = struct_xcb_list_extensions_cookie_t;
pub const struct_xcb_list_extensions_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_list_extensions_request_t = struct_xcb_list_extensions_request_t;
pub const struct_xcb_list_extensions_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    names_len: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pad0: [24]u8 = @import("std").mem.zeroes([24]u8),
};
pub const xcb_list_extensions_reply_t = struct_xcb_list_extensions_reply_t;
pub const struct_xcb_change_keyboard_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    keycode_count: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    first_keycode: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    keysyms_per_keycode: u8 = @import("std").mem.zeroes(u8),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
};
pub const xcb_change_keyboard_mapping_request_t = struct_xcb_change_keyboard_mapping_request_t;
pub const struct_xcb_get_keyboard_mapping_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_keyboard_mapping_cookie_t = struct_xcb_get_keyboard_mapping_cookie_t;
pub const struct_xcb_get_keyboard_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    first_keycode: xcb_keycode_t = @import("std").mem.zeroes(xcb_keycode_t),
    count: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_get_keyboard_mapping_request_t = struct_xcb_get_keyboard_mapping_request_t;
pub const struct_xcb_get_keyboard_mapping_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    keysyms_per_keycode: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pad0: [24]u8 = @import("std").mem.zeroes([24]u8),
};
pub const xcb_get_keyboard_mapping_reply_t = struct_xcb_get_keyboard_mapping_reply_t;
pub const XCB_KB_KEY_CLICK_PERCENT: c_int = 1;
pub const XCB_KB_BELL_PERCENT: c_int = 2;
pub const XCB_KB_BELL_PITCH: c_int = 4;
pub const XCB_KB_BELL_DURATION: c_int = 8;
pub const XCB_KB_LED: c_int = 16;
pub const XCB_KB_LED_MODE: c_int = 32;
pub const XCB_KB_KEY: c_int = 64;
pub const XCB_KB_AUTO_REPEAT_MODE: c_int = 128;
pub const enum_xcb_kb_t = c_uint;
pub const xcb_kb_t = enum_xcb_kb_t;
pub const XCB_LED_MODE_OFF: c_int = 0;
pub const XCB_LED_MODE_ON: c_int = 1;
pub const enum_xcb_led_mode_t = c_uint;
pub const xcb_led_mode_t = enum_xcb_led_mode_t;
pub const XCB_AUTO_REPEAT_MODE_OFF: c_int = 0;
pub const XCB_AUTO_REPEAT_MODE_ON: c_int = 1;
pub const XCB_AUTO_REPEAT_MODE_DEFAULT: c_int = 2;
pub const enum_xcb_auto_repeat_mode_t = c_uint;
pub const xcb_auto_repeat_mode_t = enum_xcb_auto_repeat_mode_t;
pub const struct_xcb_change_keyboard_control_value_list_t = extern struct {
    key_click_percent: i32 = @import("std").mem.zeroes(i32),
    bell_percent: i32 = @import("std").mem.zeroes(i32),
    bell_pitch: i32 = @import("std").mem.zeroes(i32),
    bell_duration: i32 = @import("std").mem.zeroes(i32),
    led: u32 = @import("std").mem.zeroes(u32),
    led_mode: u32 = @import("std").mem.zeroes(u32),
    key: xcb_keycode32_t = @import("std").mem.zeroes(xcb_keycode32_t),
    auto_repeat_mode: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_keyboard_control_value_list_t = struct_xcb_change_keyboard_control_value_list_t;
pub const struct_xcb_change_keyboard_control_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    value_mask: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_change_keyboard_control_request_t = struct_xcb_change_keyboard_control_request_t;
pub const struct_xcb_get_keyboard_control_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_keyboard_control_cookie_t = struct_xcb_get_keyboard_control_cookie_t;
pub const struct_xcb_get_keyboard_control_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_keyboard_control_request_t = struct_xcb_get_keyboard_control_request_t;
pub const struct_xcb_get_keyboard_control_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    global_auto_repeat: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    led_mask: u32 = @import("std").mem.zeroes(u32),
    key_click_percent: u8 = @import("std").mem.zeroes(u8),
    bell_percent: u8 = @import("std").mem.zeroes(u8),
    bell_pitch: u16 = @import("std").mem.zeroes(u16),
    bell_duration: u16 = @import("std").mem.zeroes(u16),
    pad0: [2]u8 = @import("std").mem.zeroes([2]u8),
    auto_repeats: [32]u8 = @import("std").mem.zeroes([32]u8),
};
pub const xcb_get_keyboard_control_reply_t = struct_xcb_get_keyboard_control_reply_t;
pub const struct_xcb_bell_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    percent: i8 = @import("std").mem.zeroes(i8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_bell_request_t = struct_xcb_bell_request_t;
pub const struct_xcb_change_pointer_control_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    acceleration_numerator: i16 = @import("std").mem.zeroes(i16),
    acceleration_denominator: i16 = @import("std").mem.zeroes(i16),
    threshold: i16 = @import("std").mem.zeroes(i16),
    do_acceleration: u8 = @import("std").mem.zeroes(u8),
    do_threshold: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_change_pointer_control_request_t = struct_xcb_change_pointer_control_request_t;
pub const struct_xcb_get_pointer_control_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_pointer_control_cookie_t = struct_xcb_get_pointer_control_cookie_t;
pub const struct_xcb_get_pointer_control_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_pointer_control_request_t = struct_xcb_get_pointer_control_request_t;
pub const struct_xcb_get_pointer_control_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    acceleration_numerator: u16 = @import("std").mem.zeroes(u16),
    acceleration_denominator: u16 = @import("std").mem.zeroes(u16),
    threshold: u16 = @import("std").mem.zeroes(u16),
    pad1: [18]u8 = @import("std").mem.zeroes([18]u8),
};
pub const xcb_get_pointer_control_reply_t = struct_xcb_get_pointer_control_reply_t;
pub const XCB_BLANKING_NOT_PREFERRED: c_int = 0;
pub const XCB_BLANKING_PREFERRED: c_int = 1;
pub const XCB_BLANKING_DEFAULT: c_int = 2;
pub const enum_xcb_blanking_t = c_uint;
pub const xcb_blanking_t = enum_xcb_blanking_t;
pub const XCB_EXPOSURES_NOT_ALLOWED: c_int = 0;
pub const XCB_EXPOSURES_ALLOWED: c_int = 1;
pub const XCB_EXPOSURES_DEFAULT: c_int = 2;
pub const enum_xcb_exposures_t = c_uint;
pub const xcb_exposures_t = enum_xcb_exposures_t;
pub const struct_xcb_set_screen_saver_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    timeout: i16 = @import("std").mem.zeroes(i16),
    interval: i16 = @import("std").mem.zeroes(i16),
    prefer_blanking: u8 = @import("std").mem.zeroes(u8),
    allow_exposures: u8 = @import("std").mem.zeroes(u8),
};
pub const xcb_set_screen_saver_request_t = struct_xcb_set_screen_saver_request_t;
pub const struct_xcb_get_screen_saver_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_screen_saver_cookie_t = struct_xcb_get_screen_saver_cookie_t;
pub const struct_xcb_get_screen_saver_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_screen_saver_request_t = struct_xcb_get_screen_saver_request_t;
pub const struct_xcb_get_screen_saver_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    timeout: u16 = @import("std").mem.zeroes(u16),
    interval: u16 = @import("std").mem.zeroes(u16),
    prefer_blanking: u8 = @import("std").mem.zeroes(u8),
    allow_exposures: u8 = @import("std").mem.zeroes(u8),
    pad1: [18]u8 = @import("std").mem.zeroes([18]u8),
};
pub const xcb_get_screen_saver_reply_t = struct_xcb_get_screen_saver_reply_t;
pub const XCB_HOST_MODE_INSERT: c_int = 0;
pub const XCB_HOST_MODE_DELETE: c_int = 1;
pub const enum_xcb_host_mode_t = c_uint;
pub const xcb_host_mode_t = enum_xcb_host_mode_t;
pub const XCB_FAMILY_INTERNET: c_int = 0;
pub const XCB_FAMILY_DECNET: c_int = 1;
pub const XCB_FAMILY_CHAOS: c_int = 2;
pub const XCB_FAMILY_SERVER_INTERPRETED: c_int = 5;
pub const XCB_FAMILY_INTERNET_6: c_int = 6;
pub const enum_xcb_family_t = c_uint;
pub const xcb_family_t = enum_xcb_family_t;
pub const struct_xcb_change_hosts_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    family: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    address_len: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_change_hosts_request_t = struct_xcb_change_hosts_request_t;
pub const struct_xcb_host_t = extern struct {
    family: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    address_len: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_host_t = struct_xcb_host_t;
pub const struct_xcb_host_iterator_t = extern struct {
    data: [*c]xcb_host_t = @import("std").mem.zeroes([*c]xcb_host_t),
    rem: c_int = @import("std").mem.zeroes(c_int),
    index: c_int = @import("std").mem.zeroes(c_int),
};
pub const xcb_host_iterator_t = struct_xcb_host_iterator_t;
pub const struct_xcb_list_hosts_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_list_hosts_cookie_t = struct_xcb_list_hosts_cookie_t;
pub const struct_xcb_list_hosts_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_list_hosts_request_t = struct_xcb_list_hosts_request_t;
pub const struct_xcb_list_hosts_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    hosts_len: u16 = @import("std").mem.zeroes(u16),
    pad0: [22]u8 = @import("std").mem.zeroes([22]u8),
};
pub const xcb_list_hosts_reply_t = struct_xcb_list_hosts_reply_t;
pub const XCB_ACCESS_CONTROL_DISABLE: c_int = 0;
pub const XCB_ACCESS_CONTROL_ENABLE: c_int = 1;
pub const enum_xcb_access_control_t = c_uint;
pub const xcb_access_control_t = enum_xcb_access_control_t;
pub const struct_xcb_set_access_control_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_set_access_control_request_t = struct_xcb_set_access_control_request_t;
pub const XCB_CLOSE_DOWN_DESTROY_ALL: c_int = 0;
pub const XCB_CLOSE_DOWN_RETAIN_PERMANENT: c_int = 1;
pub const XCB_CLOSE_DOWN_RETAIN_TEMPORARY: c_int = 2;
pub const enum_xcb_close_down_t = c_uint;
pub const xcb_close_down_t = enum_xcb_close_down_t;
pub const struct_xcb_set_close_down_mode_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_set_close_down_mode_request_t = struct_xcb_set_close_down_mode_request_t;
pub const XCB_KILL_ALL_TEMPORARY: c_int = 0;
pub const enum_xcb_kill_t = c_uint;
pub const xcb_kill_t = enum_xcb_kill_t;
pub const struct_xcb_kill_client_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    resource: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_kill_client_request_t = struct_xcb_kill_client_request_t;
pub const struct_xcb_rotate_properties_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
    window: xcb_window_t = @import("std").mem.zeroes(xcb_window_t),
    atoms_len: u16 = @import("std").mem.zeroes(u16),
    delta: i16 = @import("std").mem.zeroes(i16),
};
pub const xcb_rotate_properties_request_t = struct_xcb_rotate_properties_request_t;
pub const XCB_SCREEN_SAVER_RESET: c_int = 0;
pub const XCB_SCREEN_SAVER_ACTIVE: c_int = 1;
pub const enum_xcb_screen_saver_t = c_uint;
pub const xcb_screen_saver_t = enum_xcb_screen_saver_t;
pub const struct_xcb_force_screen_saver_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    mode: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_force_screen_saver_request_t = struct_xcb_force_screen_saver_request_t;
pub const XCB_MAPPING_STATUS_SUCCESS: c_int = 0;
pub const XCB_MAPPING_STATUS_BUSY: c_int = 1;
pub const XCB_MAPPING_STATUS_FAILURE: c_int = 2;
pub const enum_xcb_mapping_status_t = c_uint;
pub const xcb_mapping_status_t = enum_xcb_mapping_status_t;
pub const struct_xcb_set_pointer_mapping_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_set_pointer_mapping_cookie_t = struct_xcb_set_pointer_mapping_cookie_t;
pub const struct_xcb_set_pointer_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    map_len: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_set_pointer_mapping_request_t = struct_xcb_set_pointer_mapping_request_t;
pub const struct_xcb_set_pointer_mapping_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    status: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_set_pointer_mapping_reply_t = struct_xcb_set_pointer_mapping_reply_t;
pub const struct_xcb_get_pointer_mapping_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_pointer_mapping_cookie_t = struct_xcb_get_pointer_mapping_cookie_t;
pub const struct_xcb_get_pointer_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_pointer_mapping_request_t = struct_xcb_get_pointer_mapping_request_t;
pub const struct_xcb_get_pointer_mapping_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    map_len: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pad0: [24]u8 = @import("std").mem.zeroes([24]u8),
};
pub const xcb_get_pointer_mapping_reply_t = struct_xcb_get_pointer_mapping_reply_t;
pub const XCB_MAP_INDEX_SHIFT: c_int = 0;
pub const XCB_MAP_INDEX_LOCK: c_int = 1;
pub const XCB_MAP_INDEX_CONTROL: c_int = 2;
pub const XCB_MAP_INDEX_1: c_int = 3;
pub const XCB_MAP_INDEX_2: c_int = 4;
pub const XCB_MAP_INDEX_3: c_int = 5;
pub const XCB_MAP_INDEX_4: c_int = 6;
pub const XCB_MAP_INDEX_5: c_int = 7;
pub const enum_xcb_map_index_t = c_uint;
pub const xcb_map_index_t = enum_xcb_map_index_t;
pub const struct_xcb_set_modifier_mapping_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_set_modifier_mapping_cookie_t = struct_xcb_set_modifier_mapping_cookie_t;
pub const struct_xcb_set_modifier_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    keycodes_per_modifier: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_set_modifier_mapping_request_t = struct_xcb_set_modifier_mapping_request_t;
pub const struct_xcb_set_modifier_mapping_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    status: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
};
pub const xcb_set_modifier_mapping_reply_t = struct_xcb_set_modifier_mapping_reply_t;
pub const struct_xcb_get_modifier_mapping_cookie_t = extern struct {
    sequence: c_uint = @import("std").mem.zeroes(c_uint),
};
pub const xcb_get_modifier_mapping_cookie_t = struct_xcb_get_modifier_mapping_cookie_t;
pub const struct_xcb_get_modifier_mapping_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_get_modifier_mapping_request_t = struct_xcb_get_modifier_mapping_request_t;
pub const struct_xcb_get_modifier_mapping_reply_t = extern struct {
    response_type: u8 = @import("std").mem.zeroes(u8),
    keycodes_per_modifier: u8 = @import("std").mem.zeroes(u8),
    sequence: u16 = @import("std").mem.zeroes(u16),
    length: u32 = @import("std").mem.zeroes(u32),
    pad0: [24]u8 = @import("std").mem.zeroes([24]u8),
};
pub const xcb_get_modifier_mapping_reply_t = struct_xcb_get_modifier_mapping_reply_t;
pub const struct_xcb_no_operation_request_t = extern struct {
    major_opcode: u8 = @import("std").mem.zeroes(u8),
    pad0: u8 = @import("std").mem.zeroes(u8),
    length: u16 = @import("std").mem.zeroes(u16),
};
pub const xcb_no_operation_request_t = struct_xcb_no_operation_request_t;
pub extern fn xcb_char2b_next(i: [*c]xcb_char2b_iterator_t) void;
pub extern fn xcb_char2b_end(i: xcb_char2b_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_window_next(i: [*c]xcb_window_iterator_t) void;
pub extern fn xcb_window_end(i: xcb_window_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_pixmap_next(i: [*c]xcb_pixmap_iterator_t) void;
pub extern fn xcb_pixmap_end(i: xcb_pixmap_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_cursor_next(i: [*c]xcb_cursor_iterator_t) void;
pub extern fn xcb_cursor_end(i: xcb_cursor_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_font_next(i: [*c]xcb_font_iterator_t) void;
pub extern fn xcb_font_end(i: xcb_font_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_gcontext_next(i: [*c]xcb_gcontext_iterator_t) void;
pub extern fn xcb_gcontext_end(i: xcb_gcontext_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_colormap_next(i: [*c]xcb_colormap_iterator_t) void;
pub extern fn xcb_colormap_end(i: xcb_colormap_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_atom_next(i: [*c]xcb_atom_iterator_t) void;
pub extern fn xcb_atom_end(i: xcb_atom_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_drawable_next(i: [*c]xcb_drawable_iterator_t) void;
pub extern fn xcb_drawable_end(i: xcb_drawable_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_fontable_next(i: [*c]xcb_fontable_iterator_t) void;
pub extern fn xcb_fontable_end(i: xcb_fontable_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_bool32_next(i: [*c]xcb_bool32_iterator_t) void;
pub extern fn xcb_bool32_end(i: xcb_bool32_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_visualid_next(i: [*c]xcb_visualid_iterator_t) void;
pub extern fn xcb_visualid_end(i: xcb_visualid_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_timestamp_next(i: [*c]xcb_timestamp_iterator_t) void;
pub extern fn xcb_timestamp_end(i: xcb_timestamp_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_keysym_next(i: [*c]xcb_keysym_iterator_t) void;
pub extern fn xcb_keysym_end(i: xcb_keysym_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_keycode_next(i: [*c]xcb_keycode_iterator_t) void;
pub extern fn xcb_keycode_end(i: xcb_keycode_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_keycode32_next(i: [*c]xcb_keycode32_iterator_t) void;
pub extern fn xcb_keycode32_end(i: xcb_keycode32_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_button_next(i: [*c]xcb_button_iterator_t) void;
pub extern fn xcb_button_end(i: xcb_button_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_point_next(i: [*c]xcb_point_iterator_t) void;
pub extern fn xcb_point_end(i: xcb_point_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_rectangle_next(i: [*c]xcb_rectangle_iterator_t) void;
pub extern fn xcb_rectangle_end(i: xcb_rectangle_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_arc_next(i: [*c]xcb_arc_iterator_t) void;
pub extern fn xcb_arc_end(i: xcb_arc_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_format_next(i: [*c]xcb_format_iterator_t) void;
pub extern fn xcb_format_end(i: xcb_format_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_visualtype_next(i: [*c]xcb_visualtype_iterator_t) void;
pub extern fn xcb_visualtype_end(i: xcb_visualtype_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_depth_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_depth_visuals(R: [*c]const xcb_depth_t) [*c]xcb_visualtype_t;
pub extern fn xcb_depth_visuals_length(R: [*c]const xcb_depth_t) c_int;
pub extern fn xcb_depth_visuals_iterator(R: [*c]const xcb_depth_t) xcb_visualtype_iterator_t;
pub extern fn xcb_depth_next(i: [*c]xcb_depth_iterator_t) void;
pub extern fn xcb_depth_end(i: xcb_depth_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_screen_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_screen_allowed_depths_length(R: [*c]const xcb_screen_t) c_int;
pub extern fn xcb_screen_allowed_depths_iterator(R: [*c]const xcb_screen_t) xcb_depth_iterator_t;
pub extern fn xcb_screen_next(i: [*c]xcb_screen_iterator_t) void;
pub extern fn xcb_screen_end(i: xcb_screen_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_request_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_setup_request_authorization_protocol_name(R: [*c]const xcb_setup_request_t) [*c]u8;
pub extern fn xcb_setup_request_authorization_protocol_name_length(R: [*c]const xcb_setup_request_t) c_int;
pub extern fn xcb_setup_request_authorization_protocol_name_end(R: [*c]const xcb_setup_request_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_request_authorization_protocol_data(R: [*c]const xcb_setup_request_t) [*c]u8;
pub extern fn xcb_setup_request_authorization_protocol_data_length(R: [*c]const xcb_setup_request_t) c_int;
pub extern fn xcb_setup_request_authorization_protocol_data_end(R: [*c]const xcb_setup_request_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_request_next(i: [*c]xcb_setup_request_iterator_t) void;
pub extern fn xcb_setup_request_end(i: xcb_setup_request_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_failed_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_setup_failed_reason(R: [*c]const xcb_setup_failed_t) [*c]u8;
pub extern fn xcb_setup_failed_reason_length(R: [*c]const xcb_setup_failed_t) c_int;
pub extern fn xcb_setup_failed_reason_end(R: [*c]const xcb_setup_failed_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_failed_next(i: [*c]xcb_setup_failed_iterator_t) void;
pub extern fn xcb_setup_failed_end(i: xcb_setup_failed_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_authenticate_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_setup_authenticate_reason(R: [*c]const xcb_setup_authenticate_t) [*c]u8;
pub extern fn xcb_setup_authenticate_reason_length(R: [*c]const xcb_setup_authenticate_t) c_int;
pub extern fn xcb_setup_authenticate_reason_end(R: [*c]const xcb_setup_authenticate_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_authenticate_next(i: [*c]xcb_setup_authenticate_iterator_t) void;
pub extern fn xcb_setup_authenticate_end(i: xcb_setup_authenticate_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_setup_vendor(R: [*c]const xcb_setup_t) [*c]u8;
pub extern fn xcb_setup_vendor_length(R: [*c]const xcb_setup_t) c_int;
pub extern fn xcb_setup_vendor_end(R: [*c]const xcb_setup_t) xcb_generic_iterator_t;
pub extern fn xcb_setup_pixmap_formats(R: [*c]const xcb_setup_t) [*c]xcb_format_t;
pub extern fn xcb_setup_pixmap_formats_length(R: [*c]const xcb_setup_t) c_int;
pub extern fn xcb_setup_pixmap_formats_iterator(R: [*c]const xcb_setup_t) xcb_format_iterator_t;
pub extern fn xcb_setup_roots_length(R: [*c]const xcb_setup_t) c_int;
pub extern fn xcb_setup_roots_iterator(R: [*c]const xcb_setup_t) xcb_screen_iterator_t;
pub extern fn xcb_setup_next(i: [*c]xcb_setup_iterator_t) void;
pub extern fn xcb_setup_end(i: xcb_setup_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_client_message_data_next(i: [*c]xcb_client_message_data_iterator_t) void;
pub extern fn xcb_client_message_data_end(i: xcb_client_message_data_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_create_window_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u32, _aux: [*c]const xcb_create_window_value_list_t) c_int;
pub extern fn xcb_create_window_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u32, _aux: [*c]xcb_create_window_value_list_t) c_int;
pub extern fn xcb_create_window_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u32) c_int;
pub extern fn xcb_create_window_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_create_window_checked(c: ?*xcb_connection_t, depth: u8, wid: xcb_window_t, parent: xcb_window_t, x: i16, y: i16, width: u16, height: u16, border_width: u16, _class: u16, visual: xcb_visualid_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_create_window(c: ?*xcb_connection_t, depth: u8, wid: xcb_window_t, parent: xcb_window_t, x: i16, y: i16, width: u16, height: u16, border_width: u16, _class: u16, visual: xcb_visualid_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_create_window_aux_checked(c: ?*xcb_connection_t, depth: u8, wid: xcb_window_t, parent: xcb_window_t, x: i16, y: i16, width: u16, height: u16, border_width: u16, _class: u16, visual: xcb_visualid_t, value_mask: u32, value_list: [*c]const xcb_create_window_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_create_window_aux(c: ?*xcb_connection_t, depth: u8, wid: xcb_window_t, parent: xcb_window_t, x: i16, y: i16, width: u16, height: u16, border_width: u16, _class: u16, visual: xcb_visualid_t, value_mask: u32, value_list: [*c]const xcb_create_window_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_create_window_value_list(R: [*c]const xcb_create_window_request_t) ?*anyopaque;
pub extern fn xcb_change_window_attributes_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u32, _aux: [*c]const xcb_change_window_attributes_value_list_t) c_int;
pub extern fn xcb_change_window_attributes_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u32, _aux: [*c]xcb_change_window_attributes_value_list_t) c_int;
pub extern fn xcb_change_window_attributes_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u32) c_int;
pub extern fn xcb_change_window_attributes_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_window_attributes_checked(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_window_attributes(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_window_attributes_aux_checked(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u32, value_list: [*c]const xcb_change_window_attributes_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_window_attributes_aux(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u32, value_list: [*c]const xcb_change_window_attributes_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_window_attributes_value_list(R: [*c]const xcb_change_window_attributes_request_t) ?*anyopaque;
pub extern fn xcb_get_window_attributes(c: ?*xcb_connection_t, window: xcb_window_t) xcb_get_window_attributes_cookie_t;
pub extern fn xcb_get_window_attributes_unchecked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_get_window_attributes_cookie_t;
pub extern fn xcb_get_window_attributes_reply(c: ?*xcb_connection_t, cookie: xcb_get_window_attributes_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_window_attributes_reply_t;
pub extern fn xcb_destroy_window_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_destroy_window(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_destroy_subwindows_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_destroy_subwindows(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_change_save_set_checked(c: ?*xcb_connection_t, mode: u8, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_change_save_set(c: ?*xcb_connection_t, mode: u8, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_reparent_window_checked(c: ?*xcb_connection_t, window: xcb_window_t, parent: xcb_window_t, x: i16, y: i16) xcb_void_cookie_t;
pub extern fn xcb_reparent_window(c: ?*xcb_connection_t, window: xcb_window_t, parent: xcb_window_t, x: i16, y: i16) xcb_void_cookie_t;
pub extern fn xcb_map_window_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_map_window(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_map_subwindows_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_map_subwindows(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_unmap_window_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_unmap_window(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_unmap_subwindows_checked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_unmap_subwindows(c: ?*xcb_connection_t, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_configure_window_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u16, _aux: [*c]const xcb_configure_window_value_list_t) c_int;
pub extern fn xcb_configure_window_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u16, _aux: [*c]xcb_configure_window_value_list_t) c_int;
pub extern fn xcb_configure_window_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u16) c_int;
pub extern fn xcb_configure_window_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_configure_window_checked(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u16, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_configure_window(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u16, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_configure_window_aux_checked(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u16, value_list: [*c]const xcb_configure_window_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_configure_window_aux(c: ?*xcb_connection_t, window: xcb_window_t, value_mask: u16, value_list: [*c]const xcb_configure_window_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_configure_window_value_list(R: [*c]const xcb_configure_window_request_t) ?*anyopaque;
pub extern fn xcb_circulate_window_checked(c: ?*xcb_connection_t, direction: u8, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_circulate_window(c: ?*xcb_connection_t, direction: u8, window: xcb_window_t) xcb_void_cookie_t;
pub extern fn xcb_get_geometry(c: ?*xcb_connection_t, drawable: xcb_drawable_t) xcb_get_geometry_cookie_t;
pub extern fn xcb_get_geometry_unchecked(c: ?*xcb_connection_t, drawable: xcb_drawable_t) xcb_get_geometry_cookie_t;
pub extern fn xcb_get_geometry_reply(c: ?*xcb_connection_t, cookie: xcb_get_geometry_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_geometry_reply_t;
pub extern fn xcb_query_tree_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_query_tree(c: ?*xcb_connection_t, window: xcb_window_t) xcb_query_tree_cookie_t;
pub extern fn xcb_query_tree_unchecked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_query_tree_cookie_t;
pub extern fn xcb_query_tree_children(R: [*c]const xcb_query_tree_reply_t) [*c]xcb_window_t;
pub extern fn xcb_query_tree_children_length(R: [*c]const xcb_query_tree_reply_t) c_int;
pub extern fn xcb_query_tree_children_end(R: [*c]const xcb_query_tree_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_query_tree_reply(c: ?*xcb_connection_t, cookie: xcb_query_tree_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_tree_reply_t;
pub extern fn xcb_intern_atom_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_intern_atom(c: ?*xcb_connection_t, only_if_exists: u8, name_len: u16, name: [*c]const u8) xcb_intern_atom_cookie_t;
pub extern fn xcb_intern_atom_unchecked(c: ?*xcb_connection_t, only_if_exists: u8, name_len: u16, name: [*c]const u8) xcb_intern_atom_cookie_t;
pub extern fn xcb_intern_atom_reply(c: ?*xcb_connection_t, cookie: xcb_intern_atom_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_intern_atom_reply_t;
pub extern fn xcb_get_atom_name_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_atom_name(c: ?*xcb_connection_t, atom: xcb_atom_t) xcb_get_atom_name_cookie_t;
pub extern fn xcb_get_atom_name_unchecked(c: ?*xcb_connection_t, atom: xcb_atom_t) xcb_get_atom_name_cookie_t;
pub extern fn xcb_get_atom_name_name(R: [*c]const xcb_get_atom_name_reply_t) [*c]u8;
pub extern fn xcb_get_atom_name_name_length(R: [*c]const xcb_get_atom_name_reply_t) c_int;
pub extern fn xcb_get_atom_name_name_end(R: [*c]const xcb_get_atom_name_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_atom_name_reply(c: ?*xcb_connection_t, cookie: xcb_get_atom_name_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_atom_name_reply_t;
pub extern fn xcb_change_property_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_property_checked(c: ?*xcb_connection_t, mode: u8, window: xcb_window_t, property: xcb_atom_t, @"type": xcb_atom_t, format: u8, data_len: u32, data: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_property(c: ?*xcb_connection_t, mode: u8, window: xcb_window_t, property: xcb_atom_t, @"type": xcb_atom_t, format: u8, data_len: u32, data: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_property_data(R: [*c]const xcb_change_property_request_t) ?*anyopaque;
pub extern fn xcb_change_property_data_length(R: [*c]const xcb_change_property_request_t) c_int;
pub extern fn xcb_change_property_data_end(R: [*c]const xcb_change_property_request_t) xcb_generic_iterator_t;
pub extern fn xcb_delete_property_checked(c: ?*xcb_connection_t, window: xcb_window_t, property: xcb_atom_t) xcb_void_cookie_t;
pub extern fn xcb_delete_property(c: ?*xcb_connection_t, window: xcb_window_t, property: xcb_atom_t) xcb_void_cookie_t;
pub extern fn xcb_get_property_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_property(c: ?*xcb_connection_t, _delete: u8, window: xcb_window_t, property: xcb_atom_t, @"type": xcb_atom_t, long_offset: u32, long_length: u32) xcb_get_property_cookie_t;
pub extern fn xcb_get_property_unchecked(c: ?*xcb_connection_t, _delete: u8, window: xcb_window_t, property: xcb_atom_t, @"type": xcb_atom_t, long_offset: u32, long_length: u32) xcb_get_property_cookie_t;
pub extern fn xcb_get_property_value(R: [*c]const xcb_get_property_reply_t) ?*anyopaque;
pub extern fn xcb_get_property_value_length(R: [*c]const xcb_get_property_reply_t) c_int;
pub extern fn xcb_get_property_value_end(R: [*c]const xcb_get_property_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_property_reply(c: ?*xcb_connection_t, cookie: xcb_get_property_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_property_reply_t;
pub extern fn xcb_list_properties_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_properties(c: ?*xcb_connection_t, window: xcb_window_t) xcb_list_properties_cookie_t;
pub extern fn xcb_list_properties_unchecked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_list_properties_cookie_t;
pub extern fn xcb_list_properties_atoms(R: [*c]const xcb_list_properties_reply_t) [*c]xcb_atom_t;
pub extern fn xcb_list_properties_atoms_length(R: [*c]const xcb_list_properties_reply_t) c_int;
pub extern fn xcb_list_properties_atoms_end(R: [*c]const xcb_list_properties_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_list_properties_reply(c: ?*xcb_connection_t, cookie: xcb_list_properties_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_properties_reply_t;
pub extern fn xcb_set_selection_owner_checked(c: ?*xcb_connection_t, owner: xcb_window_t, selection: xcb_atom_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_set_selection_owner(c: ?*xcb_connection_t, owner: xcb_window_t, selection: xcb_atom_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_get_selection_owner(c: ?*xcb_connection_t, selection: xcb_atom_t) xcb_get_selection_owner_cookie_t;
pub extern fn xcb_get_selection_owner_unchecked(c: ?*xcb_connection_t, selection: xcb_atom_t) xcb_get_selection_owner_cookie_t;
pub extern fn xcb_get_selection_owner_reply(c: ?*xcb_connection_t, cookie: xcb_get_selection_owner_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_selection_owner_reply_t;
pub extern fn xcb_convert_selection_checked(c: ?*xcb_connection_t, requestor: xcb_window_t, selection: xcb_atom_t, target: xcb_atom_t, property: xcb_atom_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_convert_selection(c: ?*xcb_connection_t, requestor: xcb_window_t, selection: xcb_atom_t, target: xcb_atom_t, property: xcb_atom_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_send_event_checked(c: ?*xcb_connection_t, propagate: u8, destination: xcb_window_t, event_mask: u32, event: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_send_event(c: ?*xcb_connection_t, propagate: u8, destination: xcb_window_t, event_mask: u32, event: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_grab_pointer(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, event_mask: u16, pointer_mode: u8, keyboard_mode: u8, confine_to: xcb_window_t, cursor: xcb_cursor_t, time: xcb_timestamp_t) xcb_grab_pointer_cookie_t;
pub extern fn xcb_grab_pointer_unchecked(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, event_mask: u16, pointer_mode: u8, keyboard_mode: u8, confine_to: xcb_window_t, cursor: xcb_cursor_t, time: xcb_timestamp_t) xcb_grab_pointer_cookie_t;
pub extern fn xcb_grab_pointer_reply(c: ?*xcb_connection_t, cookie: xcb_grab_pointer_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_grab_pointer_reply_t;
pub extern fn xcb_ungrab_pointer_checked(c: ?*xcb_connection_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_ungrab_pointer(c: ?*xcb_connection_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_grab_button_checked(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, event_mask: u16, pointer_mode: u8, keyboard_mode: u8, confine_to: xcb_window_t, cursor: xcb_cursor_t, button: u8, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_grab_button(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, event_mask: u16, pointer_mode: u8, keyboard_mode: u8, confine_to: xcb_window_t, cursor: xcb_cursor_t, button: u8, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_ungrab_button_checked(c: ?*xcb_connection_t, button: u8, grab_window: xcb_window_t, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_ungrab_button(c: ?*xcb_connection_t, button: u8, grab_window: xcb_window_t, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_change_active_pointer_grab_checked(c: ?*xcb_connection_t, cursor: xcb_cursor_t, time: xcb_timestamp_t, event_mask: u16) xcb_void_cookie_t;
pub extern fn xcb_change_active_pointer_grab(c: ?*xcb_connection_t, cursor: xcb_cursor_t, time: xcb_timestamp_t, event_mask: u16) xcb_void_cookie_t;
pub extern fn xcb_grab_keyboard(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, time: xcb_timestamp_t, pointer_mode: u8, keyboard_mode: u8) xcb_grab_keyboard_cookie_t;
pub extern fn xcb_grab_keyboard_unchecked(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, time: xcb_timestamp_t, pointer_mode: u8, keyboard_mode: u8) xcb_grab_keyboard_cookie_t;
pub extern fn xcb_grab_keyboard_reply(c: ?*xcb_connection_t, cookie: xcb_grab_keyboard_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_grab_keyboard_reply_t;
pub extern fn xcb_ungrab_keyboard_checked(c: ?*xcb_connection_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_ungrab_keyboard(c: ?*xcb_connection_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_grab_key_checked(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, modifiers: u16, key: xcb_keycode_t, pointer_mode: u8, keyboard_mode: u8) xcb_void_cookie_t;
pub extern fn xcb_grab_key(c: ?*xcb_connection_t, owner_events: u8, grab_window: xcb_window_t, modifiers: u16, key: xcb_keycode_t, pointer_mode: u8, keyboard_mode: u8) xcb_void_cookie_t;
pub extern fn xcb_ungrab_key_checked(c: ?*xcb_connection_t, key: xcb_keycode_t, grab_window: xcb_window_t, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_ungrab_key(c: ?*xcb_connection_t, key: xcb_keycode_t, grab_window: xcb_window_t, modifiers: u16) xcb_void_cookie_t;
pub extern fn xcb_allow_events_checked(c: ?*xcb_connection_t, mode: u8, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_allow_events(c: ?*xcb_connection_t, mode: u8, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_grab_server_checked(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub extern fn xcb_grab_server(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub extern fn xcb_ungrab_server_checked(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub extern fn xcb_ungrab_server(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub extern fn xcb_query_pointer(c: ?*xcb_connection_t, window: xcb_window_t) xcb_query_pointer_cookie_t;
pub extern fn xcb_query_pointer_unchecked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_query_pointer_cookie_t;
pub extern fn xcb_query_pointer_reply(c: ?*xcb_connection_t, cookie: xcb_query_pointer_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_pointer_reply_t;
pub extern fn xcb_timecoord_next(i: [*c]xcb_timecoord_iterator_t) void;
pub extern fn xcb_timecoord_end(i: xcb_timecoord_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_get_motion_events_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_motion_events(c: ?*xcb_connection_t, window: xcb_window_t, start: xcb_timestamp_t, stop: xcb_timestamp_t) xcb_get_motion_events_cookie_t;
pub extern fn xcb_get_motion_events_unchecked(c: ?*xcb_connection_t, window: xcb_window_t, start: xcb_timestamp_t, stop: xcb_timestamp_t) xcb_get_motion_events_cookie_t;
pub extern fn xcb_get_motion_events_events(R: [*c]const xcb_get_motion_events_reply_t) [*c]xcb_timecoord_t;
pub extern fn xcb_get_motion_events_events_length(R: [*c]const xcb_get_motion_events_reply_t) c_int;
pub extern fn xcb_get_motion_events_events_iterator(R: [*c]const xcb_get_motion_events_reply_t) xcb_timecoord_iterator_t;
pub extern fn xcb_get_motion_events_reply(c: ?*xcb_connection_t, cookie: xcb_get_motion_events_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_motion_events_reply_t;
pub extern fn xcb_translate_coordinates(c: ?*xcb_connection_t, src_window: xcb_window_t, dst_window: xcb_window_t, src_x: i16, src_y: i16) xcb_translate_coordinates_cookie_t;
pub extern fn xcb_translate_coordinates_unchecked(c: ?*xcb_connection_t, src_window: xcb_window_t, dst_window: xcb_window_t, src_x: i16, src_y: i16) xcb_translate_coordinates_cookie_t;
pub extern fn xcb_translate_coordinates_reply(c: ?*xcb_connection_t, cookie: xcb_translate_coordinates_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_translate_coordinates_reply_t;
pub extern fn xcb_warp_pointer_checked(c: ?*xcb_connection_t, src_window: xcb_window_t, dst_window: xcb_window_t, src_x: i16, src_y: i16, src_width: u16, src_height: u16, dst_x: i16, dst_y: i16) xcb_void_cookie_t;
pub extern fn xcb_warp_pointer(c: ?*xcb_connection_t, src_window: xcb_window_t, dst_window: xcb_window_t, src_x: i16, src_y: i16, src_width: u16, src_height: u16, dst_x: i16, dst_y: i16) xcb_void_cookie_t;
pub extern fn xcb_set_input_focus_checked(c: ?*xcb_connection_t, revert_to: u8, focus: xcb_window_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_set_input_focus(c: ?*xcb_connection_t, revert_to: u8, focus: xcb_window_t, time: xcb_timestamp_t) xcb_void_cookie_t;
pub extern fn xcb_get_input_focus(c: ?*xcb_connection_t) xcb_get_input_focus_cookie_t;
pub extern fn xcb_get_input_focus_unchecked(c: ?*xcb_connection_t) xcb_get_input_focus_cookie_t;
pub extern fn xcb_get_input_focus_reply(c: ?*xcb_connection_t, cookie: xcb_get_input_focus_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_input_focus_reply_t;
pub extern fn xcb_query_keymap(c: ?*xcb_connection_t) xcb_query_keymap_cookie_t;
pub extern fn xcb_query_keymap_unchecked(c: ?*xcb_connection_t) xcb_query_keymap_cookie_t;
pub extern fn xcb_query_keymap_reply(c: ?*xcb_connection_t, cookie: xcb_query_keymap_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_keymap_reply_t;
pub extern fn xcb_open_font_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_open_font_checked(c: ?*xcb_connection_t, fid: xcb_font_t, name_len: u16, name: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_open_font(c: ?*xcb_connection_t, fid: xcb_font_t, name_len: u16, name: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_open_font_name(R: [*c]const xcb_open_font_request_t) [*c]u8;
pub extern fn xcb_open_font_name_length(R: [*c]const xcb_open_font_request_t) c_int;
pub extern fn xcb_open_font_name_end(R: [*c]const xcb_open_font_request_t) xcb_generic_iterator_t;
pub extern fn xcb_close_font_checked(c: ?*xcb_connection_t, font: xcb_font_t) xcb_void_cookie_t;
pub extern fn xcb_close_font(c: ?*xcb_connection_t, font: xcb_font_t) xcb_void_cookie_t;
pub extern fn xcb_fontprop_next(i: [*c]xcb_fontprop_iterator_t) void;
pub extern fn xcb_fontprop_end(i: xcb_fontprop_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_charinfo_next(i: [*c]xcb_charinfo_iterator_t) void;
pub extern fn xcb_charinfo_end(i: xcb_charinfo_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_query_font_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_query_font(c: ?*xcb_connection_t, font: xcb_fontable_t) xcb_query_font_cookie_t;
pub extern fn xcb_query_font_unchecked(c: ?*xcb_connection_t, font: xcb_fontable_t) xcb_query_font_cookie_t;
pub extern fn xcb_query_font_properties(R: [*c]const xcb_query_font_reply_t) [*c]xcb_fontprop_t;
pub extern fn xcb_query_font_properties_length(R: [*c]const xcb_query_font_reply_t) c_int;
pub extern fn xcb_query_font_properties_iterator(R: [*c]const xcb_query_font_reply_t) xcb_fontprop_iterator_t;
pub extern fn xcb_query_font_char_infos(R: [*c]const xcb_query_font_reply_t) [*c]xcb_charinfo_t;
pub extern fn xcb_query_font_char_infos_length(R: [*c]const xcb_query_font_reply_t) c_int;
pub extern fn xcb_query_font_char_infos_iterator(R: [*c]const xcb_query_font_reply_t) xcb_charinfo_iterator_t;
pub extern fn xcb_query_font_reply(c: ?*xcb_connection_t, cookie: xcb_query_font_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_font_reply_t;
pub extern fn xcb_query_text_extents_sizeof(_buffer: ?*const anyopaque, string_len: u32) c_int;
pub extern fn xcb_query_text_extents(c: ?*xcb_connection_t, font: xcb_fontable_t, string_len: u32, string: [*c]const xcb_char2b_t) xcb_query_text_extents_cookie_t;
pub extern fn xcb_query_text_extents_unchecked(c: ?*xcb_connection_t, font: xcb_fontable_t, string_len: u32, string: [*c]const xcb_char2b_t) xcb_query_text_extents_cookie_t;
pub extern fn xcb_query_text_extents_reply(c: ?*xcb_connection_t, cookie: xcb_query_text_extents_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_text_extents_reply_t;
pub extern fn xcb_str_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_str_name(R: [*c]const xcb_str_t) [*c]u8;
pub extern fn xcb_str_name_length(R: [*c]const xcb_str_t) c_int;
pub extern fn xcb_str_name_end(R: [*c]const xcb_str_t) xcb_generic_iterator_t;
pub extern fn xcb_str_next(i: [*c]xcb_str_iterator_t) void;
pub extern fn xcb_str_end(i: xcb_str_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_list_fonts_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_fonts(c: ?*xcb_connection_t, max_names: u16, pattern_len: u16, pattern: [*c]const u8) xcb_list_fonts_cookie_t;
pub extern fn xcb_list_fonts_unchecked(c: ?*xcb_connection_t, max_names: u16, pattern_len: u16, pattern: [*c]const u8) xcb_list_fonts_cookie_t;
pub extern fn xcb_list_fonts_names_length(R: [*c]const xcb_list_fonts_reply_t) c_int;
pub extern fn xcb_list_fonts_names_iterator(R: [*c]const xcb_list_fonts_reply_t) xcb_str_iterator_t;
pub extern fn xcb_list_fonts_reply(c: ?*xcb_connection_t, cookie: xcb_list_fonts_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_fonts_reply_t;
pub extern fn xcb_list_fonts_with_info_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_fonts_with_info(c: ?*xcb_connection_t, max_names: u16, pattern_len: u16, pattern: [*c]const u8) xcb_list_fonts_with_info_cookie_t;
pub extern fn xcb_list_fonts_with_info_unchecked(c: ?*xcb_connection_t, max_names: u16, pattern_len: u16, pattern: [*c]const u8) xcb_list_fonts_with_info_cookie_t;
pub extern fn xcb_list_fonts_with_info_properties(R: [*c]const xcb_list_fonts_with_info_reply_t) [*c]xcb_fontprop_t;
pub extern fn xcb_list_fonts_with_info_properties_length(R: [*c]const xcb_list_fonts_with_info_reply_t) c_int;
pub extern fn xcb_list_fonts_with_info_properties_iterator(R: [*c]const xcb_list_fonts_with_info_reply_t) xcb_fontprop_iterator_t;
pub extern fn xcb_list_fonts_with_info_name(R: [*c]const xcb_list_fonts_with_info_reply_t) [*c]u8;
pub extern fn xcb_list_fonts_with_info_name_length(R: [*c]const xcb_list_fonts_with_info_reply_t) c_int;
pub extern fn xcb_list_fonts_with_info_name_end(R: [*c]const xcb_list_fonts_with_info_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_list_fonts_with_info_reply(c: ?*xcb_connection_t, cookie: xcb_list_fonts_with_info_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_fonts_with_info_reply_t;
pub extern fn xcb_set_font_path_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_set_font_path_checked(c: ?*xcb_connection_t, font_qty: u16, font: [*c]const xcb_str_t) xcb_void_cookie_t;
pub extern fn xcb_set_font_path(c: ?*xcb_connection_t, font_qty: u16, font: [*c]const xcb_str_t) xcb_void_cookie_t;
pub extern fn xcb_set_font_path_font_length(R: [*c]const xcb_set_font_path_request_t) c_int;
pub extern fn xcb_set_font_path_font_iterator(R: [*c]const xcb_set_font_path_request_t) xcb_str_iterator_t;
pub extern fn xcb_get_font_path_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_font_path(c: ?*xcb_connection_t) xcb_get_font_path_cookie_t;
pub extern fn xcb_get_font_path_unchecked(c: ?*xcb_connection_t) xcb_get_font_path_cookie_t;
pub extern fn xcb_get_font_path_path_length(R: [*c]const xcb_get_font_path_reply_t) c_int;
pub extern fn xcb_get_font_path_path_iterator(R: [*c]const xcb_get_font_path_reply_t) xcb_str_iterator_t;
pub extern fn xcb_get_font_path_reply(c: ?*xcb_connection_t, cookie: xcb_get_font_path_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_font_path_reply_t;
pub extern fn xcb_create_pixmap_checked(c: ?*xcb_connection_t, depth: u8, pid: xcb_pixmap_t, drawable: xcb_drawable_t, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_create_pixmap(c: ?*xcb_connection_t, depth: u8, pid: xcb_pixmap_t, drawable: xcb_drawable_t, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_free_pixmap_checked(c: ?*xcb_connection_t, pixmap: xcb_pixmap_t) xcb_void_cookie_t;
pub extern fn xcb_free_pixmap(c: ?*xcb_connection_t, pixmap: xcb_pixmap_t) xcb_void_cookie_t;
pub extern fn xcb_create_gc_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u32, _aux: [*c]const xcb_create_gc_value_list_t) c_int;
pub extern fn xcb_create_gc_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u32, _aux: [*c]xcb_create_gc_value_list_t) c_int;
pub extern fn xcb_create_gc_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u32) c_int;
pub extern fn xcb_create_gc_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_create_gc_checked(c: ?*xcb_connection_t, cid: xcb_gcontext_t, drawable: xcb_drawable_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_create_gc(c: ?*xcb_connection_t, cid: xcb_gcontext_t, drawable: xcb_drawable_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_create_gc_aux_checked(c: ?*xcb_connection_t, cid: xcb_gcontext_t, drawable: xcb_drawable_t, value_mask: u32, value_list: [*c]const xcb_create_gc_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_create_gc_aux(c: ?*xcb_connection_t, cid: xcb_gcontext_t, drawable: xcb_drawable_t, value_mask: u32, value_list: [*c]const xcb_create_gc_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_create_gc_value_list(R: [*c]const xcb_create_gc_request_t) ?*anyopaque;
pub extern fn xcb_change_gc_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u32, _aux: [*c]const xcb_change_gc_value_list_t) c_int;
pub extern fn xcb_change_gc_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u32, _aux: [*c]xcb_change_gc_value_list_t) c_int;
pub extern fn xcb_change_gc_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u32) c_int;
pub extern fn xcb_change_gc_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_gc_checked(c: ?*xcb_connection_t, gc: xcb_gcontext_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_gc(c: ?*xcb_connection_t, gc: xcb_gcontext_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_gc_aux_checked(c: ?*xcb_connection_t, gc: xcb_gcontext_t, value_mask: u32, value_list: [*c]const xcb_change_gc_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_gc_aux(c: ?*xcb_connection_t, gc: xcb_gcontext_t, value_mask: u32, value_list: [*c]const xcb_change_gc_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_gc_value_list(R: [*c]const xcb_change_gc_request_t) ?*anyopaque;
pub extern fn xcb_copy_gc_checked(c: ?*xcb_connection_t, src_gc: xcb_gcontext_t, dst_gc: xcb_gcontext_t, value_mask: u32) xcb_void_cookie_t;
pub extern fn xcb_copy_gc(c: ?*xcb_connection_t, src_gc: xcb_gcontext_t, dst_gc: xcb_gcontext_t, value_mask: u32) xcb_void_cookie_t;
pub extern fn xcb_set_dashes_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_set_dashes_checked(c: ?*xcb_connection_t, gc: xcb_gcontext_t, dash_offset: u16, dashes_len: u16, dashes: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_set_dashes(c: ?*xcb_connection_t, gc: xcb_gcontext_t, dash_offset: u16, dashes_len: u16, dashes: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_set_dashes_dashes(R: [*c]const xcb_set_dashes_request_t) [*c]u8;
pub extern fn xcb_set_dashes_dashes_length(R: [*c]const xcb_set_dashes_request_t) c_int;
pub extern fn xcb_set_dashes_dashes_end(R: [*c]const xcb_set_dashes_request_t) xcb_generic_iterator_t;
pub extern fn xcb_set_clip_rectangles_sizeof(_buffer: ?*const anyopaque, rectangles_len: u32) c_int;
pub extern fn xcb_set_clip_rectangles_checked(c: ?*xcb_connection_t, ordering: u8, gc: xcb_gcontext_t, clip_x_origin: i16, clip_y_origin: i16, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_set_clip_rectangles(c: ?*xcb_connection_t, ordering: u8, gc: xcb_gcontext_t, clip_x_origin: i16, clip_y_origin: i16, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_set_clip_rectangles_rectangles(R: [*c]const xcb_set_clip_rectangles_request_t) [*c]xcb_rectangle_t;
pub extern fn xcb_set_clip_rectangles_rectangles_length(R: [*c]const xcb_set_clip_rectangles_request_t) c_int;
pub extern fn xcb_set_clip_rectangles_rectangles_iterator(R: [*c]const xcb_set_clip_rectangles_request_t) xcb_rectangle_iterator_t;
pub extern fn xcb_free_gc_checked(c: ?*xcb_connection_t, gc: xcb_gcontext_t) xcb_void_cookie_t;
pub extern fn xcb_free_gc(c: ?*xcb_connection_t, gc: xcb_gcontext_t) xcb_void_cookie_t;
pub extern fn xcb_clear_area_checked(c: ?*xcb_connection_t, exposures: u8, window: xcb_window_t, x: i16, y: i16, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_clear_area(c: ?*xcb_connection_t, exposures: u8, window: xcb_window_t, x: i16, y: i16, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_copy_area_checked(c: ?*xcb_connection_t, src_drawable: xcb_drawable_t, dst_drawable: xcb_drawable_t, gc: xcb_gcontext_t, src_x: i16, src_y: i16, dst_x: i16, dst_y: i16, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_copy_area(c: ?*xcb_connection_t, src_drawable: xcb_drawable_t, dst_drawable: xcb_drawable_t, gc: xcb_gcontext_t, src_x: i16, src_y: i16, dst_x: i16, dst_y: i16, width: u16, height: u16) xcb_void_cookie_t;
pub extern fn xcb_copy_plane_checked(c: ?*xcb_connection_t, src_drawable: xcb_drawable_t, dst_drawable: xcb_drawable_t, gc: xcb_gcontext_t, src_x: i16, src_y: i16, dst_x: i16, dst_y: i16, width: u16, height: u16, bit_plane: u32) xcb_void_cookie_t;
pub extern fn xcb_copy_plane(c: ?*xcb_connection_t, src_drawable: xcb_drawable_t, dst_drawable: xcb_drawable_t, gc: xcb_gcontext_t, src_x: i16, src_y: i16, dst_x: i16, dst_y: i16, width: u16, height: u16, bit_plane: u32) xcb_void_cookie_t;
pub extern fn xcb_poly_point_sizeof(_buffer: ?*const anyopaque, points_len: u32) c_int;
pub extern fn xcb_poly_point_checked(c: ?*xcb_connection_t, coordinate_mode: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_poly_point(c: ?*xcb_connection_t, coordinate_mode: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_poly_point_points(R: [*c]const xcb_poly_point_request_t) [*c]xcb_point_t;
pub extern fn xcb_poly_point_points_length(R: [*c]const xcb_poly_point_request_t) c_int;
pub extern fn xcb_poly_point_points_iterator(R: [*c]const xcb_poly_point_request_t) xcb_point_iterator_t;
pub extern fn xcb_poly_line_sizeof(_buffer: ?*const anyopaque, points_len: u32) c_int;
pub extern fn xcb_poly_line_checked(c: ?*xcb_connection_t, coordinate_mode: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_poly_line(c: ?*xcb_connection_t, coordinate_mode: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_poly_line_points(R: [*c]const xcb_poly_line_request_t) [*c]xcb_point_t;
pub extern fn xcb_poly_line_points_length(R: [*c]const xcb_poly_line_request_t) c_int;
pub extern fn xcb_poly_line_points_iterator(R: [*c]const xcb_poly_line_request_t) xcb_point_iterator_t;
pub extern fn xcb_segment_next(i: [*c]xcb_segment_iterator_t) void;
pub extern fn xcb_segment_end(i: xcb_segment_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_poly_segment_sizeof(_buffer: ?*const anyopaque, segments_len: u32) c_int;
pub extern fn xcb_poly_segment_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, segments_len: u32, segments: [*c]const xcb_segment_t) xcb_void_cookie_t;
pub extern fn xcb_poly_segment(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, segments_len: u32, segments: [*c]const xcb_segment_t) xcb_void_cookie_t;
pub extern fn xcb_poly_segment_segments(R: [*c]const xcb_poly_segment_request_t) [*c]xcb_segment_t;
pub extern fn xcb_poly_segment_segments_length(R: [*c]const xcb_poly_segment_request_t) c_int;
pub extern fn xcb_poly_segment_segments_iterator(R: [*c]const xcb_poly_segment_request_t) xcb_segment_iterator_t;
pub extern fn xcb_poly_rectangle_sizeof(_buffer: ?*const anyopaque, rectangles_len: u32) c_int;
pub extern fn xcb_poly_rectangle_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_poly_rectangle(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_poly_rectangle_rectangles(R: [*c]const xcb_poly_rectangle_request_t) [*c]xcb_rectangle_t;
pub extern fn xcb_poly_rectangle_rectangles_length(R: [*c]const xcb_poly_rectangle_request_t) c_int;
pub extern fn xcb_poly_rectangle_rectangles_iterator(R: [*c]const xcb_poly_rectangle_request_t) xcb_rectangle_iterator_t;
pub extern fn xcb_poly_arc_sizeof(_buffer: ?*const anyopaque, arcs_len: u32) c_int;
pub extern fn xcb_poly_arc_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, arcs_len: u32, arcs: [*c]const xcb_arc_t) xcb_void_cookie_t;
pub extern fn xcb_poly_arc(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, arcs_len: u32, arcs: [*c]const xcb_arc_t) xcb_void_cookie_t;
pub extern fn xcb_poly_arc_arcs(R: [*c]const xcb_poly_arc_request_t) [*c]xcb_arc_t;
pub extern fn xcb_poly_arc_arcs_length(R: [*c]const xcb_poly_arc_request_t) c_int;
pub extern fn xcb_poly_arc_arcs_iterator(R: [*c]const xcb_poly_arc_request_t) xcb_arc_iterator_t;
pub extern fn xcb_fill_poly_sizeof(_buffer: ?*const anyopaque, points_len: u32) c_int;
pub extern fn xcb_fill_poly_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, shape: u8, coordinate_mode: u8, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_fill_poly(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, shape: u8, coordinate_mode: u8, points_len: u32, points: [*c]const xcb_point_t) xcb_void_cookie_t;
pub extern fn xcb_fill_poly_points(R: [*c]const xcb_fill_poly_request_t) [*c]xcb_point_t;
pub extern fn xcb_fill_poly_points_length(R: [*c]const xcb_fill_poly_request_t) c_int;
pub extern fn xcb_fill_poly_points_iterator(R: [*c]const xcb_fill_poly_request_t) xcb_point_iterator_t;
pub extern fn xcb_poly_fill_rectangle_sizeof(_buffer: ?*const anyopaque, rectangles_len: u32) c_int;
pub extern fn xcb_poly_fill_rectangle_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_poly_fill_rectangle(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, rectangles_len: u32, rectangles: [*c]const xcb_rectangle_t) xcb_void_cookie_t;
pub extern fn xcb_poly_fill_rectangle_rectangles(R: [*c]const xcb_poly_fill_rectangle_request_t) [*c]xcb_rectangle_t;
pub extern fn xcb_poly_fill_rectangle_rectangles_length(R: [*c]const xcb_poly_fill_rectangle_request_t) c_int;
pub extern fn xcb_poly_fill_rectangle_rectangles_iterator(R: [*c]const xcb_poly_fill_rectangle_request_t) xcb_rectangle_iterator_t;
pub extern fn xcb_poly_fill_arc_sizeof(_buffer: ?*const anyopaque, arcs_len: u32) c_int;
pub extern fn xcb_poly_fill_arc_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, arcs_len: u32, arcs: [*c]const xcb_arc_t) xcb_void_cookie_t;
pub extern fn xcb_poly_fill_arc(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, arcs_len: u32, arcs: [*c]const xcb_arc_t) xcb_void_cookie_t;
pub extern fn xcb_poly_fill_arc_arcs(R: [*c]const xcb_poly_fill_arc_request_t) [*c]xcb_arc_t;
pub extern fn xcb_poly_fill_arc_arcs_length(R: [*c]const xcb_poly_fill_arc_request_t) c_int;
pub extern fn xcb_poly_fill_arc_arcs_iterator(R: [*c]const xcb_poly_fill_arc_request_t) xcb_arc_iterator_t;
pub extern fn xcb_put_image_sizeof(_buffer: ?*const anyopaque, data_len: u32) c_int;
pub extern fn xcb_put_image_checked(c: ?*xcb_connection_t, format: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, width: u16, height: u16, dst_x: i16, dst_y: i16, left_pad: u8, depth: u8, data_len: u32, data: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_put_image(c: ?*xcb_connection_t, format: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, width: u16, height: u16, dst_x: i16, dst_y: i16, left_pad: u8, depth: u8, data_len: u32, data: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_put_image_data(R: [*c]const xcb_put_image_request_t) [*c]u8;
pub extern fn xcb_put_image_data_length(R: [*c]const xcb_put_image_request_t) c_int;
pub extern fn xcb_put_image_data_end(R: [*c]const xcb_put_image_request_t) xcb_generic_iterator_t;
pub extern fn xcb_get_image_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_image(c: ?*xcb_connection_t, format: u8, drawable: xcb_drawable_t, x: i16, y: i16, width: u16, height: u16, plane_mask: u32) xcb_get_image_cookie_t;
pub extern fn xcb_get_image_unchecked(c: ?*xcb_connection_t, format: u8, drawable: xcb_drawable_t, x: i16, y: i16, width: u16, height: u16, plane_mask: u32) xcb_get_image_cookie_t;
pub extern fn xcb_get_image_data(R: [*c]const xcb_get_image_reply_t) [*c]u8;
pub extern fn xcb_get_image_data_length(R: [*c]const xcb_get_image_reply_t) c_int;
pub extern fn xcb_get_image_data_end(R: [*c]const xcb_get_image_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_image_reply(c: ?*xcb_connection_t, cookie: xcb_get_image_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_image_reply_t;
pub extern fn xcb_poly_text_8_sizeof(_buffer: ?*const anyopaque, items_len: u32) c_int;
pub extern fn xcb_poly_text_8_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, items_len: u32, items: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_poly_text_8(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, items_len: u32, items: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_poly_text_8_items(R: [*c]const xcb_poly_text_8_request_t) [*c]u8;
pub extern fn xcb_poly_text_8_items_length(R: [*c]const xcb_poly_text_8_request_t) c_int;
pub extern fn xcb_poly_text_8_items_end(R: [*c]const xcb_poly_text_8_request_t) xcb_generic_iterator_t;
pub extern fn xcb_poly_text_16_sizeof(_buffer: ?*const anyopaque, items_len: u32) c_int;
pub extern fn xcb_poly_text_16_checked(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, items_len: u32, items: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_poly_text_16(c: ?*xcb_connection_t, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, items_len: u32, items: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_poly_text_16_items(R: [*c]const xcb_poly_text_16_request_t) [*c]u8;
pub extern fn xcb_poly_text_16_items_length(R: [*c]const xcb_poly_text_16_request_t) c_int;
pub extern fn xcb_poly_text_16_items_end(R: [*c]const xcb_poly_text_16_request_t) xcb_generic_iterator_t;
pub extern fn xcb_image_text_8_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_image_text_8_checked(c: ?*xcb_connection_t, string_len: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, string: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_image_text_8(c: ?*xcb_connection_t, string_len: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, string: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_image_text_8_string(R: [*c]const xcb_image_text_8_request_t) [*c]u8;
pub extern fn xcb_image_text_8_string_length(R: [*c]const xcb_image_text_8_request_t) c_int;
pub extern fn xcb_image_text_8_string_end(R: [*c]const xcb_image_text_8_request_t) xcb_generic_iterator_t;
pub extern fn xcb_image_text_16_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_image_text_16_checked(c: ?*xcb_connection_t, string_len: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, string: [*c]const xcb_char2b_t) xcb_void_cookie_t;
pub extern fn xcb_image_text_16(c: ?*xcb_connection_t, string_len: u8, drawable: xcb_drawable_t, gc: xcb_gcontext_t, x: i16, y: i16, string: [*c]const xcb_char2b_t) xcb_void_cookie_t;
pub extern fn xcb_image_text_16_string(R: [*c]const xcb_image_text_16_request_t) [*c]xcb_char2b_t;
pub extern fn xcb_image_text_16_string_length(R: [*c]const xcb_image_text_16_request_t) c_int;
pub extern fn xcb_image_text_16_string_iterator(R: [*c]const xcb_image_text_16_request_t) xcb_char2b_iterator_t;
pub extern fn xcb_create_colormap_checked(c: ?*xcb_connection_t, alloc: u8, mid: xcb_colormap_t, window: xcb_window_t, visual: xcb_visualid_t) xcb_void_cookie_t;
pub extern fn xcb_create_colormap(c: ?*xcb_connection_t, alloc: u8, mid: xcb_colormap_t, window: xcb_window_t, visual: xcb_visualid_t) xcb_void_cookie_t;
pub extern fn xcb_free_colormap_checked(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_free_colormap(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_copy_colormap_and_free_checked(c: ?*xcb_connection_t, mid: xcb_colormap_t, src_cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_copy_colormap_and_free(c: ?*xcb_connection_t, mid: xcb_colormap_t, src_cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_install_colormap_checked(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_install_colormap(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_uninstall_colormap_checked(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_uninstall_colormap(c: ?*xcb_connection_t, cmap: xcb_colormap_t) xcb_void_cookie_t;
pub extern fn xcb_list_installed_colormaps_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_installed_colormaps(c: ?*xcb_connection_t, window: xcb_window_t) xcb_list_installed_colormaps_cookie_t;
pub extern fn xcb_list_installed_colormaps_unchecked(c: ?*xcb_connection_t, window: xcb_window_t) xcb_list_installed_colormaps_cookie_t;
pub extern fn xcb_list_installed_colormaps_cmaps(R: [*c]const xcb_list_installed_colormaps_reply_t) [*c]xcb_colormap_t;
pub extern fn xcb_list_installed_colormaps_cmaps_length(R: [*c]const xcb_list_installed_colormaps_reply_t) c_int;
pub extern fn xcb_list_installed_colormaps_cmaps_end(R: [*c]const xcb_list_installed_colormaps_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_list_installed_colormaps_reply(c: ?*xcb_connection_t, cookie: xcb_list_installed_colormaps_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_installed_colormaps_reply_t;
pub extern fn xcb_alloc_color(c: ?*xcb_connection_t, cmap: xcb_colormap_t, red: u16, green: u16, blue: u16) xcb_alloc_color_cookie_t;
pub extern fn xcb_alloc_color_unchecked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, red: u16, green: u16, blue: u16) xcb_alloc_color_cookie_t;
pub extern fn xcb_alloc_color_reply(c: ?*xcb_connection_t, cookie: xcb_alloc_color_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_alloc_color_reply_t;
pub extern fn xcb_alloc_named_color_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_alloc_named_color(c: ?*xcb_connection_t, cmap: xcb_colormap_t, name_len: u16, name: [*c]const u8) xcb_alloc_named_color_cookie_t;
pub extern fn xcb_alloc_named_color_unchecked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, name_len: u16, name: [*c]const u8) xcb_alloc_named_color_cookie_t;
pub extern fn xcb_alloc_named_color_reply(c: ?*xcb_connection_t, cookie: xcb_alloc_named_color_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_alloc_named_color_reply_t;
pub extern fn xcb_alloc_color_cells_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_alloc_color_cells(c: ?*xcb_connection_t, contiguous: u8, cmap: xcb_colormap_t, colors: u16, planes: u16) xcb_alloc_color_cells_cookie_t;
pub extern fn xcb_alloc_color_cells_unchecked(c: ?*xcb_connection_t, contiguous: u8, cmap: xcb_colormap_t, colors: u16, planes: u16) xcb_alloc_color_cells_cookie_t;
pub extern fn xcb_alloc_color_cells_pixels(R: [*c]const xcb_alloc_color_cells_reply_t) [*c]u32;
pub extern fn xcb_alloc_color_cells_pixels_length(R: [*c]const xcb_alloc_color_cells_reply_t) c_int;
pub extern fn xcb_alloc_color_cells_pixels_end(R: [*c]const xcb_alloc_color_cells_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_alloc_color_cells_masks(R: [*c]const xcb_alloc_color_cells_reply_t) [*c]u32;
pub extern fn xcb_alloc_color_cells_masks_length(R: [*c]const xcb_alloc_color_cells_reply_t) c_int;
pub extern fn xcb_alloc_color_cells_masks_end(R: [*c]const xcb_alloc_color_cells_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_alloc_color_cells_reply(c: ?*xcb_connection_t, cookie: xcb_alloc_color_cells_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_alloc_color_cells_reply_t;
pub extern fn xcb_alloc_color_planes_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_alloc_color_planes(c: ?*xcb_connection_t, contiguous: u8, cmap: xcb_colormap_t, colors: u16, reds: u16, greens: u16, blues: u16) xcb_alloc_color_planes_cookie_t;
pub extern fn xcb_alloc_color_planes_unchecked(c: ?*xcb_connection_t, contiguous: u8, cmap: xcb_colormap_t, colors: u16, reds: u16, greens: u16, blues: u16) xcb_alloc_color_planes_cookie_t;
pub extern fn xcb_alloc_color_planes_pixels(R: [*c]const xcb_alloc_color_planes_reply_t) [*c]u32;
pub extern fn xcb_alloc_color_planes_pixels_length(R: [*c]const xcb_alloc_color_planes_reply_t) c_int;
pub extern fn xcb_alloc_color_planes_pixels_end(R: [*c]const xcb_alloc_color_planes_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_alloc_color_planes_reply(c: ?*xcb_connection_t, cookie: xcb_alloc_color_planes_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_alloc_color_planes_reply_t;
pub extern fn xcb_free_colors_sizeof(_buffer: ?*const anyopaque, pixels_len: u32) c_int;
pub extern fn xcb_free_colors_checked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, plane_mask: u32, pixels_len: u32, pixels: [*c]const u32) xcb_void_cookie_t;
pub extern fn xcb_free_colors(c: ?*xcb_connection_t, cmap: xcb_colormap_t, plane_mask: u32, pixels_len: u32, pixels: [*c]const u32) xcb_void_cookie_t;
pub extern fn xcb_free_colors_pixels(R: [*c]const xcb_free_colors_request_t) [*c]u32;
pub extern fn xcb_free_colors_pixels_length(R: [*c]const xcb_free_colors_request_t) c_int;
pub extern fn xcb_free_colors_pixels_end(R: [*c]const xcb_free_colors_request_t) xcb_generic_iterator_t;
pub extern fn xcb_coloritem_next(i: [*c]xcb_coloritem_iterator_t) void;
pub extern fn xcb_coloritem_end(i: xcb_coloritem_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_store_colors_sizeof(_buffer: ?*const anyopaque, items_len: u32) c_int;
pub extern fn xcb_store_colors_checked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, items_len: u32, items: [*c]const xcb_coloritem_t) xcb_void_cookie_t;
pub extern fn xcb_store_colors(c: ?*xcb_connection_t, cmap: xcb_colormap_t, items_len: u32, items: [*c]const xcb_coloritem_t) xcb_void_cookie_t;
pub extern fn xcb_store_colors_items(R: [*c]const xcb_store_colors_request_t) [*c]xcb_coloritem_t;
pub extern fn xcb_store_colors_items_length(R: [*c]const xcb_store_colors_request_t) c_int;
pub extern fn xcb_store_colors_items_iterator(R: [*c]const xcb_store_colors_request_t) xcb_coloritem_iterator_t;
pub extern fn xcb_store_named_color_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_store_named_color_checked(c: ?*xcb_connection_t, flags: u8, cmap: xcb_colormap_t, pixel: u32, name_len: u16, name: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_store_named_color(c: ?*xcb_connection_t, flags: u8, cmap: xcb_colormap_t, pixel: u32, name_len: u16, name: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_store_named_color_name(R: [*c]const xcb_store_named_color_request_t) [*c]u8;
pub extern fn xcb_store_named_color_name_length(R: [*c]const xcb_store_named_color_request_t) c_int;
pub extern fn xcb_store_named_color_name_end(R: [*c]const xcb_store_named_color_request_t) xcb_generic_iterator_t;
pub extern fn xcb_rgb_next(i: [*c]xcb_rgb_iterator_t) void;
pub extern fn xcb_rgb_end(i: xcb_rgb_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_query_colors_sizeof(_buffer: ?*const anyopaque, pixels_len: u32) c_int;
pub extern fn xcb_query_colors(c: ?*xcb_connection_t, cmap: xcb_colormap_t, pixels_len: u32, pixels: [*c]const u32) xcb_query_colors_cookie_t;
pub extern fn xcb_query_colors_unchecked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, pixels_len: u32, pixels: [*c]const u32) xcb_query_colors_cookie_t;
pub extern fn xcb_query_colors_colors(R: [*c]const xcb_query_colors_reply_t) [*c]xcb_rgb_t;
pub extern fn xcb_query_colors_colors_length(R: [*c]const xcb_query_colors_reply_t) c_int;
pub extern fn xcb_query_colors_colors_iterator(R: [*c]const xcb_query_colors_reply_t) xcb_rgb_iterator_t;
pub extern fn xcb_query_colors_reply(c: ?*xcb_connection_t, cookie: xcb_query_colors_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_colors_reply_t;
pub extern fn xcb_lookup_color_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_lookup_color(c: ?*xcb_connection_t, cmap: xcb_colormap_t, name_len: u16, name: [*c]const u8) xcb_lookup_color_cookie_t;
pub extern fn xcb_lookup_color_unchecked(c: ?*xcb_connection_t, cmap: xcb_colormap_t, name_len: u16, name: [*c]const u8) xcb_lookup_color_cookie_t;
pub extern fn xcb_lookup_color_reply(c: ?*xcb_connection_t, cookie: xcb_lookup_color_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_lookup_color_reply_t;
pub extern fn xcb_create_cursor_checked(c: ?*xcb_connection_t, cid: xcb_cursor_t, source: xcb_pixmap_t, mask: xcb_pixmap_t, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16, x: u16, y: u16) xcb_void_cookie_t;
pub extern fn xcb_create_cursor(c: ?*xcb_connection_t, cid: xcb_cursor_t, source: xcb_pixmap_t, mask: xcb_pixmap_t, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16, x: u16, y: u16) xcb_void_cookie_t;
pub extern fn xcb_create_glyph_cursor_checked(c: ?*xcb_connection_t, cid: xcb_cursor_t, source_font: xcb_font_t, mask_font: xcb_font_t, source_char: u16, mask_char: u16, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16) xcb_void_cookie_t;
pub extern fn xcb_create_glyph_cursor(c: ?*xcb_connection_t, cid: xcb_cursor_t, source_font: xcb_font_t, mask_font: xcb_font_t, source_char: u16, mask_char: u16, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16) xcb_void_cookie_t;
pub extern fn xcb_free_cursor_checked(c: ?*xcb_connection_t, cursor: xcb_cursor_t) xcb_void_cookie_t;
pub extern fn xcb_free_cursor(c: ?*xcb_connection_t, cursor: xcb_cursor_t) xcb_void_cookie_t;
pub extern fn xcb_recolor_cursor_checked(c: ?*xcb_connection_t, cursor: xcb_cursor_t, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16) xcb_void_cookie_t;
pub extern fn xcb_recolor_cursor(c: ?*xcb_connection_t, cursor: xcb_cursor_t, fore_red: u16, fore_green: u16, fore_blue: u16, back_red: u16, back_green: u16, back_blue: u16) xcb_void_cookie_t;
pub extern fn xcb_query_best_size(c: ?*xcb_connection_t, _class: u8, drawable: xcb_drawable_t, width: u16, height: u16) xcb_query_best_size_cookie_t;
pub extern fn xcb_query_best_size_unchecked(c: ?*xcb_connection_t, _class: u8, drawable: xcb_drawable_t, width: u16, height: u16) xcb_query_best_size_cookie_t;
pub extern fn xcb_query_best_size_reply(c: ?*xcb_connection_t, cookie: xcb_query_best_size_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_best_size_reply_t;
pub extern fn xcb_query_extension_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_query_extension(c: ?*xcb_connection_t, name_len: u16, name: [*c]const u8) xcb_query_extension_cookie_t;
pub extern fn xcb_query_extension_unchecked(c: ?*xcb_connection_t, name_len: u16, name: [*c]const u8) xcb_query_extension_cookie_t;
pub extern fn xcb_query_extension_reply(c: ?*xcb_connection_t, cookie: xcb_query_extension_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_query_extension_reply_t;
pub extern fn xcb_list_extensions_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_extensions(c: ?*xcb_connection_t) xcb_list_extensions_cookie_t;
pub extern fn xcb_list_extensions_unchecked(c: ?*xcb_connection_t) xcb_list_extensions_cookie_t;
pub extern fn xcb_list_extensions_names_length(R: [*c]const xcb_list_extensions_reply_t) c_int;
pub extern fn xcb_list_extensions_names_iterator(R: [*c]const xcb_list_extensions_reply_t) xcb_str_iterator_t;
pub extern fn xcb_list_extensions_reply(c: ?*xcb_connection_t, cookie: xcb_list_extensions_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_extensions_reply_t;
pub extern fn xcb_change_keyboard_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_keyboard_mapping_checked(c: ?*xcb_connection_t, keycode_count: u8, first_keycode: xcb_keycode_t, keysyms_per_keycode: u8, keysyms: [*c]const xcb_keysym_t) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_mapping(c: ?*xcb_connection_t, keycode_count: u8, first_keycode: xcb_keycode_t, keysyms_per_keycode: u8, keysyms: [*c]const xcb_keysym_t) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_mapping_keysyms(R: [*c]const xcb_change_keyboard_mapping_request_t) [*c]xcb_keysym_t;
pub extern fn xcb_change_keyboard_mapping_keysyms_length(R: [*c]const xcb_change_keyboard_mapping_request_t) c_int;
pub extern fn xcb_change_keyboard_mapping_keysyms_end(R: [*c]const xcb_change_keyboard_mapping_request_t) xcb_generic_iterator_t;
pub extern fn xcb_get_keyboard_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_keyboard_mapping(c: ?*xcb_connection_t, first_keycode: xcb_keycode_t, count: u8) xcb_get_keyboard_mapping_cookie_t;
pub extern fn xcb_get_keyboard_mapping_unchecked(c: ?*xcb_connection_t, first_keycode: xcb_keycode_t, count: u8) xcb_get_keyboard_mapping_cookie_t;
pub extern fn xcb_get_keyboard_mapping_keysyms(R: [*c]const xcb_get_keyboard_mapping_reply_t) [*c]xcb_keysym_t;
pub extern fn xcb_get_keyboard_mapping_keysyms_length(R: [*c]const xcb_get_keyboard_mapping_reply_t) c_int;
pub extern fn xcb_get_keyboard_mapping_keysyms_end(R: [*c]const xcb_get_keyboard_mapping_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_keyboard_mapping_reply(c: ?*xcb_connection_t, cookie: xcb_get_keyboard_mapping_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_keyboard_mapping_reply_t;
pub extern fn xcb_change_keyboard_control_value_list_serialize(_buffer: [*c]?*anyopaque, value_mask: u32, _aux: [*c]const xcb_change_keyboard_control_value_list_t) c_int;
pub extern fn xcb_change_keyboard_control_value_list_unpack(_buffer: ?*const anyopaque, value_mask: u32, _aux: [*c]xcb_change_keyboard_control_value_list_t) c_int;
pub extern fn xcb_change_keyboard_control_value_list_sizeof(_buffer: ?*const anyopaque, value_mask: u32) c_int;
pub extern fn xcb_change_keyboard_control_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_keyboard_control_checked(c: ?*xcb_connection_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_control(c: ?*xcb_connection_t, value_mask: u32, value_list: ?*const anyopaque) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_control_aux_checked(c: ?*xcb_connection_t, value_mask: u32, value_list: [*c]const xcb_change_keyboard_control_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_control_aux(c: ?*xcb_connection_t, value_mask: u32, value_list: [*c]const xcb_change_keyboard_control_value_list_t) xcb_void_cookie_t;
pub extern fn xcb_change_keyboard_control_value_list(R: [*c]const xcb_change_keyboard_control_request_t) ?*anyopaque;
pub extern fn xcb_get_keyboard_control(c: ?*xcb_connection_t) xcb_get_keyboard_control_cookie_t;
pub extern fn xcb_get_keyboard_control_unchecked(c: ?*xcb_connection_t) xcb_get_keyboard_control_cookie_t;
pub extern fn xcb_get_keyboard_control_reply(c: ?*xcb_connection_t, cookie: xcb_get_keyboard_control_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_keyboard_control_reply_t;
pub extern fn xcb_bell_checked(c: ?*xcb_connection_t, percent: i8) xcb_void_cookie_t;
pub extern fn xcb_bell(c: ?*xcb_connection_t, percent: i8) xcb_void_cookie_t;
pub extern fn xcb_change_pointer_control_checked(c: ?*xcb_connection_t, acceleration_numerator: i16, acceleration_denominator: i16, threshold: i16, do_acceleration: u8, do_threshold: u8) xcb_void_cookie_t;
pub extern fn xcb_change_pointer_control(c: ?*xcb_connection_t, acceleration_numerator: i16, acceleration_denominator: i16, threshold: i16, do_acceleration: u8, do_threshold: u8) xcb_void_cookie_t;
pub extern fn xcb_get_pointer_control(c: ?*xcb_connection_t) xcb_get_pointer_control_cookie_t;
pub extern fn xcb_get_pointer_control_unchecked(c: ?*xcb_connection_t) xcb_get_pointer_control_cookie_t;
pub extern fn xcb_get_pointer_control_reply(c: ?*xcb_connection_t, cookie: xcb_get_pointer_control_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_pointer_control_reply_t;
pub extern fn xcb_set_screen_saver_checked(c: ?*xcb_connection_t, timeout: i16, interval: i16, prefer_blanking: u8, allow_exposures: u8) xcb_void_cookie_t;
pub extern fn xcb_set_screen_saver(c: ?*xcb_connection_t, timeout: i16, interval: i16, prefer_blanking: u8, allow_exposures: u8) xcb_void_cookie_t;
pub extern fn xcb_get_screen_saver(c: ?*xcb_connection_t) xcb_get_screen_saver_cookie_t;
pub extern fn xcb_get_screen_saver_unchecked(c: ?*xcb_connection_t) xcb_get_screen_saver_cookie_t;
pub extern fn xcb_get_screen_saver_reply(c: ?*xcb_connection_t, cookie: xcb_get_screen_saver_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_screen_saver_reply_t;
pub extern fn xcb_change_hosts_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_change_hosts_checked(c: ?*xcb_connection_t, mode: u8, family: u8, address_len: u16, address: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_change_hosts(c: ?*xcb_connection_t, mode: u8, family: u8, address_len: u16, address: [*c]const u8) xcb_void_cookie_t;
pub extern fn xcb_change_hosts_address(R: [*c]const xcb_change_hosts_request_t) [*c]u8;
pub extern fn xcb_change_hosts_address_length(R: [*c]const xcb_change_hosts_request_t) c_int;
pub extern fn xcb_change_hosts_address_end(R: [*c]const xcb_change_hosts_request_t) xcb_generic_iterator_t;
pub extern fn xcb_host_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_host_address(R: [*c]const xcb_host_t) [*c]u8;
pub extern fn xcb_host_address_length(R: [*c]const xcb_host_t) c_int;
pub extern fn xcb_host_address_end(R: [*c]const xcb_host_t) xcb_generic_iterator_t;
pub extern fn xcb_host_next(i: [*c]xcb_host_iterator_t) void;
pub extern fn xcb_host_end(i: xcb_host_iterator_t) xcb_generic_iterator_t;
pub extern fn xcb_list_hosts_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_list_hosts(c: ?*xcb_connection_t) xcb_list_hosts_cookie_t;
pub extern fn xcb_list_hosts_unchecked(c: ?*xcb_connection_t) xcb_list_hosts_cookie_t;
pub extern fn xcb_list_hosts_hosts_length(R: [*c]const xcb_list_hosts_reply_t) c_int;
pub extern fn xcb_list_hosts_hosts_iterator(R: [*c]const xcb_list_hosts_reply_t) xcb_host_iterator_t;
pub extern fn xcb_list_hosts_reply(c: ?*xcb_connection_t, cookie: xcb_list_hosts_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_list_hosts_reply_t;
pub extern fn xcb_set_access_control_checked(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_set_access_control(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_set_close_down_mode_checked(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_set_close_down_mode(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_kill_client_checked(c: ?*xcb_connection_t, resource: u32) xcb_void_cookie_t;
pub extern fn xcb_kill_client(c: ?*xcb_connection_t, resource: u32) xcb_void_cookie_t;
pub extern fn xcb_rotate_properties_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_rotate_properties_checked(c: ?*xcb_connection_t, window: xcb_window_t, atoms_len: u16, delta: i16, atoms: [*c]const xcb_atom_t) xcb_void_cookie_t;
pub extern fn xcb_rotate_properties(c: ?*xcb_connection_t, window: xcb_window_t, atoms_len: u16, delta: i16, atoms: [*c]const xcb_atom_t) xcb_void_cookie_t;
pub extern fn xcb_rotate_properties_atoms(R: [*c]const xcb_rotate_properties_request_t) [*c]xcb_atom_t;
pub extern fn xcb_rotate_properties_atoms_length(R: [*c]const xcb_rotate_properties_request_t) c_int;
pub extern fn xcb_rotate_properties_atoms_end(R: [*c]const xcb_rotate_properties_request_t) xcb_generic_iterator_t;
pub extern fn xcb_force_screen_saver_checked(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_force_screen_saver(c: ?*xcb_connection_t, mode: u8) xcb_void_cookie_t;
pub extern fn xcb_set_pointer_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_set_pointer_mapping(c: ?*xcb_connection_t, map_len: u8, map: [*c]const u8) xcb_set_pointer_mapping_cookie_t;
pub extern fn xcb_set_pointer_mapping_unchecked(c: ?*xcb_connection_t, map_len: u8, map: [*c]const u8) xcb_set_pointer_mapping_cookie_t;
pub extern fn xcb_set_pointer_mapping_reply(c: ?*xcb_connection_t, cookie: xcb_set_pointer_mapping_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_set_pointer_mapping_reply_t;
pub extern fn xcb_get_pointer_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_pointer_mapping(c: ?*xcb_connection_t) xcb_get_pointer_mapping_cookie_t;
pub extern fn xcb_get_pointer_mapping_unchecked(c: ?*xcb_connection_t) xcb_get_pointer_mapping_cookie_t;
pub extern fn xcb_get_pointer_mapping_map(R: [*c]const xcb_get_pointer_mapping_reply_t) [*c]u8;
pub extern fn xcb_get_pointer_mapping_map_length(R: [*c]const xcb_get_pointer_mapping_reply_t) c_int;
pub extern fn xcb_get_pointer_mapping_map_end(R: [*c]const xcb_get_pointer_mapping_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_pointer_mapping_reply(c: ?*xcb_connection_t, cookie: xcb_get_pointer_mapping_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_pointer_mapping_reply_t;
pub extern fn xcb_set_modifier_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_set_modifier_mapping(c: ?*xcb_connection_t, keycodes_per_modifier: u8, keycodes: [*c]const xcb_keycode_t) xcb_set_modifier_mapping_cookie_t;
pub extern fn xcb_set_modifier_mapping_unchecked(c: ?*xcb_connection_t, keycodes_per_modifier: u8, keycodes: [*c]const xcb_keycode_t) xcb_set_modifier_mapping_cookie_t;
pub extern fn xcb_set_modifier_mapping_reply(c: ?*xcb_connection_t, cookie: xcb_set_modifier_mapping_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_set_modifier_mapping_reply_t;
pub extern fn xcb_get_modifier_mapping_sizeof(_buffer: ?*const anyopaque) c_int;
pub extern fn xcb_get_modifier_mapping(c: ?*xcb_connection_t) xcb_get_modifier_mapping_cookie_t;
pub extern fn xcb_get_modifier_mapping_unchecked(c: ?*xcb_connection_t) xcb_get_modifier_mapping_cookie_t;
pub extern fn xcb_get_modifier_mapping_keycodes(R: [*c]const xcb_get_modifier_mapping_reply_t) [*c]xcb_keycode_t;
pub extern fn xcb_get_modifier_mapping_keycodes_length(R: [*c]const xcb_get_modifier_mapping_reply_t) c_int;
pub extern fn xcb_get_modifier_mapping_keycodes_end(R: [*c]const xcb_get_modifier_mapping_reply_t) xcb_generic_iterator_t;
pub extern fn xcb_get_modifier_mapping_reply(c: ?*xcb_connection_t, cookie: xcb_get_modifier_mapping_cookie_t, e: [*c][*c]xcb_generic_error_t) [*c]xcb_get_modifier_mapping_reply_t;
pub extern fn xcb_no_operation_checked(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub extern fn xcb_no_operation(c: ?*xcb_connection_t) xcb_void_cookie_t;
pub const struct_xcb_auth_info_t = extern struct {
    namelen: c_int = @import("std").mem.zeroes(c_int),
    name: [*c]u8 = @import("std").mem.zeroes([*c]u8),
    datalen: c_int = @import("std").mem.zeroes(c_int),
    data: [*c]u8 = @import("std").mem.zeroes([*c]u8),
};
pub const xcb_auth_info_t = struct_xcb_auth_info_t;
pub extern fn xcb_flush(c: ?*xcb_connection_t) c_int;
pub extern fn xcb_get_maximum_request_length(c: ?*xcb_connection_t) u32;
pub extern fn xcb_prefetch_maximum_request_length(c: ?*xcb_connection_t) void;
pub extern fn xcb_wait_for_event(c: ?*xcb_connection_t) [*c]xcb_generic_event_t;
pub extern fn xcb_poll_for_event(c: ?*xcb_connection_t) [*c]xcb_generic_event_t;
pub extern fn xcb_poll_for_queued_event(c: ?*xcb_connection_t) [*c]xcb_generic_event_t;
pub const struct_xcb_special_event = opaque {};
pub const xcb_special_event_t = struct_xcb_special_event;
pub extern fn xcb_poll_for_special_event(c: ?*xcb_connection_t, se: ?*xcb_special_event_t) [*c]xcb_generic_event_t;
pub extern fn xcb_wait_for_special_event(c: ?*xcb_connection_t, se: ?*xcb_special_event_t) [*c]xcb_generic_event_t;
pub const struct_xcb_extension_t = opaque {};
pub const xcb_extension_t = struct_xcb_extension_t;
pub extern fn xcb_register_for_special_xge(c: ?*xcb_connection_t, ext: ?*xcb_extension_t, eid: u32, stamp: [*c]u32) ?*xcb_special_event_t;
pub extern fn xcb_unregister_for_special_event(c: ?*xcb_connection_t, se: ?*xcb_special_event_t) void;
pub extern fn xcb_request_check(c: ?*xcb_connection_t, cookie: xcb_void_cookie_t) [*c]xcb_generic_error_t;
pub extern fn xcb_discard_reply(c: ?*xcb_connection_t, sequence: c_uint) void;
pub extern fn xcb_discard_reply64(c: ?*xcb_connection_t, sequence: u64) void;
pub extern fn xcb_get_extension_data(c: ?*xcb_connection_t, ext: ?*xcb_extension_t) [*c]const struct_xcb_query_extension_reply_t;
pub extern fn xcb_prefetch_extension_data(c: ?*xcb_connection_t, ext: ?*xcb_extension_t) void;
pub extern fn xcb_get_setup(c: ?*xcb_connection_t) [*c]const struct_xcb_setup_t;
pub extern fn xcb_get_file_descriptor(c: ?*xcb_connection_t) c_int;
pub extern fn xcb_connection_has_error(c: ?*xcb_connection_t) c_int;
pub extern fn xcb_connect_to_fd(fd: c_int, auth_info: [*c]xcb_auth_info_t) ?*xcb_connection_t;
pub extern fn xcb_disconnect(c: ?*xcb_connection_t) void;
pub extern fn xcb_parse_display(name: [*c]const u8, host: [*c][*c]u8, display: [*c]c_int, screen: [*c]c_int) c_int;
pub extern fn xcb_connect(displayname: [*c]const u8, screenp: [*c]c_int) ?*xcb_connection_t;
pub extern fn xcb_connect_to_display_with_auth_info(display: [*c]const u8, auth: [*c]xcb_auth_info_t, screen: [*c]c_int) ?*xcb_connection_t;
pub extern fn xcb_generate_id(c: ?*xcb_connection_t) u32;
pub extern fn xcb_total_read(c: ?*xcb_connection_t) u64;
pub extern fn xcb_total_written(c: ?*xcb_connection_t) u64;
pub const XKB_X11_SETUP_XKB_EXTENSION_NO_FLAGS: c_int = 0;
pub const enum_xkb_x11_setup_xkb_extension_flags = c_uint;
pub extern fn xkb_x11_setup_xkb_extension(connection: ?*xcb_connection_t, major_xkb_version: u16, minor_xkb_version: u16, flags: enum_xkb_x11_setup_xkb_extension_flags, major_xkb_version_out: [*c]u16, minor_xkb_version_out: [*c]u16, base_event_out: [*c]u8, base_error_out: [*c]u8) c_int;
pub extern fn xkb_x11_get_core_keyboard_device_id(connection: ?*xcb_connection_t) i32;
pub extern fn xkb_x11_keymap_new_from_device(context: ?*struct_xkb_context, connection: ?*xcb_connection_t, device_id: i32, flags: enum_xkb_keymap_compile_flags) ?*struct_xkb_keymap;
pub extern fn xkb_x11_state_new_from_device(keymap: ?*struct_xkb_keymap, connection: ?*xcb_connection_t, device_id: i32) ?*struct_xkb_state;
pub const struct_xkb_compose_table = opaque {};
pub const struct_xkb_compose_state = opaque {};
pub const XKB_COMPOSE_COMPILE_NO_FLAGS: c_int = 0;
pub const enum_xkb_compose_compile_flags = c_uint;
pub const XKB_COMPOSE_FORMAT_TEXT_V1: c_int = 1;
pub const enum_xkb_compose_format = c_uint;
pub extern fn xkb_compose_table_new_from_locale(context: ?*struct_xkb_context, locale: [*c]const u8, flags: enum_xkb_compose_compile_flags) ?*struct_xkb_compose_table;
pub extern fn xkb_compose_table_new_from_file(context: ?*struct_xkb_context, file: ?*FILE, locale: [*c]const u8, format: enum_xkb_compose_format, flags: enum_xkb_compose_compile_flags) ?*struct_xkb_compose_table;
pub extern fn xkb_compose_table_new_from_buffer(context: ?*struct_xkb_context, buffer: [*c]const u8, length: usize, locale: [*c]const u8, format: enum_xkb_compose_format, flags: enum_xkb_compose_compile_flags) ?*struct_xkb_compose_table;
pub extern fn xkb_compose_table_ref(table: ?*struct_xkb_compose_table) ?*struct_xkb_compose_table;
pub extern fn xkb_compose_table_unref(table: ?*struct_xkb_compose_table) void;
pub const struct_xkb_compose_table_entry = opaque {};
pub extern fn xkb_compose_table_entry_sequence(entry: ?*struct_xkb_compose_table_entry, sequence_length: [*c]usize) [*c]const xkb_keysym_t;
pub extern fn xkb_compose_table_entry_keysym(entry: ?*struct_xkb_compose_table_entry) xkb_keysym_t;
pub extern fn xkb_compose_table_entry_utf8(entry: ?*struct_xkb_compose_table_entry) [*c]const u8;
pub const struct_xkb_compose_table_iterator = opaque {};
pub extern fn xkb_compose_table_iterator_new(table: ?*struct_xkb_compose_table) ?*struct_xkb_compose_table_iterator;
pub extern fn xkb_compose_table_iterator_free(iter: ?*struct_xkb_compose_table_iterator) void;
pub extern fn xkb_compose_table_iterator_next(iter: ?*struct_xkb_compose_table_iterator) ?*struct_xkb_compose_table_entry;
pub const XKB_COMPOSE_STATE_NO_FLAGS: c_int = 0;
pub const enum_xkb_compose_state_flags = c_uint;
pub extern fn xkb_compose_state_new(table: ?*struct_xkb_compose_table, flags: enum_xkb_compose_state_flags) ?*struct_xkb_compose_state;
pub extern fn xkb_compose_state_ref(state: ?*struct_xkb_compose_state) ?*struct_xkb_compose_state;
pub extern fn xkb_compose_state_unref(state: ?*struct_xkb_compose_state) void;
pub extern fn xkb_compose_state_get_compose_table(state: ?*struct_xkb_compose_state) ?*struct_xkb_compose_table;
pub const XKB_COMPOSE_NOTHING: c_int = 0;
pub const XKB_COMPOSE_COMPOSING: c_int = 1;
pub const XKB_COMPOSE_COMPOSED: c_int = 2;
pub const XKB_COMPOSE_CANCELLED: c_int = 3;
pub const enum_xkb_compose_status = c_uint;
pub const XKB_COMPOSE_FEED_IGNORED: c_int = 0;
pub const XKB_COMPOSE_FEED_ACCEPTED: c_int = 1;
pub const enum_xkb_compose_feed_result = c_uint;
pub extern fn xkb_compose_state_feed(state: ?*struct_xkb_compose_state, keysym: xkb_keysym_t) enum_xkb_compose_feed_result;
pub extern fn xkb_compose_state_reset(state: ?*struct_xkb_compose_state) void;
pub extern fn xkb_compose_state_get_status(state: ?*struct_xkb_compose_state) enum_xkb_compose_status;
pub extern fn xkb_compose_state_get_utf8(state: ?*struct_xkb_compose_state, buffer: [*c]u8, size: usize) c_int;
pub extern fn xkb_compose_state_get_one_sym(state: ?*struct_xkb_compose_state) xkb_keysym_t;
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
pub const __ARM_FEATURE_CRC32 = @as(c_int, 1);
pub const __ARM_FEATURE_RCPC = @as(c_int, 1);
pub const __ARM_FEATURE_CRYPTO = @as(c_int, 1);
pub const __ARM_FEATURE_AES = @as(c_int, 1);
pub const __ARM_FEATURE_SHA2 = @as(c_int, 1);
pub const __ARM_FEATURE_SHA3 = @as(c_int, 1);
pub const __ARM_FEATURE_SHA512 = @as(c_int, 1);
pub const __ARM_FEATURE_PAUTH = @as(c_int, 1);
pub const __ARM_FEATURE_BTI = @as(c_int, 1);
pub const __ARM_FEATURE_UNALIGNED = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_VECTOR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_SCALAR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_DOTPROD = @as(c_int, 1);
pub const __ARM_FEATURE_MATMUL_INT8 = @as(c_int, 1);
pub const __ARM_FEATURE_ATOMICS = @as(c_int, 1);
pub const __ARM_FEATURE_BF16 = @as(c_int, 1);
pub const __ARM_FEATURE_BF16_VECTOR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_BF16_FORMAT_ALTERNATIVE = @as(c_int, 1);
pub const __ARM_FEATURE_BF16_SCALAR_ARITHMETIC = @as(c_int, 1);
pub const __ARM_FEATURE_FP16_FML = @as(c_int, 1);
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
pub const _XKBCOMMON_H_ = "";
pub const __STDBOOL_H = "";
pub const __bool_true_false_are_defined = @as(c_int, 1);
pub const @"bool" = bool;
pub const @"true" = @as(c_int, 1);
pub const @"false" = @as(c_int, 0);
pub const _STDINT_H = @as(c_int, 1);
pub const __GLIBC_INTERNAL_STARTING_HEADER_IMPLEMENTATION = "";
pub const _FEATURES_H = @as(c_int, 1);
pub const __KERNEL_STRICT_NAMES = "";
pub inline fn __GNUC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GNUC__ << @as(c_int, 16)) + __GNUC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub inline fn __glibc_clang_prereq(maj: anytype, min: anytype) @TypeOf(((__clang_major__ << @as(c_int, 16)) + __clang_minor__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__clang_major__ << @as(c_int, 16)) + __clang_minor__) >= ((maj << @as(c_int, 16)) + min);
}
pub const __GLIBC_USE = @compileError("unable to translate macro: undefined identifier `__GLIBC_USE_`");
// /usr/include/features.h:191:9
pub const _DEFAULT_SOURCE = @as(c_int, 1);
pub const __GLIBC_USE_ISOC2Y = @as(c_int, 0);
pub const __GLIBC_USE_ISOC23 = @as(c_int, 0);
pub const __USE_ISOC11 = @as(c_int, 1);
pub const __USE_ISOC99 = @as(c_int, 1);
pub const __USE_ISOC95 = @as(c_int, 1);
pub const __USE_POSIX_IMPLICITLY = @as(c_int, 1);
pub const _POSIX_SOURCE = @as(c_int, 1);
pub const _POSIX_C_SOURCE = @as(c_long, 200809);
pub const __USE_POSIX = @as(c_int, 1);
pub const __USE_POSIX2 = @as(c_int, 1);
pub const __USE_POSIX199309 = @as(c_int, 1);
pub const __USE_POSIX199506 = @as(c_int, 1);
pub const __USE_XOPEN2K = @as(c_int, 1);
pub const __USE_XOPEN2K8 = @as(c_int, 1);
pub const _ATFILE_SOURCE = @as(c_int, 1);
pub const __WORDSIZE = @as(c_int, 64);
pub const __WORDSIZE_TIME64_COMPAT32 = @as(c_int, 0);
pub const __TIMESIZE = @as(c_int, 64);
pub const __USE_TIME_BITS64 = @as(c_int, 1);
pub const __USE_MISC = @as(c_int, 1);
pub const __USE_ATFILE = @as(c_int, 1);
pub const __USE_FORTIFY_LEVEL = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_GETS = @as(c_int, 0);
pub const __GLIBC_USE_DEPRECATED_SCANF = @as(c_int, 0);
pub const __GLIBC_USE_C23_STRTOL = @as(c_int, 0);
pub const _STDC_PREDEF_H = @as(c_int, 1);
pub const __STDC_IEC_559__ = @as(c_int, 1);
pub const __STDC_IEC_60559_BFP__ = @as(c_long, 201404);
pub const __STDC_IEC_559_COMPLEX__ = @as(c_int, 1);
pub const __STDC_IEC_60559_COMPLEX__ = @as(c_long, 201404);
pub const __STDC_ISO_10646__ = @as(c_long, 201706);
pub const __GNU_LIBRARY__ = @as(c_int, 6);
pub const __GLIBC__ = @as(c_int, 2);
pub const __GLIBC_MINOR__ = @as(c_int, 42);
pub inline fn __GLIBC_PREREQ(maj: anytype, min: anytype) @TypeOf(((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min)) {
    _ = &maj;
    _ = &min;
    return ((__GLIBC__ << @as(c_int, 16)) + __GLIBC_MINOR__) >= ((maj << @as(c_int, 16)) + min);
}
pub const _SYS_CDEFS_H = @as(c_int, 1);
pub const __glibc_has_attribute = @compileError("unable to translate macro: undefined identifier `__has_attribute`");
// /usr/include/sys/cdefs.h:45:10
pub inline fn __glibc_has_builtin(name: anytype) @TypeOf(__has_builtin(name)) {
    _ = &name;
    return __has_builtin(name);
}
pub const __glibc_has_extension = @compileError("unable to translate macro: undefined identifier `__has_extension`");
// /usr/include/sys/cdefs.h:55:10
pub const __LEAF = "";
pub const __LEAF_ATTR = "";
pub const __THROW = @compileError("unable to translate macro: undefined identifier `__nothrow__`");
// /usr/include/sys/cdefs.h:79:11
pub const __THROWNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`");
// /usr/include/sys/cdefs.h:80:11
pub const __NTH = @compileError("unable to translate macro: undefined identifier `__nothrow__`");
// /usr/include/sys/cdefs.h:81:11
pub const __NTHNL = @compileError("unable to translate macro: undefined identifier `__nothrow__`");
// /usr/include/sys/cdefs.h:82:11
pub const __COLD = @compileError("unable to translate macro: undefined identifier `__cold__`");
// /usr/include/sys/cdefs.h:102:11
pub inline fn __P(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub inline fn __PMT(args: anytype) @TypeOf(args) {
    _ = &args;
    return args;
}
pub const __CONCAT = @compileError("unable to translate C expr: unexpected token '##'");
// /usr/include/sys/cdefs.h:131:9
pub const __STRING = @compileError("unable to translate C expr: unexpected token '#'");
// /usr/include/sys/cdefs.h:132:9
pub const __ptr_t = ?*anyopaque;
pub const __BEGIN_DECLS = "";
pub const __END_DECLS = "";
pub const __attribute_overloadable__ = @compileError("unable to translate macro: undefined identifier `__overloadable__`");
// /usr/include/sys/cdefs.h:151:10
pub inline fn __bos(ptr: anytype) @TypeOf(__builtin_object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1))) {
    _ = &ptr;
    return __builtin_object_size(ptr, __USE_FORTIFY_LEVEL > @as(c_int, 1));
}
pub inline fn __bos0(ptr: anytype) @TypeOf(__builtin_object_size(ptr, @as(c_int, 0))) {
    _ = &ptr;
    return __builtin_object_size(ptr, @as(c_int, 0));
}
pub inline fn __glibc_objsize0(__o: anytype) @TypeOf(__bos0(__o)) {
    _ = &__o;
    return __bos0(__o);
}
pub inline fn __glibc_objsize(__o: anytype) @TypeOf(__bos(__o)) {
    _ = &__o;
    return __bos(__o);
}
pub const __warnattr = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:370:10
pub const __errordecl = @compileError("unable to translate C expr: unexpected token 'extern'");
// /usr/include/sys/cdefs.h:371:10
pub const __flexarr = @compileError("unable to translate C expr: unexpected token '['");
// /usr/include/sys/cdefs.h:379:10
pub const __glibc_c99_flexarr_available = @as(c_int, 1);
pub const __REDIRECT = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /usr/include/sys/cdefs.h:410:10
pub const __REDIRECT_NTH = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /usr/include/sys/cdefs.h:417:11
pub const __REDIRECT_NTHNL = @compileError("unable to translate C expr: unexpected token '__asm__'");
// /usr/include/sys/cdefs.h:419:11
pub const __ASMNAME = @compileError("unable to translate C expr: unexpected token ','");
// /usr/include/sys/cdefs.h:422:10
pub inline fn __ASMNAME2(prefix: anytype, cname: anytype) @TypeOf(__STRING(prefix) ++ cname) {
    _ = &prefix;
    _ = &cname;
    return __STRING(prefix) ++ cname;
}
pub const __REDIRECT_FORTIFY = __REDIRECT;
pub const __REDIRECT_FORTIFY_NTH = __REDIRECT_NTH;
pub const __attribute_malloc__ = @compileError("unable to translate macro: undefined identifier `__malloc__`");
// /usr/include/sys/cdefs.h:452:10
pub const __attribute_alloc_size__ = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:463:10
pub const __attribute_alloc_align__ = @compileError("unable to translate macro: undefined identifier `__alloc_align__`");
// /usr/include/sys/cdefs.h:469:10
pub const __attribute_pure__ = @compileError("unable to translate macro: undefined identifier `__pure__`");
// /usr/include/sys/cdefs.h:479:10
pub const __attribute_const__ = @compileError("unable to translate C expr: unexpected token '__attribute__'");
// /usr/include/sys/cdefs.h:486:10
pub const __attribute_maybe_unused__ = @compileError("unable to translate macro: undefined identifier `__unused__`");
// /usr/include/sys/cdefs.h:492:10
pub const __attribute_used__ = @compileError("unable to translate macro: undefined identifier `__used__`");
// /usr/include/sys/cdefs.h:501:10
pub const __attribute_noinline__ = @compileError("unable to translate macro: undefined identifier `__noinline__`");
// /usr/include/sys/cdefs.h:502:10
pub const __attribute_deprecated__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`");
// /usr/include/sys/cdefs.h:510:10
pub const __attribute_deprecated_msg__ = @compileError("unable to translate macro: undefined identifier `__deprecated__`");
// /usr/include/sys/cdefs.h:520:10
pub const __attribute_format_arg__ = @compileError("unable to translate macro: undefined identifier `__format_arg__`");
// /usr/include/sys/cdefs.h:533:10
pub const __attribute_format_strfmon__ = @compileError("unable to translate macro: undefined identifier `__format__`");
// /usr/include/sys/cdefs.h:543:10
pub const __attribute_nonnull__ = @compileError("unable to translate macro: undefined identifier `__nonnull__`");
// /usr/include/sys/cdefs.h:555:11
pub inline fn __nonnull(params: anytype) @TypeOf(__attribute_nonnull__(params)) {
    _ = &params;
    return __attribute_nonnull__(params);
}
pub const __returns_nonnull = @compileError("unable to translate macro: undefined identifier `__returns_nonnull__`");
// /usr/include/sys/cdefs.h:568:10
pub const __attribute_warn_unused_result__ = @compileError("unable to translate macro: undefined identifier `__warn_unused_result__`");
// /usr/include/sys/cdefs.h:577:10
pub const __wur = "";
pub const __always_inline = @compileError("unable to translate macro: undefined identifier `__always_inline__`");
// /usr/include/sys/cdefs.h:595:10
pub const __attribute_artificial__ = @compileError("unable to translate macro: undefined identifier `__artificial__`");
// /usr/include/sys/cdefs.h:604:10
pub const __extern_inline = @compileError("unable to translate macro: undefined identifier `__gnu_inline__`");
// /usr/include/sys/cdefs.h:622:11
pub const __extern_always_inline = @compileError("unable to translate macro: undefined identifier `__gnu_inline__`");
// /usr/include/sys/cdefs.h:623:11
pub const __fortify_function = __extern_always_inline ++ __attribute_artificial__;
pub const __restrict_arr = @compileError("unable to translate C expr: unexpected token '__restrict'");
// /usr/include/sys/cdefs.h:666:10
pub inline fn __glibc_unlikely(cond: anytype) @TypeOf(__builtin_expect(cond, @as(c_int, 0))) {
    _ = &cond;
    return __builtin_expect(cond, @as(c_int, 0));
}
pub inline fn __glibc_likely(cond: anytype) @TypeOf(__builtin_expect(cond, @as(c_int, 1))) {
    _ = &cond;
    return __builtin_expect(cond, @as(c_int, 1));
}
pub const __attribute_nonstring__ = "";
pub const __attribute_copy__ = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:715:10
pub const __LDOUBLE_REDIRECTS_TO_FLOAT128_ABI = @as(c_int, 0);
pub inline fn __LDBL_REDIR1(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR(name: anytype, proto: anytype) @TypeOf(name ++ proto) {
    _ = &name;
    _ = &proto;
    return name ++ proto;
}
pub inline fn __LDBL_REDIR1_NTH(name: anytype, proto: anytype, alias: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return name ++ proto ++ __THROW;
}
pub inline fn __LDBL_REDIR_NTH(name: anytype, proto: anytype) @TypeOf(name ++ proto ++ __THROW) {
    _ = &name;
    _ = &proto;
    return name ++ proto ++ __THROW;
}
pub const __LDBL_REDIR2_DECL = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:792:10
pub const __LDBL_REDIR_DECL = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:793:10
pub inline fn __REDIRECT_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT(name, proto, alias);
}
pub inline fn __REDIRECT_NTH_LDBL(name: anytype, proto: anytype, alias: anytype) @TypeOf(__REDIRECT_NTH(name, proto, alias)) {
    _ = &name;
    _ = &proto;
    _ = &alias;
    return __REDIRECT_NTH(name, proto, alias);
}
pub const __glibc_macro_warning1 = @compileError("unable to translate macro: undefined identifier `_Pragma`");
// /usr/include/sys/cdefs.h:807:10
pub const __glibc_macro_warning = @compileError("unable to translate macro: undefined identifier `GCC`");
// /usr/include/sys/cdefs.h:808:10
pub const __HAVE_GENERIC_SELECTION = @as(c_int, 1);
pub const __fortified_attr_access = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:853:11
pub const __attr_access = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:854:11
pub const __attr_access_none = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:855:11
pub const __attr_dealloc = @compileError("unable to translate C expr: unexpected token ''");
// /usr/include/sys/cdefs.h:865:10
pub const __attr_dealloc_free = "";
pub const __attribute_returns_twice__ = @compileError("unable to translate macro: undefined identifier `__returns_twice__`");
// /usr/include/sys/cdefs.h:872:10
pub const __attribute_struct_may_alias__ = @compileError("unable to translate macro: undefined identifier `__may_alias__`");
// /usr/include/sys/cdefs.h:881:10
pub const __stub___compat_bdflush = "";
pub const __stub___compat_create_module = "";
pub const __stub___compat_get_kernel_syms = "";
pub const __stub___compat_query_module = "";
pub const __stub___compat_uselib = "";
pub const __stub_chflags = "";
pub const __stub_fchflags = "";
pub const __stub_gtty = "";
pub const __stub_revoke = "";
pub const __stub_setlogin = "";
pub const __stub_sigreturn = "";
pub const __stub_stty = "";
pub const __GLIBC_USE_LIB_EXT2 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_BFP_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_FUNCS_EXT_C23 = @as(c_int, 0);
pub const __GLIBC_USE_IEC_60559_TYPES_EXT = @as(c_int, 0);
pub const _BITS_TYPES_H = @as(c_int, 1);
pub const __S16_TYPE = c_short;
pub const __U16_TYPE = c_ushort;
pub const __S32_TYPE = c_int;
pub const __U32_TYPE = c_uint;
pub const __SLONGWORD_TYPE = c_long;
pub const __ULONGWORD_TYPE = c_ulong;
pub const __SQUAD_TYPE = c_long;
pub const __UQUAD_TYPE = c_ulong;
pub const __SWORD_TYPE = c_long;
pub const __UWORD_TYPE = c_ulong;
pub const __SLONG32_TYPE = c_int;
pub const __ULONG32_TYPE = c_uint;
pub const __S64_TYPE = c_long;
pub const __U64_TYPE = c_ulong;
pub const __STD_TYPE = @compileError("unable to translate C expr: unexpected token 'typedef'");
// /usr/include/bits/types.h:137:10
pub const _BITS_TYPESIZES_H = @as(c_int, 1);
pub const __INO_T_TYPE = __ULONGWORD_TYPE;
pub const __OFF_T_TYPE = __SLONGWORD_TYPE;
pub const __RLIM_T_TYPE = __ULONGWORD_TYPE;
pub const __BLKCNT_T_TYPE = __SLONGWORD_TYPE;
pub const __FSBLKCNT_T_TYPE = __ULONGWORD_TYPE;
pub const __FSFILCNT_T_TYPE = __ULONGWORD_TYPE;
pub const __TIME_T_TYPE = __SLONGWORD_TYPE;
pub const __SUSECONDS_T_TYPE = __SLONGWORD_TYPE;
pub const __DEV_T_TYPE = __UQUAD_TYPE;
pub const __UID_T_TYPE = __U32_TYPE;
pub const __GID_T_TYPE = __U32_TYPE;
pub const __INO64_T_TYPE = __UQUAD_TYPE;
pub const __MODE_T_TYPE = __U32_TYPE;
pub const __NLINK_T_TYPE = __U32_TYPE;
pub const __OFF64_T_TYPE = __SQUAD_TYPE;
pub const __PID_T_TYPE = __S32_TYPE;
pub const __RLIM64_T_TYPE = __UQUAD_TYPE;
pub const __BLKCNT64_T_TYPE = __SQUAD_TYPE;
pub const __FSBLKCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSFILCNT64_T_TYPE = __UQUAD_TYPE;
pub const __FSWORD_T_TYPE = __SWORD_TYPE;
pub const __ID_T_TYPE = __U32_TYPE;
pub const __CLOCK_T_TYPE = __SLONGWORD_TYPE;
pub const __USECONDS_T_TYPE = __U32_TYPE;
pub const __SUSECONDS64_T_TYPE = __SQUAD_TYPE;
pub const __DADDR_T_TYPE = __S32_TYPE;
pub const __KEY_T_TYPE = __S32_TYPE;
pub const __CLOCKID_T_TYPE = __S32_TYPE;
pub const __TIMER_T_TYPE = ?*anyopaque;
pub const __BLKSIZE_T_TYPE = __S32_TYPE;
pub const __FSID_T_TYPE = @compileError("unable to translate macro: undefined identifier `__val`");
// /usr/include/bits/typesizes.h:72:9
pub const __SSIZE_T_TYPE = __SWORD_TYPE;
pub const __SYSCALL_SLONG_TYPE = __SLONGWORD_TYPE;
pub const __SYSCALL_ULONG_TYPE = __ULONGWORD_TYPE;
pub const __CPU_MASK_TYPE = __ULONGWORD_TYPE;
pub const __OFF_T_MATCHES_OFF64_T = @as(c_int, 1);
pub const __INO_T_MATCHES_INO64_T = @as(c_int, 1);
pub const __RLIM_T_MATCHES_RLIM64_T = @as(c_int, 1);
pub const __STATFS_MATCHES_STATFS64 = @as(c_int, 1);
pub const __KERNEL_OLD_TIMEVAL_MATCHES_TIMEVAL64 = __WORDSIZE == @as(c_int, 64);
pub const __FD_SETSIZE = @as(c_int, 1024);
pub const _BITS_TIME64_H = @as(c_int, 1);
pub const __TIME64_T_TYPE = __TIME_T_TYPE;
pub const _BITS_WCHAR_H = @as(c_int, 1);
pub const __WCHAR_MAX = __WCHAR_MAX__;
pub const __WCHAR_MIN = '\x00' + @as(c_int, 0);
pub const _BITS_STDINT_INTN_H = @as(c_int, 1);
pub const _BITS_STDINT_UINTN_H = @as(c_int, 1);
pub const _BITS_STDINT_LEAST_H = @as(c_int, 1);
pub const __intptr_t_defined = "";
pub const INT8_MIN = -@as(c_int, 128);
pub const INT16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT32_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT64_MIN = -__INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT8_MAX = @as(c_int, 127);
pub const INT16_MAX = @as(c_int, 32767);
pub const INT32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT64_MAX = __INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT8_MAX = @as(c_int, 255);
pub const UINT16_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT64_MAX = __UINT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_LEAST8_MIN = -@as(c_int, 128);
pub const INT_LEAST16_MIN = -@as(c_int, 32767) - @as(c_int, 1);
pub const INT_LEAST32_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const INT_LEAST64_MIN = -__INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_LEAST8_MAX = @as(c_int, 127);
pub const INT_LEAST16_MAX = @as(c_int, 32767);
pub const INT_LEAST32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const INT_LEAST64_MAX = __INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_LEAST8_MAX = @as(c_int, 255);
pub const UINT_LEAST16_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 65535, .decimal);
pub const UINT_LEAST32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
pub const UINT_LEAST64_MAX = __UINT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INT_FAST8_MIN = -@as(c_int, 128);
pub const INT_FAST16_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST32_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INT_FAST64_MIN = -__INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INT_FAST8_MAX = @as(c_int, 127);
pub const INT_FAST16_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const INT_FAST64_MAX = __INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINT_FAST8_MAX = @as(c_int, 255);
pub const UINT_FAST16_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST32_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const UINT_FAST64_MAX = __UINT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const INTPTR_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const INTPTR_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const UINTPTR_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const INTMAX_MIN = -__INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal)) - @as(c_int, 1);
pub const INTMAX_MAX = __INT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 9223372036854775807, .decimal));
pub const UINTMAX_MAX = __UINT64_C(@import("std").zig.c_translation.promoteIntLiteral(c_int, 18446744073709551615, .decimal));
pub const PTRDIFF_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal) - @as(c_int, 1);
pub const PTRDIFF_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 9223372036854775807, .decimal);
pub const SIG_ATOMIC_MIN = -@import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal) - @as(c_int, 1);
pub const SIG_ATOMIC_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 2147483647, .decimal);
pub const SIZE_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_ulong, 18446744073709551615, .decimal);
pub const WCHAR_MIN = __WCHAR_MIN;
pub const WCHAR_MAX = __WCHAR_MAX;
pub const WINT_MIN = @as(c_uint, 0);
pub const WINT_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_uint, 4294967295, .decimal);
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
pub const INT64_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub inline fn UINT8_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub inline fn UINT16_C(c: anytype) @TypeOf(c) {
    _ = &c;
    return c;
}
pub const UINT32_C = @import("std").zig.c_translation.Macros.U_SUFFIX;
pub const UINT64_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
pub const INTMAX_C = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const UINTMAX_C = @import("std").zig.c_translation.Macros.UL_SUFFIX;
pub const _STDIO_H = @as(c_int, 1);
pub const __need_size_t = "";
pub const __need_NULL = "";
pub const _SIZE_T = "";
pub const NULL = @import("std").zig.c_translation.cast(?*anyopaque, @as(c_int, 0));
pub const __need___va_list = "";
pub const __GNUC_VA_LIST = "";
pub const _____fpos_t_defined = @as(c_int, 1);
pub const ____mbstate_t_defined = @as(c_int, 1);
pub const _____fpos64_t_defined = @as(c_int, 1);
pub const ____FILE_defined = @as(c_int, 1);
pub const __FILE_defined = @as(c_int, 1);
pub const __struct_FILE_defined = @as(c_int, 1);
pub const __getc_unlocked_body = @compileError("TODO postfix inc/dec expr");
// /usr/include/bits/types/struct_FILE.h:113:9
pub const __putc_unlocked_body = @compileError("TODO postfix inc/dec expr");
// /usr/include/bits/types/struct_FILE.h:117:9
pub const _IO_EOF_SEEN = @as(c_int, 0x0010);
pub inline fn __feof_unlocked_body(_fp: anytype) @TypeOf((_fp.*._flags & _IO_EOF_SEEN) != @as(c_int, 0)) {
    _ = &_fp;
    return (_fp.*._flags & _IO_EOF_SEEN) != @as(c_int, 0);
}
pub const _IO_ERR_SEEN = @as(c_int, 0x0020);
pub inline fn __ferror_unlocked_body(_fp: anytype) @TypeOf((_fp.*._flags & _IO_ERR_SEEN) != @as(c_int, 0)) {
    _ = &_fp;
    return (_fp.*._flags & _IO_ERR_SEEN) != @as(c_int, 0);
}
pub const _IO_USER_LOCK = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x8000, .hex);
pub const __cookie_io_functions_t_defined = @as(c_int, 1);
pub const _VA_LIST_DEFINED = "";
pub const __off_t_defined = "";
pub const __ssize_t_defined = "";
pub const _IOFBF = @as(c_int, 0);
pub const _IOLBF = @as(c_int, 1);
pub const _IONBF = @as(c_int, 2);
pub const BUFSIZ = @as(c_int, 8192);
pub const EOF = -@as(c_int, 1);
pub const SEEK_SET = @as(c_int, 0);
pub const SEEK_CUR = @as(c_int, 1);
pub const SEEK_END = @as(c_int, 2);
pub const P_tmpdir = "/tmp";
pub const L_tmpnam = @as(c_int, 20);
pub const TMP_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 238328, .decimal);
pub const _BITS_STDIO_LIM_H = @as(c_int, 1);
pub const FILENAME_MAX = @as(c_int, 4096);
pub const L_ctermid = @as(c_int, 9);
pub const FOPEN_MAX = @as(c_int, 16);
pub const __attr_dealloc_fclose = __attr_dealloc(fclose, @as(c_int, 1));
pub const _BITS_FLOATN_H = "";
pub const __HAVE_FLOAT128 = @as(c_int, 1);
pub const __HAVE_DISTINCT_FLOAT128 = @as(c_int, 0);
pub const __HAVE_FLOAT64X = __HAVE_FLOAT128;
pub const __HAVE_FLOAT64X_LONG_DOUBLE = __HAVE_FLOAT128;
pub const __f128 = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const __CFLOAT128 = @compileError("unable to translate: TODO _Complex");
// /usr/include/bits/floatn.h:69:12
pub const __builtin_huge_valf128 = @compileError("unable to translate macro: undefined identifier `__builtin_huge_vall`");
// /usr/include/bits/floatn.h:85:12
pub const __builtin_inff128 = @compileError("unable to translate macro: undefined identifier `__builtin_infl`");
// /usr/include/bits/floatn.h:86:12
pub const __builtin_nanf128 = @compileError("unable to translate macro: undefined identifier `__builtin_nanl`");
// /usr/include/bits/floatn.h:87:12
pub const __builtin_nansf128 = @compileError("unable to translate macro: undefined identifier `__builtin_nansl`");
// /usr/include/bits/floatn.h:88:12
pub const _BITS_FLOATN_COMMON_H = "";
pub const __HAVE_FLOAT16 = @as(c_int, 0);
pub const __HAVE_FLOAT32 = @as(c_int, 1);
pub const __HAVE_FLOAT64 = @as(c_int, 1);
pub const __HAVE_FLOAT32X = @as(c_int, 1);
pub const __HAVE_FLOAT128X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT16 = __HAVE_FLOAT16;
pub const __HAVE_DISTINCT_FLOAT32 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64 = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT32X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT64X = @as(c_int, 0);
pub const __HAVE_DISTINCT_FLOAT128X = __HAVE_FLOAT128X;
pub const __HAVE_FLOAT128_UNLIKE_LDBL = (__HAVE_DISTINCT_FLOAT128 != 0) and (__LDBL_MANT_DIG__ != @as(c_int, 113));
pub const __HAVE_FLOATN_NOT_TYPEDEF = @as(c_int, 0);
pub const __f32 = @import("std").zig.c_translation.Macros.F_SUFFIX;
pub inline fn __f64(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub inline fn __f32x(x: anytype) @TypeOf(x) {
    _ = &x;
    return x;
}
pub const __f64x = @import("std").zig.c_translation.Macros.L_SUFFIX;
pub const __CFLOAT32 = @compileError("unable to translate: TODO _Complex");
// /usr/include/bits/floatn-common.h:149:12
pub const __CFLOAT64 = @compileError("unable to translate: TODO _Complex");
// /usr/include/bits/floatn-common.h:160:13
pub const __CFLOAT32X = @compileError("unable to translate: TODO _Complex");
// /usr/include/bits/floatn-common.h:169:12
pub const __CFLOAT64X = @compileError("unable to translate: TODO _Complex");
// /usr/include/bits/floatn-common.h:178:13
pub inline fn __builtin_huge_valf32() @TypeOf(__builtin_huge_valf()) {
    return __builtin_huge_valf();
}
pub inline fn __builtin_inff32() @TypeOf(__builtin_inff()) {
    return __builtin_inff();
}
pub inline fn __builtin_nanf32(x: anytype) @TypeOf(__builtin_nanf(x)) {
    _ = &x;
    return __builtin_nanf(x);
}
pub const __builtin_nansf32 = @compileError("unable to translate macro: undefined identifier `__builtin_nansf`");
// /usr/include/bits/floatn-common.h:221:12
pub const __builtin_huge_valf64 = @compileError("unable to translate macro: undefined identifier `__builtin_huge_val`");
// /usr/include/bits/floatn-common.h:255:13
pub const __builtin_inff64 = @compileError("unable to translate macro: undefined identifier `__builtin_inf`");
// /usr/include/bits/floatn-common.h:256:13
pub const __builtin_nanf64 = @compileError("unable to translate macro: undefined identifier `__builtin_nan`");
// /usr/include/bits/floatn-common.h:257:13
pub const __builtin_nansf64 = @compileError("unable to translate macro: undefined identifier `__builtin_nans`");
// /usr/include/bits/floatn-common.h:258:13
pub const __builtin_huge_valf32x = @compileError("unable to translate macro: undefined identifier `__builtin_huge_val`");
// /usr/include/bits/floatn-common.h:272:12
pub const __builtin_inff32x = @compileError("unable to translate macro: undefined identifier `__builtin_inf`");
// /usr/include/bits/floatn-common.h:273:12
pub const __builtin_nanf32x = @compileError("unable to translate macro: undefined identifier `__builtin_nan`");
// /usr/include/bits/floatn-common.h:274:12
pub const __builtin_nansf32x = @compileError("unable to translate macro: undefined identifier `__builtin_nans`");
// /usr/include/bits/floatn-common.h:275:12
pub const __builtin_huge_valf64x = @compileError("unable to translate macro: undefined identifier `__builtin_huge_vall`");
// /usr/include/bits/floatn-common.h:289:13
pub const __builtin_inff64x = @compileError("unable to translate macro: undefined identifier `__builtin_infl`");
// /usr/include/bits/floatn-common.h:290:13
pub const __builtin_nanf64x = @compileError("unable to translate macro: undefined identifier `__builtin_nanl`");
// /usr/include/bits/floatn-common.h:291:13
pub const __builtin_nansf64x = @compileError("unable to translate macro: undefined identifier `__builtin_nansl`");
// /usr/include/bits/floatn-common.h:292:13
pub const __need_va_list = "";
pub const __need_va_arg = "";
pub const __need___va_copy = "";
pub const __need_va_copy = "";
pub const __STDARG_H = "";
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
pub const _XKBCOMMON_NAMES_H = "";
pub const XKB_MOD_NAME_SHIFT = "Shift";
pub const XKB_MOD_NAME_CAPS = "Lock";
pub const XKB_MOD_NAME_CTRL = "Control";
pub const XKB_MOD_NAME_MOD1 = "Mod1";
pub const XKB_MOD_NAME_MOD2 = "Mod2";
pub const XKB_MOD_NAME_MOD3 = "Mod3";
pub const XKB_MOD_NAME_MOD4 = "Mod4";
pub const XKB_MOD_NAME_MOD5 = "Mod5";
pub const XKB_VMOD_NAME_ALT = "Alt";
pub const XKB_VMOD_NAME_HYPER = "Hyper";
pub const XKB_VMOD_NAME_LEVEL3 = "LevelThree";
pub const XKB_VMOD_NAME_LEVEL5 = "LevelFive";
pub const XKB_VMOD_NAME_META = "Meta";
pub const XKB_VMOD_NAME_NUM = "NumLock";
pub const XKB_VMOD_NAME_SCROLL = "ScrollLock";
pub const XKB_VMOD_NAME_SUPER = "Super";
pub const XKB_MOD_NAME_ALT = "Mod1";
pub const XKB_MOD_NAME_LOGO = "Mod4";
pub const XKB_MOD_NAME_NUM = "Mod2";
pub const XKB_LED_NAME_NUM = "Num Lock";
pub const XKB_LED_NAME_CAPS = "Caps Lock";
pub const XKB_LED_NAME_SCROLL = "Scroll Lock";
pub const XKB_LED_NAME_COMPOSE = "Compose";
pub const XKB_LED_NAME_KANA = "Kana";
pub const _XKBCOMMON_KEYSYMS_H = "";
pub const XKB_KEY_NoSymbol = @as(c_int, 0x000000);
pub const XKB_KEY_VoidSymbol = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffff, .hex);
pub const XKB_KEY_BackSpace = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff08, .hex);
pub const XKB_KEY_Tab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff09, .hex);
pub const XKB_KEY_Linefeed = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff0a, .hex);
pub const XKB_KEY_Clear = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff0b, .hex);
pub const XKB_KEY_Return = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff0d, .hex);
pub const XKB_KEY_Pause = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff13, .hex);
pub const XKB_KEY_Scroll_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff14, .hex);
pub const XKB_KEY_Sys_Req = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff15, .hex);
pub const XKB_KEY_Escape = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff1b, .hex);
pub const XKB_KEY_Delete = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffff, .hex);
pub const XKB_KEY_Multi_key = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff20, .hex);
pub const XKB_KEY_Codeinput = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff37, .hex);
pub const XKB_KEY_SingleCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3c, .hex);
pub const XKB_KEY_MultipleCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3d, .hex);
pub const XKB_KEY_PreviousCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3e, .hex);
pub const XKB_KEY_Kanji = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff21, .hex);
pub const XKB_KEY_Muhenkan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff22, .hex);
pub const XKB_KEY_Henkan_Mode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff23, .hex);
pub const XKB_KEY_Henkan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff23, .hex);
pub const XKB_KEY_Romaji = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff24, .hex);
pub const XKB_KEY_Hiragana = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff25, .hex);
pub const XKB_KEY_Katakana = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff26, .hex);
pub const XKB_KEY_Hiragana_Katakana = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff27, .hex);
pub const XKB_KEY_Zenkaku = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff28, .hex);
pub const XKB_KEY_Hankaku = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff29, .hex);
pub const XKB_KEY_Zenkaku_Hankaku = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2a, .hex);
pub const XKB_KEY_Touroku = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2b, .hex);
pub const XKB_KEY_Massyo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2c, .hex);
pub const XKB_KEY_Kana_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2d, .hex);
pub const XKB_KEY_Kana_Shift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2e, .hex);
pub const XKB_KEY_Eisu_Shift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff2f, .hex);
pub const XKB_KEY_Eisu_toggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff30, .hex);
pub const XKB_KEY_Kanji_Bangou = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff37, .hex);
pub const XKB_KEY_Zen_Koho = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3d, .hex);
pub const XKB_KEY_Mae_Koho = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3e, .hex);
pub const XKB_KEY_Home = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff50, .hex);
pub const XKB_KEY_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff51, .hex);
pub const XKB_KEY_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff52, .hex);
pub const XKB_KEY_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff53, .hex);
pub const XKB_KEY_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff54, .hex);
pub const XKB_KEY_Prior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff55, .hex);
pub const XKB_KEY_Page_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff55, .hex);
pub const XKB_KEY_Next = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff56, .hex);
pub const XKB_KEY_Page_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff56, .hex);
pub const XKB_KEY_End = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff57, .hex);
pub const XKB_KEY_Begin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff58, .hex);
pub const XKB_KEY_Select = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff60, .hex);
pub const XKB_KEY_Print = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff61, .hex);
pub const XKB_KEY_Execute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff62, .hex);
pub const XKB_KEY_Insert = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff63, .hex);
pub const XKB_KEY_Undo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff65, .hex);
pub const XKB_KEY_Redo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff66, .hex);
pub const XKB_KEY_Menu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff67, .hex);
pub const XKB_KEY_Find = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff68, .hex);
pub const XKB_KEY_Cancel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff69, .hex);
pub const XKB_KEY_Help = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff6a, .hex);
pub const XKB_KEY_Break = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff6b, .hex);
pub const XKB_KEY_Mode_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_script_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_Num_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7f, .hex);
pub const XKB_KEY_KP_Space = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff80, .hex);
pub const XKB_KEY_KP_Tab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff89, .hex);
pub const XKB_KEY_KP_Enter = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff8d, .hex);
pub const XKB_KEY_KP_F1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff91, .hex);
pub const XKB_KEY_KP_F2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff92, .hex);
pub const XKB_KEY_KP_F3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff93, .hex);
pub const XKB_KEY_KP_F4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff94, .hex);
pub const XKB_KEY_KP_Home = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff95, .hex);
pub const XKB_KEY_KP_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff96, .hex);
pub const XKB_KEY_KP_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff97, .hex);
pub const XKB_KEY_KP_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff98, .hex);
pub const XKB_KEY_KP_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff99, .hex);
pub const XKB_KEY_KP_Prior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9a, .hex);
pub const XKB_KEY_KP_Page_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9a, .hex);
pub const XKB_KEY_KP_Next = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9b, .hex);
pub const XKB_KEY_KP_Page_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9b, .hex);
pub const XKB_KEY_KP_End = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9c, .hex);
pub const XKB_KEY_KP_Begin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9d, .hex);
pub const XKB_KEY_KP_Insert = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9e, .hex);
pub const XKB_KEY_KP_Delete = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff9f, .hex);
pub const XKB_KEY_KP_Equal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffbd, .hex);
pub const XKB_KEY_KP_Multiply = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffaa, .hex);
pub const XKB_KEY_KP_Add = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffab, .hex);
pub const XKB_KEY_KP_Separator = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffac, .hex);
pub const XKB_KEY_KP_Subtract = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffad, .hex);
pub const XKB_KEY_KP_Decimal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffae, .hex);
pub const XKB_KEY_KP_Divide = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffaf, .hex);
pub const XKB_KEY_KP_0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb0, .hex);
pub const XKB_KEY_KP_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb1, .hex);
pub const XKB_KEY_KP_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb2, .hex);
pub const XKB_KEY_KP_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb3, .hex);
pub const XKB_KEY_KP_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb4, .hex);
pub const XKB_KEY_KP_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb5, .hex);
pub const XKB_KEY_KP_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb6, .hex);
pub const XKB_KEY_KP_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb7, .hex);
pub const XKB_KEY_KP_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb8, .hex);
pub const XKB_KEY_KP_9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffb9, .hex);
pub const XKB_KEY_F1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffbe, .hex);
pub const XKB_KEY_F2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffbf, .hex);
pub const XKB_KEY_F3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc0, .hex);
pub const XKB_KEY_F4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc1, .hex);
pub const XKB_KEY_F5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc2, .hex);
pub const XKB_KEY_F6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc3, .hex);
pub const XKB_KEY_F7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc4, .hex);
pub const XKB_KEY_F8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc5, .hex);
pub const XKB_KEY_F9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc6, .hex);
pub const XKB_KEY_F10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc7, .hex);
pub const XKB_KEY_F11 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc8, .hex);
pub const XKB_KEY_L1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc8, .hex);
pub const XKB_KEY_F12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc9, .hex);
pub const XKB_KEY_L2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffc9, .hex);
pub const XKB_KEY_F13 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffca, .hex);
pub const XKB_KEY_L3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffca, .hex);
pub const XKB_KEY_F14 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcb, .hex);
pub const XKB_KEY_L4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcb, .hex);
pub const XKB_KEY_F15 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcc, .hex);
pub const XKB_KEY_L5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcc, .hex);
pub const XKB_KEY_F16 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcd, .hex);
pub const XKB_KEY_L6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcd, .hex);
pub const XKB_KEY_F17 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffce, .hex);
pub const XKB_KEY_L7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffce, .hex);
pub const XKB_KEY_F18 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcf, .hex);
pub const XKB_KEY_L8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffcf, .hex);
pub const XKB_KEY_F19 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd0, .hex);
pub const XKB_KEY_L9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd0, .hex);
pub const XKB_KEY_F20 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd1, .hex);
pub const XKB_KEY_L10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd1, .hex);
pub const XKB_KEY_F21 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd2, .hex);
pub const XKB_KEY_R1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd2, .hex);
pub const XKB_KEY_F22 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd3, .hex);
pub const XKB_KEY_R2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd3, .hex);
pub const XKB_KEY_F23 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd4, .hex);
pub const XKB_KEY_R3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd4, .hex);
pub const XKB_KEY_F24 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd5, .hex);
pub const XKB_KEY_R4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd5, .hex);
pub const XKB_KEY_F25 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd6, .hex);
pub const XKB_KEY_R5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd6, .hex);
pub const XKB_KEY_F26 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd7, .hex);
pub const XKB_KEY_R6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd7, .hex);
pub const XKB_KEY_F27 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd8, .hex);
pub const XKB_KEY_R7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd8, .hex);
pub const XKB_KEY_F28 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd9, .hex);
pub const XKB_KEY_R8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffd9, .hex);
pub const XKB_KEY_F29 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffda, .hex);
pub const XKB_KEY_R9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffda, .hex);
pub const XKB_KEY_F30 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdb, .hex);
pub const XKB_KEY_R10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdb, .hex);
pub const XKB_KEY_F31 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdc, .hex);
pub const XKB_KEY_R11 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdc, .hex);
pub const XKB_KEY_F32 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdd, .hex);
pub const XKB_KEY_R12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdd, .hex);
pub const XKB_KEY_F33 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffde, .hex);
pub const XKB_KEY_R13 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffde, .hex);
pub const XKB_KEY_F34 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdf, .hex);
pub const XKB_KEY_R14 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffdf, .hex);
pub const XKB_KEY_F35 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe0, .hex);
pub const XKB_KEY_R15 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe0, .hex);
pub const XKB_KEY_Shift_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe1, .hex);
pub const XKB_KEY_Shift_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe2, .hex);
pub const XKB_KEY_Control_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe3, .hex);
pub const XKB_KEY_Control_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe4, .hex);
pub const XKB_KEY_Caps_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe5, .hex);
pub const XKB_KEY_Shift_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe6, .hex);
pub const XKB_KEY_Meta_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe7, .hex);
pub const XKB_KEY_Meta_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe8, .hex);
pub const XKB_KEY_Alt_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffe9, .hex);
pub const XKB_KEY_Alt_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffea, .hex);
pub const XKB_KEY_Super_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffeb, .hex);
pub const XKB_KEY_Super_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffec, .hex);
pub const XKB_KEY_Hyper_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffed, .hex);
pub const XKB_KEY_Hyper_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffee, .hex);
pub const XKB_KEY_ISO_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe01, .hex);
pub const XKB_KEY_ISO_Level2_Latch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe02, .hex);
pub const XKB_KEY_ISO_Level3_Shift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe03, .hex);
pub const XKB_KEY_ISO_Level3_Latch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe04, .hex);
pub const XKB_KEY_ISO_Level3_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe05, .hex);
pub const XKB_KEY_ISO_Level5_Shift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe11, .hex);
pub const XKB_KEY_ISO_Level5_Latch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe12, .hex);
pub const XKB_KEY_ISO_Level5_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe13, .hex);
pub const XKB_KEY_ISO_Group_Shift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_ISO_Group_Latch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe06, .hex);
pub const XKB_KEY_ISO_Group_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe07, .hex);
pub const XKB_KEY_ISO_Next_Group = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe08, .hex);
pub const XKB_KEY_ISO_Next_Group_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe09, .hex);
pub const XKB_KEY_ISO_Prev_Group = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0a, .hex);
pub const XKB_KEY_ISO_Prev_Group_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0b, .hex);
pub const XKB_KEY_ISO_First_Group = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0c, .hex);
pub const XKB_KEY_ISO_First_Group_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0d, .hex);
pub const XKB_KEY_ISO_Last_Group = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0e, .hex);
pub const XKB_KEY_ISO_Last_Group_Lock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe0f, .hex);
pub const XKB_KEY_ISO_Left_Tab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe20, .hex);
pub const XKB_KEY_ISO_Move_Line_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe21, .hex);
pub const XKB_KEY_ISO_Move_Line_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe22, .hex);
pub const XKB_KEY_ISO_Partial_Line_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe23, .hex);
pub const XKB_KEY_ISO_Partial_Line_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe24, .hex);
pub const XKB_KEY_ISO_Partial_Space_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe25, .hex);
pub const XKB_KEY_ISO_Partial_Space_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe26, .hex);
pub const XKB_KEY_ISO_Set_Margin_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe27, .hex);
pub const XKB_KEY_ISO_Set_Margin_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe28, .hex);
pub const XKB_KEY_ISO_Release_Margin_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe29, .hex);
pub const XKB_KEY_ISO_Release_Margin_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2a, .hex);
pub const XKB_KEY_ISO_Release_Both_Margins = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2b, .hex);
pub const XKB_KEY_ISO_Fast_Cursor_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2c, .hex);
pub const XKB_KEY_ISO_Fast_Cursor_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2d, .hex);
pub const XKB_KEY_ISO_Fast_Cursor_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2e, .hex);
pub const XKB_KEY_ISO_Fast_Cursor_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe2f, .hex);
pub const XKB_KEY_ISO_Continuous_Underline = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe30, .hex);
pub const XKB_KEY_ISO_Discontinuous_Underline = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe31, .hex);
pub const XKB_KEY_ISO_Emphasize = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe32, .hex);
pub const XKB_KEY_ISO_Center_Object = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe33, .hex);
pub const XKB_KEY_ISO_Enter = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe34, .hex);
pub const XKB_KEY_dead_grave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe50, .hex);
pub const XKB_KEY_dead_acute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe51, .hex);
pub const XKB_KEY_dead_circumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe52, .hex);
pub const XKB_KEY_dead_tilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe53, .hex);
pub const XKB_KEY_dead_perispomeni = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe53, .hex);
pub const XKB_KEY_dead_macron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe54, .hex);
pub const XKB_KEY_dead_breve = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe55, .hex);
pub const XKB_KEY_dead_abovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe56, .hex);
pub const XKB_KEY_dead_diaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe57, .hex);
pub const XKB_KEY_dead_abovering = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe58, .hex);
pub const XKB_KEY_dead_doubleacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe59, .hex);
pub const XKB_KEY_dead_caron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5a, .hex);
pub const XKB_KEY_dead_cedilla = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5b, .hex);
pub const XKB_KEY_dead_ogonek = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5c, .hex);
pub const XKB_KEY_dead_iota = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5d, .hex);
pub const XKB_KEY_dead_voiced_sound = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5e, .hex);
pub const XKB_KEY_dead_semivoiced_sound = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe5f, .hex);
pub const XKB_KEY_dead_belowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe60, .hex);
pub const XKB_KEY_dead_hook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe61, .hex);
pub const XKB_KEY_dead_horn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe62, .hex);
pub const XKB_KEY_dead_stroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe63, .hex);
pub const XKB_KEY_dead_abovecomma = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe64, .hex);
pub const XKB_KEY_dead_psili = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe64, .hex);
pub const XKB_KEY_dead_abovereversedcomma = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe65, .hex);
pub const XKB_KEY_dead_dasia = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe65, .hex);
pub const XKB_KEY_dead_doublegrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe66, .hex);
pub const XKB_KEY_dead_belowring = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe67, .hex);
pub const XKB_KEY_dead_belowmacron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe68, .hex);
pub const XKB_KEY_dead_belowcircumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe69, .hex);
pub const XKB_KEY_dead_belowtilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6a, .hex);
pub const XKB_KEY_dead_belowbreve = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6b, .hex);
pub const XKB_KEY_dead_belowdiaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6c, .hex);
pub const XKB_KEY_dead_invertedbreve = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6d, .hex);
pub const XKB_KEY_dead_belowcomma = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6e, .hex);
pub const XKB_KEY_dead_currency = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe6f, .hex);
pub const XKB_KEY_dead_lowline = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe90, .hex);
pub const XKB_KEY_dead_aboveverticalline = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe91, .hex);
pub const XKB_KEY_dead_belowverticalline = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe92, .hex);
pub const XKB_KEY_dead_longsolidusoverlay = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe93, .hex);
pub const XKB_KEY_dead_a = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe80, .hex);
pub const XKB_KEY_dead_A = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe81, .hex);
pub const XKB_KEY_dead_e = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe82, .hex);
pub const XKB_KEY_dead_E = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe83, .hex);
pub const XKB_KEY_dead_i = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe84, .hex);
pub const XKB_KEY_dead_I = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe85, .hex);
pub const XKB_KEY_dead_o = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe86, .hex);
pub const XKB_KEY_dead_O = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe87, .hex);
pub const XKB_KEY_dead_u = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe88, .hex);
pub const XKB_KEY_dead_U = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe89, .hex);
pub const XKB_KEY_dead_small_schwa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8a, .hex);
pub const XKB_KEY_dead_schwa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8a, .hex);
pub const XKB_KEY_dead_capital_schwa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8b, .hex);
pub const XKB_KEY_dead_SCHWA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8b, .hex);
pub const XKB_KEY_dead_greek = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8c, .hex);
pub const XKB_KEY_dead_hamza = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe8d, .hex);
pub const XKB_KEY_First_Virtual_Screen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfed0, .hex);
pub const XKB_KEY_Prev_Virtual_Screen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfed1, .hex);
pub const XKB_KEY_Next_Virtual_Screen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfed2, .hex);
pub const XKB_KEY_Last_Virtual_Screen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfed4, .hex);
pub const XKB_KEY_Terminate_Server = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfed5, .hex);
pub const XKB_KEY_AccessX_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe70, .hex);
pub const XKB_KEY_AccessX_Feedback_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe71, .hex);
pub const XKB_KEY_RepeatKeys_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe72, .hex);
pub const XKB_KEY_SlowKeys_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe73, .hex);
pub const XKB_KEY_BounceKeys_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe74, .hex);
pub const XKB_KEY_StickyKeys_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe75, .hex);
pub const XKB_KEY_MouseKeys_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe76, .hex);
pub const XKB_KEY_MouseKeys_Accel_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe77, .hex);
pub const XKB_KEY_Overlay1_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe78, .hex);
pub const XKB_KEY_Overlay2_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe79, .hex);
pub const XKB_KEY_AudibleBell_Enable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfe7a, .hex);
pub const XKB_KEY_Pointer_Left = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee0, .hex);
pub const XKB_KEY_Pointer_Right = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee1, .hex);
pub const XKB_KEY_Pointer_Up = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee2, .hex);
pub const XKB_KEY_Pointer_Down = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee3, .hex);
pub const XKB_KEY_Pointer_UpLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee4, .hex);
pub const XKB_KEY_Pointer_UpRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee5, .hex);
pub const XKB_KEY_Pointer_DownLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee6, .hex);
pub const XKB_KEY_Pointer_DownRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee7, .hex);
pub const XKB_KEY_Pointer_Button_Dflt = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee8, .hex);
pub const XKB_KEY_Pointer_Button1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfee9, .hex);
pub const XKB_KEY_Pointer_Button2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeea, .hex);
pub const XKB_KEY_Pointer_Button3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeeb, .hex);
pub const XKB_KEY_Pointer_Button4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeec, .hex);
pub const XKB_KEY_Pointer_Button5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeed, .hex);
pub const XKB_KEY_Pointer_DblClick_Dflt = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeee, .hex);
pub const XKB_KEY_Pointer_DblClick1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfeef, .hex);
pub const XKB_KEY_Pointer_DblClick2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef0, .hex);
pub const XKB_KEY_Pointer_DblClick3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef1, .hex);
pub const XKB_KEY_Pointer_DblClick4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef2, .hex);
pub const XKB_KEY_Pointer_DblClick5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef3, .hex);
pub const XKB_KEY_Pointer_Drag_Dflt = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef4, .hex);
pub const XKB_KEY_Pointer_Drag1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef5, .hex);
pub const XKB_KEY_Pointer_Drag2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef6, .hex);
pub const XKB_KEY_Pointer_Drag3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef7, .hex);
pub const XKB_KEY_Pointer_Drag4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef8, .hex);
pub const XKB_KEY_Pointer_Drag5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfefd, .hex);
pub const XKB_KEY_Pointer_EnableKeys = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfef9, .hex);
pub const XKB_KEY_Pointer_Accelerate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfefa, .hex);
pub const XKB_KEY_Pointer_DfltBtnNext = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfefb, .hex);
pub const XKB_KEY_Pointer_DfltBtnPrev = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfefc, .hex);
pub const XKB_KEY_ch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea0, .hex);
pub const XKB_KEY_Ch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea1, .hex);
pub const XKB_KEY_CH = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea2, .hex);
pub const XKB_KEY_c_h = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea3, .hex);
pub const XKB_KEY_C_h = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea4, .hex);
pub const XKB_KEY_C_H = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfea5, .hex);
pub const XKB_KEY_3270_Duplicate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd01, .hex);
pub const XKB_KEY_3270_FieldMark = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd02, .hex);
pub const XKB_KEY_3270_Right2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd03, .hex);
pub const XKB_KEY_3270_Left2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd04, .hex);
pub const XKB_KEY_3270_BackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd05, .hex);
pub const XKB_KEY_3270_EraseEOF = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd06, .hex);
pub const XKB_KEY_3270_EraseInput = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd07, .hex);
pub const XKB_KEY_3270_Reset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd08, .hex);
pub const XKB_KEY_3270_Quit = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd09, .hex);
pub const XKB_KEY_3270_PA1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0a, .hex);
pub const XKB_KEY_3270_PA2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0b, .hex);
pub const XKB_KEY_3270_PA3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0c, .hex);
pub const XKB_KEY_3270_Test = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0d, .hex);
pub const XKB_KEY_3270_Attn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0e, .hex);
pub const XKB_KEY_3270_CursorBlink = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd0f, .hex);
pub const XKB_KEY_3270_AltCursor = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd10, .hex);
pub const XKB_KEY_3270_KeyClick = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd11, .hex);
pub const XKB_KEY_3270_Jump = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd12, .hex);
pub const XKB_KEY_3270_Ident = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd13, .hex);
pub const XKB_KEY_3270_Rule = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd14, .hex);
pub const XKB_KEY_3270_Copy = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd15, .hex);
pub const XKB_KEY_3270_Play = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd16, .hex);
pub const XKB_KEY_3270_Setup = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd17, .hex);
pub const XKB_KEY_3270_Record = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd18, .hex);
pub const XKB_KEY_3270_ChangeScreen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd19, .hex);
pub const XKB_KEY_3270_DeleteWord = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd1a, .hex);
pub const XKB_KEY_3270_ExSelect = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd1b, .hex);
pub const XKB_KEY_3270_CursorSelect = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd1c, .hex);
pub const XKB_KEY_3270_PrintScreen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd1d, .hex);
pub const XKB_KEY_3270_Enter = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfd1e, .hex);
pub const XKB_KEY_space = @as(c_int, 0x0020);
pub const XKB_KEY_exclam = @as(c_int, 0x0021);
pub const XKB_KEY_quotedbl = @as(c_int, 0x0022);
pub const XKB_KEY_numbersign = @as(c_int, 0x0023);
pub const XKB_KEY_dollar = @as(c_int, 0x0024);
pub const XKB_KEY_percent = @as(c_int, 0x0025);
pub const XKB_KEY_ampersand = @as(c_int, 0x0026);
pub const XKB_KEY_apostrophe = @as(c_int, 0x0027);
pub const XKB_KEY_quoteright = @as(c_int, 0x0027);
pub const XKB_KEY_parenleft = @as(c_int, 0x0028);
pub const XKB_KEY_parenright = @as(c_int, 0x0029);
pub const XKB_KEY_asterisk = @as(c_int, 0x002a);
pub const XKB_KEY_plus = @as(c_int, 0x002b);
pub const XKB_KEY_comma = @as(c_int, 0x002c);
pub const XKB_KEY_minus = @as(c_int, 0x002d);
pub const XKB_KEY_period = @as(c_int, 0x002e);
pub const XKB_KEY_slash = @as(c_int, 0x002f);
pub const XKB_KEY_0 = @as(c_int, 0x0030);
pub const XKB_KEY_1 = @as(c_int, 0x0031);
pub const XKB_KEY_2 = @as(c_int, 0x0032);
pub const XKB_KEY_3 = @as(c_int, 0x0033);
pub const XKB_KEY_4 = @as(c_int, 0x0034);
pub const XKB_KEY_5 = @as(c_int, 0x0035);
pub const XKB_KEY_6 = @as(c_int, 0x0036);
pub const XKB_KEY_7 = @as(c_int, 0x0037);
pub const XKB_KEY_8 = @as(c_int, 0x0038);
pub const XKB_KEY_9 = @as(c_int, 0x0039);
pub const XKB_KEY_colon = @as(c_int, 0x003a);
pub const XKB_KEY_semicolon = @as(c_int, 0x003b);
pub const XKB_KEY_less = @as(c_int, 0x003c);
pub const XKB_KEY_equal = @as(c_int, 0x003d);
pub const XKB_KEY_greater = @as(c_int, 0x003e);
pub const XKB_KEY_question = @as(c_int, 0x003f);
pub const XKB_KEY_at = @as(c_int, 0x0040);
pub const XKB_KEY_A = @as(c_int, 0x0041);
pub const XKB_KEY_B = @as(c_int, 0x0042);
pub const XKB_KEY_C = @as(c_int, 0x0043);
pub const XKB_KEY_D = @as(c_int, 0x0044);
pub const XKB_KEY_E = @as(c_int, 0x0045);
pub const XKB_KEY_F = @as(c_int, 0x0046);
pub const XKB_KEY_G = @as(c_int, 0x0047);
pub const XKB_KEY_H = @as(c_int, 0x0048);
pub const XKB_KEY_I = @as(c_int, 0x0049);
pub const XKB_KEY_J = @as(c_int, 0x004a);
pub const XKB_KEY_K = @as(c_int, 0x004b);
pub const XKB_KEY_L = @as(c_int, 0x004c);
pub const XKB_KEY_M = @as(c_int, 0x004d);
pub const XKB_KEY_N = @as(c_int, 0x004e);
pub const XKB_KEY_O = @as(c_int, 0x004f);
pub const XKB_KEY_P = @as(c_int, 0x0050);
pub const XKB_KEY_Q = @as(c_int, 0x0051);
pub const XKB_KEY_R = @as(c_int, 0x0052);
pub const XKB_KEY_S = @as(c_int, 0x0053);
pub const XKB_KEY_T = @as(c_int, 0x0054);
pub const XKB_KEY_U = @as(c_int, 0x0055);
pub const XKB_KEY_V = @as(c_int, 0x0056);
pub const XKB_KEY_W = @as(c_int, 0x0057);
pub const XKB_KEY_X = @as(c_int, 0x0058);
pub const XKB_KEY_Y = @as(c_int, 0x0059);
pub const XKB_KEY_Z = @as(c_int, 0x005a);
pub const XKB_KEY_bracketleft = @as(c_int, 0x005b);
pub const XKB_KEY_backslash = @as(c_int, 0x005c);
pub const XKB_KEY_bracketright = @as(c_int, 0x005d);
pub const XKB_KEY_asciicircum = @as(c_int, 0x005e);
pub const XKB_KEY_underscore = @as(c_int, 0x005f);
pub const XKB_KEY_grave = @as(c_int, 0x0060);
pub const XKB_KEY_quoteleft = @as(c_int, 0x0060);
pub const XKB_KEY_a = @as(c_int, 0x0061);
pub const XKB_KEY_b = @as(c_int, 0x0062);
pub const XKB_KEY_c = @as(c_int, 0x0063);
pub const XKB_KEY_d = @as(c_int, 0x0064);
pub const XKB_KEY_e = @as(c_int, 0x0065);
pub const XKB_KEY_f = @as(c_int, 0x0066);
pub const XKB_KEY_g = @as(c_int, 0x0067);
pub const XKB_KEY_h = @as(c_int, 0x0068);
pub const XKB_KEY_i = @as(c_int, 0x0069);
pub const XKB_KEY_j = @as(c_int, 0x006a);
pub const XKB_KEY_k = @as(c_int, 0x006b);
pub const XKB_KEY_l = @as(c_int, 0x006c);
pub const XKB_KEY_m = @as(c_int, 0x006d);
pub const XKB_KEY_n = @as(c_int, 0x006e);
pub const XKB_KEY_o = @as(c_int, 0x006f);
pub const XKB_KEY_p = @as(c_int, 0x0070);
pub const XKB_KEY_q = @as(c_int, 0x0071);
pub const XKB_KEY_r = @as(c_int, 0x0072);
pub const XKB_KEY_s = @as(c_int, 0x0073);
pub const XKB_KEY_t = @as(c_int, 0x0074);
pub const XKB_KEY_u = @as(c_int, 0x0075);
pub const XKB_KEY_v = @as(c_int, 0x0076);
pub const XKB_KEY_w = @as(c_int, 0x0077);
pub const XKB_KEY_x = @as(c_int, 0x0078);
pub const XKB_KEY_y = @as(c_int, 0x0079);
pub const XKB_KEY_z = @as(c_int, 0x007a);
pub const XKB_KEY_braceleft = @as(c_int, 0x007b);
pub const XKB_KEY_bar = @as(c_int, 0x007c);
pub const XKB_KEY_braceright = @as(c_int, 0x007d);
pub const XKB_KEY_asciitilde = @as(c_int, 0x007e);
pub const XKB_KEY_nobreakspace = @as(c_int, 0x00a0);
pub const XKB_KEY_exclamdown = @as(c_int, 0x00a1);
pub const XKB_KEY_cent = @as(c_int, 0x00a2);
pub const XKB_KEY_sterling = @as(c_int, 0x00a3);
pub const XKB_KEY_currency = @as(c_int, 0x00a4);
pub const XKB_KEY_yen = @as(c_int, 0x00a5);
pub const XKB_KEY_brokenbar = @as(c_int, 0x00a6);
pub const XKB_KEY_section = @as(c_int, 0x00a7);
pub const XKB_KEY_diaeresis = @as(c_int, 0x00a8);
pub const XKB_KEY_copyright = @as(c_int, 0x00a9);
pub const XKB_KEY_ordfeminine = @as(c_int, 0x00aa);
pub const XKB_KEY_guillemotleft = @as(c_int, 0x00ab);
pub const XKB_KEY_guillemetleft = @as(c_int, 0x00ab);
pub const XKB_KEY_notsign = @as(c_int, 0x00ac);
pub const XKB_KEY_hyphen = @as(c_int, 0x00ad);
pub const XKB_KEY_registered = @as(c_int, 0x00ae);
pub const XKB_KEY_macron = @as(c_int, 0x00af);
pub const XKB_KEY_degree = @as(c_int, 0x00b0);
pub const XKB_KEY_plusminus = @as(c_int, 0x00b1);
pub const XKB_KEY_twosuperior = @as(c_int, 0x00b2);
pub const XKB_KEY_threesuperior = @as(c_int, 0x00b3);
pub const XKB_KEY_acute = @as(c_int, 0x00b4);
pub const XKB_KEY_mu = @as(c_int, 0x00b5);
pub const XKB_KEY_paragraph = @as(c_int, 0x00b6);
pub const XKB_KEY_periodcentered = @as(c_int, 0x00b7);
pub const XKB_KEY_cedilla = @as(c_int, 0x00b8);
pub const XKB_KEY_onesuperior = @as(c_int, 0x00b9);
pub const XKB_KEY_masculine = @as(c_int, 0x00ba);
pub const XKB_KEY_ordmasculine = @as(c_int, 0x00ba);
pub const XKB_KEY_guillemotright = @as(c_int, 0x00bb);
pub const XKB_KEY_guillemetright = @as(c_int, 0x00bb);
pub const XKB_KEY_onequarter = @as(c_int, 0x00bc);
pub const XKB_KEY_onehalf = @as(c_int, 0x00bd);
pub const XKB_KEY_threequarters = @as(c_int, 0x00be);
pub const XKB_KEY_questiondown = @as(c_int, 0x00bf);
pub const XKB_KEY_Agrave = @as(c_int, 0x00c0);
pub const XKB_KEY_Aacute = @as(c_int, 0x00c1);
pub const XKB_KEY_Acircumflex = @as(c_int, 0x00c2);
pub const XKB_KEY_Atilde = @as(c_int, 0x00c3);
pub const XKB_KEY_Adiaeresis = @as(c_int, 0x00c4);
pub const XKB_KEY_Aring = @as(c_int, 0x00c5);
pub const XKB_KEY_AE = @as(c_int, 0x00c6);
pub const XKB_KEY_Ccedilla = @as(c_int, 0x00c7);
pub const XKB_KEY_Egrave = @as(c_int, 0x00c8);
pub const XKB_KEY_Eacute = @as(c_int, 0x00c9);
pub const XKB_KEY_Ecircumflex = @as(c_int, 0x00ca);
pub const XKB_KEY_Ediaeresis = @as(c_int, 0x00cb);
pub const XKB_KEY_Igrave = @as(c_int, 0x00cc);
pub const XKB_KEY_Iacute = @as(c_int, 0x00cd);
pub const XKB_KEY_Icircumflex = @as(c_int, 0x00ce);
pub const XKB_KEY_Idiaeresis = @as(c_int, 0x00cf);
pub const XKB_KEY_ETH = @as(c_int, 0x00d0);
pub const XKB_KEY_Eth = @as(c_int, 0x00d0);
pub const XKB_KEY_Ntilde = @as(c_int, 0x00d1);
pub const XKB_KEY_Ograve = @as(c_int, 0x00d2);
pub const XKB_KEY_Oacute = @as(c_int, 0x00d3);
pub const XKB_KEY_Ocircumflex = @as(c_int, 0x00d4);
pub const XKB_KEY_Otilde = @as(c_int, 0x00d5);
pub const XKB_KEY_Odiaeresis = @as(c_int, 0x00d6);
pub const XKB_KEY_multiply = @as(c_int, 0x00d7);
pub const XKB_KEY_Oslash = @as(c_int, 0x00d8);
pub const XKB_KEY_Ooblique = @as(c_int, 0x00d8);
pub const XKB_KEY_Ugrave = @as(c_int, 0x00d9);
pub const XKB_KEY_Uacute = @as(c_int, 0x00da);
pub const XKB_KEY_Ucircumflex = @as(c_int, 0x00db);
pub const XKB_KEY_Udiaeresis = @as(c_int, 0x00dc);
pub const XKB_KEY_Yacute = @as(c_int, 0x00dd);
pub const XKB_KEY_THORN = @as(c_int, 0x00de);
pub const XKB_KEY_Thorn = @as(c_int, 0x00de);
pub const XKB_KEY_ssharp = @as(c_int, 0x00df);
pub const XKB_KEY_agrave = @as(c_int, 0x00e0);
pub const XKB_KEY_aacute = @as(c_int, 0x00e1);
pub const XKB_KEY_acircumflex = @as(c_int, 0x00e2);
pub const XKB_KEY_atilde = @as(c_int, 0x00e3);
pub const XKB_KEY_adiaeresis = @as(c_int, 0x00e4);
pub const XKB_KEY_aring = @as(c_int, 0x00e5);
pub const XKB_KEY_ae = @as(c_int, 0x00e6);
pub const XKB_KEY_ccedilla = @as(c_int, 0x00e7);
pub const XKB_KEY_egrave = @as(c_int, 0x00e8);
pub const XKB_KEY_eacute = @as(c_int, 0x00e9);
pub const XKB_KEY_ecircumflex = @as(c_int, 0x00ea);
pub const XKB_KEY_ediaeresis = @as(c_int, 0x00eb);
pub const XKB_KEY_igrave = @as(c_int, 0x00ec);
pub const XKB_KEY_iacute = @as(c_int, 0x00ed);
pub const XKB_KEY_icircumflex = @as(c_int, 0x00ee);
pub const XKB_KEY_idiaeresis = @as(c_int, 0x00ef);
pub const XKB_KEY_eth = @as(c_int, 0x00f0);
pub const XKB_KEY_ntilde = @as(c_int, 0x00f1);
pub const XKB_KEY_ograve = @as(c_int, 0x00f2);
pub const XKB_KEY_oacute = @as(c_int, 0x00f3);
pub const XKB_KEY_ocircumflex = @as(c_int, 0x00f4);
pub const XKB_KEY_otilde = @as(c_int, 0x00f5);
pub const XKB_KEY_odiaeresis = @as(c_int, 0x00f6);
pub const XKB_KEY_division = @as(c_int, 0x00f7);
pub const XKB_KEY_oslash = @as(c_int, 0x00f8);
pub const XKB_KEY_ooblique = @as(c_int, 0x00f8);
pub const XKB_KEY_ugrave = @as(c_int, 0x00f9);
pub const XKB_KEY_uacute = @as(c_int, 0x00fa);
pub const XKB_KEY_ucircumflex = @as(c_int, 0x00fb);
pub const XKB_KEY_udiaeresis = @as(c_int, 0x00fc);
pub const XKB_KEY_yacute = @as(c_int, 0x00fd);
pub const XKB_KEY_thorn = @as(c_int, 0x00fe);
pub const XKB_KEY_ydiaeresis = @as(c_int, 0x00ff);
pub const XKB_KEY_Aogonek = @as(c_int, 0x01a1);
pub const XKB_KEY_breve = @as(c_int, 0x01a2);
pub const XKB_KEY_Lstroke = @as(c_int, 0x01a3);
pub const XKB_KEY_Lcaron = @as(c_int, 0x01a5);
pub const XKB_KEY_Sacute = @as(c_int, 0x01a6);
pub const XKB_KEY_Scaron = @as(c_int, 0x01a9);
pub const XKB_KEY_Scedilla = @as(c_int, 0x01aa);
pub const XKB_KEY_Tcaron = @as(c_int, 0x01ab);
pub const XKB_KEY_Zacute = @as(c_int, 0x01ac);
pub const XKB_KEY_Zcaron = @as(c_int, 0x01ae);
pub const XKB_KEY_Zabovedot = @as(c_int, 0x01af);
pub const XKB_KEY_aogonek = @as(c_int, 0x01b1);
pub const XKB_KEY_ogonek = @as(c_int, 0x01b2);
pub const XKB_KEY_lstroke = @as(c_int, 0x01b3);
pub const XKB_KEY_lcaron = @as(c_int, 0x01b5);
pub const XKB_KEY_sacute = @as(c_int, 0x01b6);
pub const XKB_KEY_caron = @as(c_int, 0x01b7);
pub const XKB_KEY_scaron = @as(c_int, 0x01b9);
pub const XKB_KEY_scedilla = @as(c_int, 0x01ba);
pub const XKB_KEY_tcaron = @as(c_int, 0x01bb);
pub const XKB_KEY_zacute = @as(c_int, 0x01bc);
pub const XKB_KEY_doubleacute = @as(c_int, 0x01bd);
pub const XKB_KEY_zcaron = @as(c_int, 0x01be);
pub const XKB_KEY_zabovedot = @as(c_int, 0x01bf);
pub const XKB_KEY_Racute = @as(c_int, 0x01c0);
pub const XKB_KEY_Abreve = @as(c_int, 0x01c3);
pub const XKB_KEY_Lacute = @as(c_int, 0x01c5);
pub const XKB_KEY_Cacute = @as(c_int, 0x01c6);
pub const XKB_KEY_Ccaron = @as(c_int, 0x01c8);
pub const XKB_KEY_Eogonek = @as(c_int, 0x01ca);
pub const XKB_KEY_Ecaron = @as(c_int, 0x01cc);
pub const XKB_KEY_Dcaron = @as(c_int, 0x01cf);
pub const XKB_KEY_Dstroke = @as(c_int, 0x01d0);
pub const XKB_KEY_Nacute = @as(c_int, 0x01d1);
pub const XKB_KEY_Ncaron = @as(c_int, 0x01d2);
pub const XKB_KEY_Odoubleacute = @as(c_int, 0x01d5);
pub const XKB_KEY_Rcaron = @as(c_int, 0x01d8);
pub const XKB_KEY_Uring = @as(c_int, 0x01d9);
pub const XKB_KEY_Udoubleacute = @as(c_int, 0x01db);
pub const XKB_KEY_Tcedilla = @as(c_int, 0x01de);
pub const XKB_KEY_racute = @as(c_int, 0x01e0);
pub const XKB_KEY_abreve = @as(c_int, 0x01e3);
pub const XKB_KEY_lacute = @as(c_int, 0x01e5);
pub const XKB_KEY_cacute = @as(c_int, 0x01e6);
pub const XKB_KEY_ccaron = @as(c_int, 0x01e8);
pub const XKB_KEY_eogonek = @as(c_int, 0x01ea);
pub const XKB_KEY_ecaron = @as(c_int, 0x01ec);
pub const XKB_KEY_dcaron = @as(c_int, 0x01ef);
pub const XKB_KEY_dstroke = @as(c_int, 0x01f0);
pub const XKB_KEY_nacute = @as(c_int, 0x01f1);
pub const XKB_KEY_ncaron = @as(c_int, 0x01f2);
pub const XKB_KEY_odoubleacute = @as(c_int, 0x01f5);
pub const XKB_KEY_rcaron = @as(c_int, 0x01f8);
pub const XKB_KEY_uring = @as(c_int, 0x01f9);
pub const XKB_KEY_udoubleacute = @as(c_int, 0x01fb);
pub const XKB_KEY_tcedilla = @as(c_int, 0x01fe);
pub const XKB_KEY_abovedot = @as(c_int, 0x01ff);
pub const XKB_KEY_Hstroke = @as(c_int, 0x02a1);
pub const XKB_KEY_Hcircumflex = @as(c_int, 0x02a6);
pub const XKB_KEY_Iabovedot = @as(c_int, 0x02a9);
pub const XKB_KEY_Gbreve = @as(c_int, 0x02ab);
pub const XKB_KEY_Jcircumflex = @as(c_int, 0x02ac);
pub const XKB_KEY_hstroke = @as(c_int, 0x02b1);
pub const XKB_KEY_hcircumflex = @as(c_int, 0x02b6);
pub const XKB_KEY_idotless = @as(c_int, 0x02b9);
pub const XKB_KEY_gbreve = @as(c_int, 0x02bb);
pub const XKB_KEY_jcircumflex = @as(c_int, 0x02bc);
pub const XKB_KEY_Cabovedot = @as(c_int, 0x02c5);
pub const XKB_KEY_Ccircumflex = @as(c_int, 0x02c6);
pub const XKB_KEY_Gabovedot = @as(c_int, 0x02d5);
pub const XKB_KEY_Gcircumflex = @as(c_int, 0x02d8);
pub const XKB_KEY_Ubreve = @as(c_int, 0x02dd);
pub const XKB_KEY_Scircumflex = @as(c_int, 0x02de);
pub const XKB_KEY_cabovedot = @as(c_int, 0x02e5);
pub const XKB_KEY_ccircumflex = @as(c_int, 0x02e6);
pub const XKB_KEY_gabovedot = @as(c_int, 0x02f5);
pub const XKB_KEY_gcircumflex = @as(c_int, 0x02f8);
pub const XKB_KEY_ubreve = @as(c_int, 0x02fd);
pub const XKB_KEY_scircumflex = @as(c_int, 0x02fe);
pub const XKB_KEY_kra = @as(c_int, 0x03a2);
pub const XKB_KEY_kappa = @as(c_int, 0x03a2);
pub const XKB_KEY_Rcedilla = @as(c_int, 0x03a3);
pub const XKB_KEY_Itilde = @as(c_int, 0x03a5);
pub const XKB_KEY_Lcedilla = @as(c_int, 0x03a6);
pub const XKB_KEY_Emacron = @as(c_int, 0x03aa);
pub const XKB_KEY_Gcedilla = @as(c_int, 0x03ab);
pub const XKB_KEY_Tslash = @as(c_int, 0x03ac);
pub const XKB_KEY_rcedilla = @as(c_int, 0x03b3);
pub const XKB_KEY_itilde = @as(c_int, 0x03b5);
pub const XKB_KEY_lcedilla = @as(c_int, 0x03b6);
pub const XKB_KEY_emacron = @as(c_int, 0x03ba);
pub const XKB_KEY_gcedilla = @as(c_int, 0x03bb);
pub const XKB_KEY_tslash = @as(c_int, 0x03bc);
pub const XKB_KEY_ENG = @as(c_int, 0x03bd);
pub const XKB_KEY_eng = @as(c_int, 0x03bf);
pub const XKB_KEY_Amacron = @as(c_int, 0x03c0);
pub const XKB_KEY_Iogonek = @as(c_int, 0x03c7);
pub const XKB_KEY_Eabovedot = @as(c_int, 0x03cc);
pub const XKB_KEY_Imacron = @as(c_int, 0x03cf);
pub const XKB_KEY_Ncedilla = @as(c_int, 0x03d1);
pub const XKB_KEY_Omacron = @as(c_int, 0x03d2);
pub const XKB_KEY_Kcedilla = @as(c_int, 0x03d3);
pub const XKB_KEY_Uogonek = @as(c_int, 0x03d9);
pub const XKB_KEY_Utilde = @as(c_int, 0x03dd);
pub const XKB_KEY_Umacron = @as(c_int, 0x03de);
pub const XKB_KEY_amacron = @as(c_int, 0x03e0);
pub const XKB_KEY_iogonek = @as(c_int, 0x03e7);
pub const XKB_KEY_eabovedot = @as(c_int, 0x03ec);
pub const XKB_KEY_imacron = @as(c_int, 0x03ef);
pub const XKB_KEY_ncedilla = @as(c_int, 0x03f1);
pub const XKB_KEY_omacron = @as(c_int, 0x03f2);
pub const XKB_KEY_kcedilla = @as(c_int, 0x03f3);
pub const XKB_KEY_uogonek = @as(c_int, 0x03f9);
pub const XKB_KEY_utilde = @as(c_int, 0x03fd);
pub const XKB_KEY_umacron = @as(c_int, 0x03fe);
pub const XKB_KEY_Wcircumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000174, .hex);
pub const XKB_KEY_wcircumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000175, .hex);
pub const XKB_KEY_Ycircumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000176, .hex);
pub const XKB_KEY_ycircumflex = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000177, .hex);
pub const XKB_KEY_Babovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e02, .hex);
pub const XKB_KEY_babovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e03, .hex);
pub const XKB_KEY_Dabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e0a, .hex);
pub const XKB_KEY_dabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e0b, .hex);
pub const XKB_KEY_Fabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e1e, .hex);
pub const XKB_KEY_fabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e1f, .hex);
pub const XKB_KEY_Mabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e40, .hex);
pub const XKB_KEY_mabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e41, .hex);
pub const XKB_KEY_Pabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e56, .hex);
pub const XKB_KEY_pabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e57, .hex);
pub const XKB_KEY_Sabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e60, .hex);
pub const XKB_KEY_sabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e61, .hex);
pub const XKB_KEY_Tabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e6a, .hex);
pub const XKB_KEY_tabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e6b, .hex);
pub const XKB_KEY_Wgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e80, .hex);
pub const XKB_KEY_wgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e81, .hex);
pub const XKB_KEY_Wacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e82, .hex);
pub const XKB_KEY_wacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e83, .hex);
pub const XKB_KEY_Wdiaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e84, .hex);
pub const XKB_KEY_wdiaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e85, .hex);
pub const XKB_KEY_Ygrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef2, .hex);
pub const XKB_KEY_ygrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef3, .hex);
pub const XKB_KEY_OE = @as(c_int, 0x13bc);
pub const XKB_KEY_oe = @as(c_int, 0x13bd);
pub const XKB_KEY_Ydiaeresis = @as(c_int, 0x13be);
pub const XKB_KEY_overline = @as(c_int, 0x047e);
pub const XKB_KEY_kana_fullstop = @as(c_int, 0x04a1);
pub const XKB_KEY_kana_openingbracket = @as(c_int, 0x04a2);
pub const XKB_KEY_kana_closingbracket = @as(c_int, 0x04a3);
pub const XKB_KEY_kana_comma = @as(c_int, 0x04a4);
pub const XKB_KEY_kana_conjunctive = @as(c_int, 0x04a5);
pub const XKB_KEY_kana_middledot = @as(c_int, 0x04a5);
pub const XKB_KEY_kana_WO = @as(c_int, 0x04a6);
pub const XKB_KEY_kana_a = @as(c_int, 0x04a7);
pub const XKB_KEY_kana_i = @as(c_int, 0x04a8);
pub const XKB_KEY_kana_u = @as(c_int, 0x04a9);
pub const XKB_KEY_kana_e = @as(c_int, 0x04aa);
pub const XKB_KEY_kana_o = @as(c_int, 0x04ab);
pub const XKB_KEY_kana_ya = @as(c_int, 0x04ac);
pub const XKB_KEY_kana_yu = @as(c_int, 0x04ad);
pub const XKB_KEY_kana_yo = @as(c_int, 0x04ae);
pub const XKB_KEY_kana_tsu = @as(c_int, 0x04af);
pub const XKB_KEY_kana_tu = @as(c_int, 0x04af);
pub const XKB_KEY_prolongedsound = @as(c_int, 0x04b0);
pub const XKB_KEY_kana_A = @as(c_int, 0x04b1);
pub const XKB_KEY_kana_I = @as(c_int, 0x04b2);
pub const XKB_KEY_kana_U = @as(c_int, 0x04b3);
pub const XKB_KEY_kana_E = @as(c_int, 0x04b4);
pub const XKB_KEY_kana_O = @as(c_int, 0x04b5);
pub const XKB_KEY_kana_KA = @as(c_int, 0x04b6);
pub const XKB_KEY_kana_KI = @as(c_int, 0x04b7);
pub const XKB_KEY_kana_KU = @as(c_int, 0x04b8);
pub const XKB_KEY_kana_KE = @as(c_int, 0x04b9);
pub const XKB_KEY_kana_KO = @as(c_int, 0x04ba);
pub const XKB_KEY_kana_SA = @as(c_int, 0x04bb);
pub const XKB_KEY_kana_SHI = @as(c_int, 0x04bc);
pub const XKB_KEY_kana_SU = @as(c_int, 0x04bd);
pub const XKB_KEY_kana_SE = @as(c_int, 0x04be);
pub const XKB_KEY_kana_SO = @as(c_int, 0x04bf);
pub const XKB_KEY_kana_TA = @as(c_int, 0x04c0);
pub const XKB_KEY_kana_CHI = @as(c_int, 0x04c1);
pub const XKB_KEY_kana_TI = @as(c_int, 0x04c1);
pub const XKB_KEY_kana_TSU = @as(c_int, 0x04c2);
pub const XKB_KEY_kana_TU = @as(c_int, 0x04c2);
pub const XKB_KEY_kana_TE = @as(c_int, 0x04c3);
pub const XKB_KEY_kana_TO = @as(c_int, 0x04c4);
pub const XKB_KEY_kana_NA = @as(c_int, 0x04c5);
pub const XKB_KEY_kana_NI = @as(c_int, 0x04c6);
pub const XKB_KEY_kana_NU = @as(c_int, 0x04c7);
pub const XKB_KEY_kana_NE = @as(c_int, 0x04c8);
pub const XKB_KEY_kana_NO = @as(c_int, 0x04c9);
pub const XKB_KEY_kana_HA = @as(c_int, 0x04ca);
pub const XKB_KEY_kana_HI = @as(c_int, 0x04cb);
pub const XKB_KEY_kana_FU = @as(c_int, 0x04cc);
pub const XKB_KEY_kana_HU = @as(c_int, 0x04cc);
pub const XKB_KEY_kana_HE = @as(c_int, 0x04cd);
pub const XKB_KEY_kana_HO = @as(c_int, 0x04ce);
pub const XKB_KEY_kana_MA = @as(c_int, 0x04cf);
pub const XKB_KEY_kana_MI = @as(c_int, 0x04d0);
pub const XKB_KEY_kana_MU = @as(c_int, 0x04d1);
pub const XKB_KEY_kana_ME = @as(c_int, 0x04d2);
pub const XKB_KEY_kana_MO = @as(c_int, 0x04d3);
pub const XKB_KEY_kana_YA = @as(c_int, 0x04d4);
pub const XKB_KEY_kana_YU = @as(c_int, 0x04d5);
pub const XKB_KEY_kana_YO = @as(c_int, 0x04d6);
pub const XKB_KEY_kana_RA = @as(c_int, 0x04d7);
pub const XKB_KEY_kana_RI = @as(c_int, 0x04d8);
pub const XKB_KEY_kana_RU = @as(c_int, 0x04d9);
pub const XKB_KEY_kana_RE = @as(c_int, 0x04da);
pub const XKB_KEY_kana_RO = @as(c_int, 0x04db);
pub const XKB_KEY_kana_WA = @as(c_int, 0x04dc);
pub const XKB_KEY_kana_N = @as(c_int, 0x04dd);
pub const XKB_KEY_voicedsound = @as(c_int, 0x04de);
pub const XKB_KEY_semivoicedsound = @as(c_int, 0x04df);
pub const XKB_KEY_kana_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_Farsi_0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f0, .hex);
pub const XKB_KEY_Farsi_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f1, .hex);
pub const XKB_KEY_Farsi_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f2, .hex);
pub const XKB_KEY_Farsi_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f3, .hex);
pub const XKB_KEY_Farsi_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f4, .hex);
pub const XKB_KEY_Farsi_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f5, .hex);
pub const XKB_KEY_Farsi_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f6, .hex);
pub const XKB_KEY_Farsi_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f7, .hex);
pub const XKB_KEY_Farsi_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f8, .hex);
pub const XKB_KEY_Farsi_9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006f9, .hex);
pub const XKB_KEY_Arabic_percent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100066a, .hex);
pub const XKB_KEY_Arabic_superscript_alef = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000670, .hex);
pub const XKB_KEY_Arabic_tteh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000679, .hex);
pub const XKB_KEY_Arabic_peh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100067e, .hex);
pub const XKB_KEY_Arabic_tcheh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000686, .hex);
pub const XKB_KEY_Arabic_ddal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000688, .hex);
pub const XKB_KEY_Arabic_rreh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000691, .hex);
pub const XKB_KEY_Arabic_comma = @as(c_int, 0x05ac);
pub const XKB_KEY_Arabic_fullstop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006d4, .hex);
pub const XKB_KEY_Arabic_0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000660, .hex);
pub const XKB_KEY_Arabic_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000661, .hex);
pub const XKB_KEY_Arabic_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000662, .hex);
pub const XKB_KEY_Arabic_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000663, .hex);
pub const XKB_KEY_Arabic_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000664, .hex);
pub const XKB_KEY_Arabic_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000665, .hex);
pub const XKB_KEY_Arabic_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000666, .hex);
pub const XKB_KEY_Arabic_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000667, .hex);
pub const XKB_KEY_Arabic_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000668, .hex);
pub const XKB_KEY_Arabic_9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000669, .hex);
pub const XKB_KEY_Arabic_semicolon = @as(c_int, 0x05bb);
pub const XKB_KEY_Arabic_question_mark = @as(c_int, 0x05bf);
pub const XKB_KEY_Arabic_hamza = @as(c_int, 0x05c1);
pub const XKB_KEY_Arabic_maddaonalef = @as(c_int, 0x05c2);
pub const XKB_KEY_Arabic_hamzaonalef = @as(c_int, 0x05c3);
pub const XKB_KEY_Arabic_hamzaonwaw = @as(c_int, 0x05c4);
pub const XKB_KEY_Arabic_hamzaunderalef = @as(c_int, 0x05c5);
pub const XKB_KEY_Arabic_hamzaonyeh = @as(c_int, 0x05c6);
pub const XKB_KEY_Arabic_alef = @as(c_int, 0x05c7);
pub const XKB_KEY_Arabic_beh = @as(c_int, 0x05c8);
pub const XKB_KEY_Arabic_tehmarbuta = @as(c_int, 0x05c9);
pub const XKB_KEY_Arabic_teh = @as(c_int, 0x05ca);
pub const XKB_KEY_Arabic_theh = @as(c_int, 0x05cb);
pub const XKB_KEY_Arabic_jeem = @as(c_int, 0x05cc);
pub const XKB_KEY_Arabic_hah = @as(c_int, 0x05cd);
pub const XKB_KEY_Arabic_khah = @as(c_int, 0x05ce);
pub const XKB_KEY_Arabic_dal = @as(c_int, 0x05cf);
pub const XKB_KEY_Arabic_thal = @as(c_int, 0x05d0);
pub const XKB_KEY_Arabic_ra = @as(c_int, 0x05d1);
pub const XKB_KEY_Arabic_zain = @as(c_int, 0x05d2);
pub const XKB_KEY_Arabic_seen = @as(c_int, 0x05d3);
pub const XKB_KEY_Arabic_sheen = @as(c_int, 0x05d4);
pub const XKB_KEY_Arabic_sad = @as(c_int, 0x05d5);
pub const XKB_KEY_Arabic_dad = @as(c_int, 0x05d6);
pub const XKB_KEY_Arabic_tah = @as(c_int, 0x05d7);
pub const XKB_KEY_Arabic_zah = @as(c_int, 0x05d8);
pub const XKB_KEY_Arabic_ain = @as(c_int, 0x05d9);
pub const XKB_KEY_Arabic_ghain = @as(c_int, 0x05da);
pub const XKB_KEY_Arabic_tatweel = @as(c_int, 0x05e0);
pub const XKB_KEY_Arabic_feh = @as(c_int, 0x05e1);
pub const XKB_KEY_Arabic_qaf = @as(c_int, 0x05e2);
pub const XKB_KEY_Arabic_kaf = @as(c_int, 0x05e3);
pub const XKB_KEY_Arabic_lam = @as(c_int, 0x05e4);
pub const XKB_KEY_Arabic_meem = @as(c_int, 0x05e5);
pub const XKB_KEY_Arabic_noon = @as(c_int, 0x05e6);
pub const XKB_KEY_Arabic_ha = @as(c_int, 0x05e7);
pub const XKB_KEY_Arabic_heh = @as(c_int, 0x05e7);
pub const XKB_KEY_Arabic_waw = @as(c_int, 0x05e8);
pub const XKB_KEY_Arabic_alefmaksura = @as(c_int, 0x05e9);
pub const XKB_KEY_Arabic_yeh = @as(c_int, 0x05ea);
pub const XKB_KEY_Arabic_fathatan = @as(c_int, 0x05eb);
pub const XKB_KEY_Arabic_dammatan = @as(c_int, 0x05ec);
pub const XKB_KEY_Arabic_kasratan = @as(c_int, 0x05ed);
pub const XKB_KEY_Arabic_fatha = @as(c_int, 0x05ee);
pub const XKB_KEY_Arabic_damma = @as(c_int, 0x05ef);
pub const XKB_KEY_Arabic_kasra = @as(c_int, 0x05f0);
pub const XKB_KEY_Arabic_shadda = @as(c_int, 0x05f1);
pub const XKB_KEY_Arabic_sukun = @as(c_int, 0x05f2);
pub const XKB_KEY_Arabic_madda_above = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000653, .hex);
pub const XKB_KEY_Arabic_hamza_above = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000654, .hex);
pub const XKB_KEY_Arabic_hamza_below = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000655, .hex);
pub const XKB_KEY_Arabic_jeh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000698, .hex);
pub const XKB_KEY_Arabic_veh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006a4, .hex);
pub const XKB_KEY_Arabic_keheh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006a9, .hex);
pub const XKB_KEY_Arabic_gaf = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006af, .hex);
pub const XKB_KEY_Arabic_noon_ghunna = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006ba, .hex);
pub const XKB_KEY_Arabic_heh_doachashmee = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006be, .hex);
pub const XKB_KEY_Farsi_yeh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006cc, .hex);
pub const XKB_KEY_Arabic_farsi_yeh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006cc, .hex);
pub const XKB_KEY_Arabic_yeh_baree = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006d2, .hex);
pub const XKB_KEY_Arabic_heh_goal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10006c1, .hex);
pub const XKB_KEY_Arabic_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_Cyrillic_GHE_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000492, .hex);
pub const XKB_KEY_Cyrillic_ghe_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000493, .hex);
pub const XKB_KEY_Cyrillic_ZHE_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000496, .hex);
pub const XKB_KEY_Cyrillic_zhe_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000497, .hex);
pub const XKB_KEY_Cyrillic_KA_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100049a, .hex);
pub const XKB_KEY_Cyrillic_ka_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100049b, .hex);
pub const XKB_KEY_Cyrillic_KA_vertstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100049c, .hex);
pub const XKB_KEY_Cyrillic_ka_vertstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100049d, .hex);
pub const XKB_KEY_Cyrillic_EN_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004a2, .hex);
pub const XKB_KEY_Cyrillic_en_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004a3, .hex);
pub const XKB_KEY_Cyrillic_U_straight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004ae, .hex);
pub const XKB_KEY_Cyrillic_u_straight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004af, .hex);
pub const XKB_KEY_Cyrillic_U_straight_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b0, .hex);
pub const XKB_KEY_Cyrillic_u_straight_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b1, .hex);
pub const XKB_KEY_Cyrillic_HA_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b2, .hex);
pub const XKB_KEY_Cyrillic_ha_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b3, .hex);
pub const XKB_KEY_Cyrillic_CHE_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b6, .hex);
pub const XKB_KEY_Cyrillic_che_descender = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b7, .hex);
pub const XKB_KEY_Cyrillic_CHE_vertstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b8, .hex);
pub const XKB_KEY_Cyrillic_che_vertstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004b9, .hex);
pub const XKB_KEY_Cyrillic_SHHA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004ba, .hex);
pub const XKB_KEY_Cyrillic_shha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004bb, .hex);
pub const XKB_KEY_Cyrillic_SCHWA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004d8, .hex);
pub const XKB_KEY_Cyrillic_schwa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004d9, .hex);
pub const XKB_KEY_Cyrillic_I_macron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004e2, .hex);
pub const XKB_KEY_Cyrillic_i_macron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004e3, .hex);
pub const XKB_KEY_Cyrillic_O_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004e8, .hex);
pub const XKB_KEY_Cyrillic_o_bar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004e9, .hex);
pub const XKB_KEY_Cyrillic_U_macron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004ee, .hex);
pub const XKB_KEY_Cyrillic_u_macron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10004ef, .hex);
pub const XKB_KEY_Serbian_dje = @as(c_int, 0x06a1);
pub const XKB_KEY_Macedonia_gje = @as(c_int, 0x06a2);
pub const XKB_KEY_Cyrillic_io = @as(c_int, 0x06a3);
pub const XKB_KEY_Ukrainian_ie = @as(c_int, 0x06a4);
pub const XKB_KEY_Ukranian_je = @as(c_int, 0x06a4);
pub const XKB_KEY_Macedonia_dse = @as(c_int, 0x06a5);
pub const XKB_KEY_Ukrainian_i = @as(c_int, 0x06a6);
pub const XKB_KEY_Ukranian_i = @as(c_int, 0x06a6);
pub const XKB_KEY_Ukrainian_yi = @as(c_int, 0x06a7);
pub const XKB_KEY_Ukranian_yi = @as(c_int, 0x06a7);
pub const XKB_KEY_Cyrillic_je = @as(c_int, 0x06a8);
pub const XKB_KEY_Serbian_je = @as(c_int, 0x06a8);
pub const XKB_KEY_Cyrillic_lje = @as(c_int, 0x06a9);
pub const XKB_KEY_Serbian_lje = @as(c_int, 0x06a9);
pub const XKB_KEY_Cyrillic_nje = @as(c_int, 0x06aa);
pub const XKB_KEY_Serbian_nje = @as(c_int, 0x06aa);
pub const XKB_KEY_Serbian_tshe = @as(c_int, 0x06ab);
pub const XKB_KEY_Macedonia_kje = @as(c_int, 0x06ac);
pub const XKB_KEY_Ukrainian_ghe_with_upturn = @as(c_int, 0x06ad);
pub const XKB_KEY_Byelorussian_shortu = @as(c_int, 0x06ae);
pub const XKB_KEY_Cyrillic_dzhe = @as(c_int, 0x06af);
pub const XKB_KEY_Serbian_dze = @as(c_int, 0x06af);
pub const XKB_KEY_numerosign = @as(c_int, 0x06b0);
pub const XKB_KEY_Serbian_DJE = @as(c_int, 0x06b1);
pub const XKB_KEY_Macedonia_GJE = @as(c_int, 0x06b2);
pub const XKB_KEY_Cyrillic_IO = @as(c_int, 0x06b3);
pub const XKB_KEY_Ukrainian_IE = @as(c_int, 0x06b4);
pub const XKB_KEY_Ukranian_JE = @as(c_int, 0x06b4);
pub const XKB_KEY_Macedonia_DSE = @as(c_int, 0x06b5);
pub const XKB_KEY_Ukrainian_I = @as(c_int, 0x06b6);
pub const XKB_KEY_Ukranian_I = @as(c_int, 0x06b6);
pub const XKB_KEY_Ukrainian_YI = @as(c_int, 0x06b7);
pub const XKB_KEY_Ukranian_YI = @as(c_int, 0x06b7);
pub const XKB_KEY_Cyrillic_JE = @as(c_int, 0x06b8);
pub const XKB_KEY_Serbian_JE = @as(c_int, 0x06b8);
pub const XKB_KEY_Cyrillic_LJE = @as(c_int, 0x06b9);
pub const XKB_KEY_Serbian_LJE = @as(c_int, 0x06b9);
pub const XKB_KEY_Cyrillic_NJE = @as(c_int, 0x06ba);
pub const XKB_KEY_Serbian_NJE = @as(c_int, 0x06ba);
pub const XKB_KEY_Serbian_TSHE = @as(c_int, 0x06bb);
pub const XKB_KEY_Macedonia_KJE = @as(c_int, 0x06bc);
pub const XKB_KEY_Ukrainian_GHE_WITH_UPTURN = @as(c_int, 0x06bd);
pub const XKB_KEY_Byelorussian_SHORTU = @as(c_int, 0x06be);
pub const XKB_KEY_Cyrillic_DZHE = @as(c_int, 0x06bf);
pub const XKB_KEY_Serbian_DZE = @as(c_int, 0x06bf);
pub const XKB_KEY_Cyrillic_yu = @as(c_int, 0x06c0);
pub const XKB_KEY_Cyrillic_a = @as(c_int, 0x06c1);
pub const XKB_KEY_Cyrillic_be = @as(c_int, 0x06c2);
pub const XKB_KEY_Cyrillic_tse = @as(c_int, 0x06c3);
pub const XKB_KEY_Cyrillic_de = @as(c_int, 0x06c4);
pub const XKB_KEY_Cyrillic_ie = @as(c_int, 0x06c5);
pub const XKB_KEY_Cyrillic_ef = @as(c_int, 0x06c6);
pub const XKB_KEY_Cyrillic_ghe = @as(c_int, 0x06c7);
pub const XKB_KEY_Cyrillic_ha = @as(c_int, 0x06c8);
pub const XKB_KEY_Cyrillic_i = @as(c_int, 0x06c9);
pub const XKB_KEY_Cyrillic_shorti = @as(c_int, 0x06ca);
pub const XKB_KEY_Cyrillic_ka = @as(c_int, 0x06cb);
pub const XKB_KEY_Cyrillic_el = @as(c_int, 0x06cc);
pub const XKB_KEY_Cyrillic_em = @as(c_int, 0x06cd);
pub const XKB_KEY_Cyrillic_en = @as(c_int, 0x06ce);
pub const XKB_KEY_Cyrillic_o = @as(c_int, 0x06cf);
pub const XKB_KEY_Cyrillic_pe = @as(c_int, 0x06d0);
pub const XKB_KEY_Cyrillic_ya = @as(c_int, 0x06d1);
pub const XKB_KEY_Cyrillic_er = @as(c_int, 0x06d2);
pub const XKB_KEY_Cyrillic_es = @as(c_int, 0x06d3);
pub const XKB_KEY_Cyrillic_te = @as(c_int, 0x06d4);
pub const XKB_KEY_Cyrillic_u = @as(c_int, 0x06d5);
pub const XKB_KEY_Cyrillic_zhe = @as(c_int, 0x06d6);
pub const XKB_KEY_Cyrillic_ve = @as(c_int, 0x06d7);
pub const XKB_KEY_Cyrillic_softsign = @as(c_int, 0x06d8);
pub const XKB_KEY_Cyrillic_yeru = @as(c_int, 0x06d9);
pub const XKB_KEY_Cyrillic_ze = @as(c_int, 0x06da);
pub const XKB_KEY_Cyrillic_sha = @as(c_int, 0x06db);
pub const XKB_KEY_Cyrillic_e = @as(c_int, 0x06dc);
pub const XKB_KEY_Cyrillic_shcha = @as(c_int, 0x06dd);
pub const XKB_KEY_Cyrillic_che = @as(c_int, 0x06de);
pub const XKB_KEY_Cyrillic_hardsign = @as(c_int, 0x06df);
pub const XKB_KEY_Cyrillic_YU = @as(c_int, 0x06e0);
pub const XKB_KEY_Cyrillic_A = @as(c_int, 0x06e1);
pub const XKB_KEY_Cyrillic_BE = @as(c_int, 0x06e2);
pub const XKB_KEY_Cyrillic_TSE = @as(c_int, 0x06e3);
pub const XKB_KEY_Cyrillic_DE = @as(c_int, 0x06e4);
pub const XKB_KEY_Cyrillic_IE = @as(c_int, 0x06e5);
pub const XKB_KEY_Cyrillic_EF = @as(c_int, 0x06e6);
pub const XKB_KEY_Cyrillic_GHE = @as(c_int, 0x06e7);
pub const XKB_KEY_Cyrillic_HA = @as(c_int, 0x06e8);
pub const XKB_KEY_Cyrillic_I = @as(c_int, 0x06e9);
pub const XKB_KEY_Cyrillic_SHORTI = @as(c_int, 0x06ea);
pub const XKB_KEY_Cyrillic_KA = @as(c_int, 0x06eb);
pub const XKB_KEY_Cyrillic_EL = @as(c_int, 0x06ec);
pub const XKB_KEY_Cyrillic_EM = @as(c_int, 0x06ed);
pub const XKB_KEY_Cyrillic_EN = @as(c_int, 0x06ee);
pub const XKB_KEY_Cyrillic_O = @as(c_int, 0x06ef);
pub const XKB_KEY_Cyrillic_PE = @as(c_int, 0x06f0);
pub const XKB_KEY_Cyrillic_YA = @as(c_int, 0x06f1);
pub const XKB_KEY_Cyrillic_ER = @as(c_int, 0x06f2);
pub const XKB_KEY_Cyrillic_ES = @as(c_int, 0x06f3);
pub const XKB_KEY_Cyrillic_TE = @as(c_int, 0x06f4);
pub const XKB_KEY_Cyrillic_U = @as(c_int, 0x06f5);
pub const XKB_KEY_Cyrillic_ZHE = @as(c_int, 0x06f6);
pub const XKB_KEY_Cyrillic_VE = @as(c_int, 0x06f7);
pub const XKB_KEY_Cyrillic_SOFTSIGN = @as(c_int, 0x06f8);
pub const XKB_KEY_Cyrillic_YERU = @as(c_int, 0x06f9);
pub const XKB_KEY_Cyrillic_ZE = @as(c_int, 0x06fa);
pub const XKB_KEY_Cyrillic_SHA = @as(c_int, 0x06fb);
pub const XKB_KEY_Cyrillic_E = @as(c_int, 0x06fc);
pub const XKB_KEY_Cyrillic_SHCHA = @as(c_int, 0x06fd);
pub const XKB_KEY_Cyrillic_CHE = @as(c_int, 0x06fe);
pub const XKB_KEY_Cyrillic_HARDSIGN = @as(c_int, 0x06ff);
pub const XKB_KEY_Greek_ALPHAaccent = @as(c_int, 0x07a1);
pub const XKB_KEY_Greek_EPSILONaccent = @as(c_int, 0x07a2);
pub const XKB_KEY_Greek_ETAaccent = @as(c_int, 0x07a3);
pub const XKB_KEY_Greek_IOTAaccent = @as(c_int, 0x07a4);
pub const XKB_KEY_Greek_IOTAdieresis = @as(c_int, 0x07a5);
pub const XKB_KEY_Greek_IOTAdiaeresis = @as(c_int, 0x07a5);
pub const XKB_KEY_Greek_OMICRONaccent = @as(c_int, 0x07a7);
pub const XKB_KEY_Greek_UPSILONaccent = @as(c_int, 0x07a8);
pub const XKB_KEY_Greek_UPSILONdieresis = @as(c_int, 0x07a9);
pub const XKB_KEY_Greek_OMEGAaccent = @as(c_int, 0x07ab);
pub const XKB_KEY_Greek_accentdieresis = @as(c_int, 0x07ae);
pub const XKB_KEY_Greek_horizbar = @as(c_int, 0x07af);
pub const XKB_KEY_Greek_alphaaccent = @as(c_int, 0x07b1);
pub const XKB_KEY_Greek_epsilonaccent = @as(c_int, 0x07b2);
pub const XKB_KEY_Greek_etaaccent = @as(c_int, 0x07b3);
pub const XKB_KEY_Greek_iotaaccent = @as(c_int, 0x07b4);
pub const XKB_KEY_Greek_iotadieresis = @as(c_int, 0x07b5);
pub const XKB_KEY_Greek_iotaaccentdieresis = @as(c_int, 0x07b6);
pub const XKB_KEY_Greek_omicronaccent = @as(c_int, 0x07b7);
pub const XKB_KEY_Greek_upsilonaccent = @as(c_int, 0x07b8);
pub const XKB_KEY_Greek_upsilondieresis = @as(c_int, 0x07b9);
pub const XKB_KEY_Greek_upsilonaccentdieresis = @as(c_int, 0x07ba);
pub const XKB_KEY_Greek_omegaaccent = @as(c_int, 0x07bb);
pub const XKB_KEY_Greek_ALPHA = @as(c_int, 0x07c1);
pub const XKB_KEY_Greek_BETA = @as(c_int, 0x07c2);
pub const XKB_KEY_Greek_GAMMA = @as(c_int, 0x07c3);
pub const XKB_KEY_Greek_DELTA = @as(c_int, 0x07c4);
pub const XKB_KEY_Greek_EPSILON = @as(c_int, 0x07c5);
pub const XKB_KEY_Greek_ZETA = @as(c_int, 0x07c6);
pub const XKB_KEY_Greek_ETA = @as(c_int, 0x07c7);
pub const XKB_KEY_Greek_THETA = @as(c_int, 0x07c8);
pub const XKB_KEY_Greek_IOTA = @as(c_int, 0x07c9);
pub const XKB_KEY_Greek_KAPPA = @as(c_int, 0x07ca);
pub const XKB_KEY_Greek_LAMDA = @as(c_int, 0x07cb);
pub const XKB_KEY_Greek_LAMBDA = @as(c_int, 0x07cb);
pub const XKB_KEY_Greek_MU = @as(c_int, 0x07cc);
pub const XKB_KEY_Greek_NU = @as(c_int, 0x07cd);
pub const XKB_KEY_Greek_XI = @as(c_int, 0x07ce);
pub const XKB_KEY_Greek_OMICRON = @as(c_int, 0x07cf);
pub const XKB_KEY_Greek_PI = @as(c_int, 0x07d0);
pub const XKB_KEY_Greek_RHO = @as(c_int, 0x07d1);
pub const XKB_KEY_Greek_SIGMA = @as(c_int, 0x07d2);
pub const XKB_KEY_Greek_TAU = @as(c_int, 0x07d4);
pub const XKB_KEY_Greek_UPSILON = @as(c_int, 0x07d5);
pub const XKB_KEY_Greek_PHI = @as(c_int, 0x07d6);
pub const XKB_KEY_Greek_CHI = @as(c_int, 0x07d7);
pub const XKB_KEY_Greek_PSI = @as(c_int, 0x07d8);
pub const XKB_KEY_Greek_OMEGA = @as(c_int, 0x07d9);
pub const XKB_KEY_Greek_alpha = @as(c_int, 0x07e1);
pub const XKB_KEY_Greek_beta = @as(c_int, 0x07e2);
pub const XKB_KEY_Greek_gamma = @as(c_int, 0x07e3);
pub const XKB_KEY_Greek_delta = @as(c_int, 0x07e4);
pub const XKB_KEY_Greek_epsilon = @as(c_int, 0x07e5);
pub const XKB_KEY_Greek_zeta = @as(c_int, 0x07e6);
pub const XKB_KEY_Greek_eta = @as(c_int, 0x07e7);
pub const XKB_KEY_Greek_theta = @as(c_int, 0x07e8);
pub const XKB_KEY_Greek_iota = @as(c_int, 0x07e9);
pub const XKB_KEY_Greek_kappa = @as(c_int, 0x07ea);
pub const XKB_KEY_Greek_lamda = @as(c_int, 0x07eb);
pub const XKB_KEY_Greek_lambda = @as(c_int, 0x07eb);
pub const XKB_KEY_Greek_mu = @as(c_int, 0x07ec);
pub const XKB_KEY_Greek_nu = @as(c_int, 0x07ed);
pub const XKB_KEY_Greek_xi = @as(c_int, 0x07ee);
pub const XKB_KEY_Greek_omicron = @as(c_int, 0x07ef);
pub const XKB_KEY_Greek_pi = @as(c_int, 0x07f0);
pub const XKB_KEY_Greek_rho = @as(c_int, 0x07f1);
pub const XKB_KEY_Greek_sigma = @as(c_int, 0x07f2);
pub const XKB_KEY_Greek_finalsmallsigma = @as(c_int, 0x07f3);
pub const XKB_KEY_Greek_tau = @as(c_int, 0x07f4);
pub const XKB_KEY_Greek_upsilon = @as(c_int, 0x07f5);
pub const XKB_KEY_Greek_phi = @as(c_int, 0x07f6);
pub const XKB_KEY_Greek_chi = @as(c_int, 0x07f7);
pub const XKB_KEY_Greek_psi = @as(c_int, 0x07f8);
pub const XKB_KEY_Greek_omega = @as(c_int, 0x07f9);
pub const XKB_KEY_Greek_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_leftradical = @as(c_int, 0x08a1);
pub const XKB_KEY_topleftradical = @as(c_int, 0x08a2);
pub const XKB_KEY_horizconnector = @as(c_int, 0x08a3);
pub const XKB_KEY_topintegral = @as(c_int, 0x08a4);
pub const XKB_KEY_botintegral = @as(c_int, 0x08a5);
pub const XKB_KEY_vertconnector = @as(c_int, 0x08a6);
pub const XKB_KEY_topleftsqbracket = @as(c_int, 0x08a7);
pub const XKB_KEY_botleftsqbracket = @as(c_int, 0x08a8);
pub const XKB_KEY_toprightsqbracket = @as(c_int, 0x08a9);
pub const XKB_KEY_botrightsqbracket = @as(c_int, 0x08aa);
pub const XKB_KEY_topleftparens = @as(c_int, 0x08ab);
pub const XKB_KEY_botleftparens = @as(c_int, 0x08ac);
pub const XKB_KEY_toprightparens = @as(c_int, 0x08ad);
pub const XKB_KEY_botrightparens = @as(c_int, 0x08ae);
pub const XKB_KEY_leftmiddlecurlybrace = @as(c_int, 0x08af);
pub const XKB_KEY_rightmiddlecurlybrace = @as(c_int, 0x08b0);
pub const XKB_KEY_topleftsummation = @as(c_int, 0x08b1);
pub const XKB_KEY_botleftsummation = @as(c_int, 0x08b2);
pub const XKB_KEY_topvertsummationconnector = @as(c_int, 0x08b3);
pub const XKB_KEY_botvertsummationconnector = @as(c_int, 0x08b4);
pub const XKB_KEY_toprightsummation = @as(c_int, 0x08b5);
pub const XKB_KEY_botrightsummation = @as(c_int, 0x08b6);
pub const XKB_KEY_rightmiddlesummation = @as(c_int, 0x08b7);
pub const XKB_KEY_lessthanequal = @as(c_int, 0x08bc);
pub const XKB_KEY_notequal = @as(c_int, 0x08bd);
pub const XKB_KEY_greaterthanequal = @as(c_int, 0x08be);
pub const XKB_KEY_integral = @as(c_int, 0x08bf);
pub const XKB_KEY_therefore = @as(c_int, 0x08c0);
pub const XKB_KEY_variation = @as(c_int, 0x08c1);
pub const XKB_KEY_infinity = @as(c_int, 0x08c2);
pub const XKB_KEY_nabla = @as(c_int, 0x08c5);
pub const XKB_KEY_approximate = @as(c_int, 0x08c8);
pub const XKB_KEY_similarequal = @as(c_int, 0x08c9);
pub const XKB_KEY_ifonlyif = @as(c_int, 0x08cd);
pub const XKB_KEY_implies = @as(c_int, 0x08ce);
pub const XKB_KEY_identical = @as(c_int, 0x08cf);
pub const XKB_KEY_radical = @as(c_int, 0x08d6);
pub const XKB_KEY_includedin = @as(c_int, 0x08da);
pub const XKB_KEY_includes = @as(c_int, 0x08db);
pub const XKB_KEY_intersection = @as(c_int, 0x08dc);
pub const XKB_KEY_union = @as(c_int, 0x08dd);
pub const XKB_KEY_logicaland = @as(c_int, 0x08de);
pub const XKB_KEY_logicalor = @as(c_int, 0x08df);
pub const XKB_KEY_partialderivative = @as(c_int, 0x08ef);
pub const XKB_KEY_function = @as(c_int, 0x08f6);
pub const XKB_KEY_leftarrow = @as(c_int, 0x08fb);
pub const XKB_KEY_uparrow = @as(c_int, 0x08fc);
pub const XKB_KEY_rightarrow = @as(c_int, 0x08fd);
pub const XKB_KEY_downarrow = @as(c_int, 0x08fe);
pub const XKB_KEY_blank = @as(c_int, 0x09df);
pub const XKB_KEY_soliddiamond = @as(c_int, 0x09e0);
pub const XKB_KEY_checkerboard = @as(c_int, 0x09e1);
pub const XKB_KEY_ht = @as(c_int, 0x09e2);
pub const XKB_KEY_ff = @as(c_int, 0x09e3);
pub const XKB_KEY_cr = @as(c_int, 0x09e4);
pub const XKB_KEY_lf = @as(c_int, 0x09e5);
pub const XKB_KEY_nl = @as(c_int, 0x09e8);
pub const XKB_KEY_vt = @as(c_int, 0x09e9);
pub const XKB_KEY_lowrightcorner = @as(c_int, 0x09ea);
pub const XKB_KEY_uprightcorner = @as(c_int, 0x09eb);
pub const XKB_KEY_upleftcorner = @as(c_int, 0x09ec);
pub const XKB_KEY_lowleftcorner = @as(c_int, 0x09ed);
pub const XKB_KEY_crossinglines = @as(c_int, 0x09ee);
pub const XKB_KEY_horizlinescan1 = @as(c_int, 0x09ef);
pub const XKB_KEY_horizlinescan3 = @as(c_int, 0x09f0);
pub const XKB_KEY_horizlinescan5 = @as(c_int, 0x09f1);
pub const XKB_KEY_horizlinescan7 = @as(c_int, 0x09f2);
pub const XKB_KEY_horizlinescan9 = @as(c_int, 0x09f3);
pub const XKB_KEY_leftt = @as(c_int, 0x09f4);
pub const XKB_KEY_rightt = @as(c_int, 0x09f5);
pub const XKB_KEY_bott = @as(c_int, 0x09f6);
pub const XKB_KEY_topt = @as(c_int, 0x09f7);
pub const XKB_KEY_vertbar = @as(c_int, 0x09f8);
pub const XKB_KEY_emspace = @as(c_int, 0x0aa1);
pub const XKB_KEY_enspace = @as(c_int, 0x0aa2);
pub const XKB_KEY_em3space = @as(c_int, 0x0aa3);
pub const XKB_KEY_em4space = @as(c_int, 0x0aa4);
pub const XKB_KEY_digitspace = @as(c_int, 0x0aa5);
pub const XKB_KEY_punctspace = @as(c_int, 0x0aa6);
pub const XKB_KEY_thinspace = @as(c_int, 0x0aa7);
pub const XKB_KEY_hairspace = @as(c_int, 0x0aa8);
pub const XKB_KEY_emdash = @as(c_int, 0x0aa9);
pub const XKB_KEY_endash = @as(c_int, 0x0aaa);
pub const XKB_KEY_signifblank = @as(c_int, 0x0aac);
pub const XKB_KEY_ellipsis = @as(c_int, 0x0aae);
pub const XKB_KEY_doubbaselinedot = @as(c_int, 0x0aaf);
pub const XKB_KEY_onethird = @as(c_int, 0x0ab0);
pub const XKB_KEY_twothirds = @as(c_int, 0x0ab1);
pub const XKB_KEY_onefifth = @as(c_int, 0x0ab2);
pub const XKB_KEY_twofifths = @as(c_int, 0x0ab3);
pub const XKB_KEY_threefifths = @as(c_int, 0x0ab4);
pub const XKB_KEY_fourfifths = @as(c_int, 0x0ab5);
pub const XKB_KEY_onesixth = @as(c_int, 0x0ab6);
pub const XKB_KEY_fivesixths = @as(c_int, 0x0ab7);
pub const XKB_KEY_careof = @as(c_int, 0x0ab8);
pub const XKB_KEY_figdash = @as(c_int, 0x0abb);
pub const XKB_KEY_leftanglebracket = @as(c_int, 0x0abc);
pub const XKB_KEY_decimalpoint = @as(c_int, 0x0abd);
pub const XKB_KEY_rightanglebracket = @as(c_int, 0x0abe);
pub const XKB_KEY_marker = @as(c_int, 0x0abf);
pub const XKB_KEY_oneeighth = @as(c_int, 0x0ac3);
pub const XKB_KEY_threeeighths = @as(c_int, 0x0ac4);
pub const XKB_KEY_fiveeighths = @as(c_int, 0x0ac5);
pub const XKB_KEY_seveneighths = @as(c_int, 0x0ac6);
pub const XKB_KEY_trademark = @as(c_int, 0x0ac9);
pub const XKB_KEY_signaturemark = @as(c_int, 0x0aca);
pub const XKB_KEY_trademarkincircle = @as(c_int, 0x0acb);
pub const XKB_KEY_leftopentriangle = @as(c_int, 0x0acc);
pub const XKB_KEY_rightopentriangle = @as(c_int, 0x0acd);
pub const XKB_KEY_emopencircle = @as(c_int, 0x0ace);
pub const XKB_KEY_emopenrectangle = @as(c_int, 0x0acf);
pub const XKB_KEY_leftsinglequotemark = @as(c_int, 0x0ad0);
pub const XKB_KEY_rightsinglequotemark = @as(c_int, 0x0ad1);
pub const XKB_KEY_leftdoublequotemark = @as(c_int, 0x0ad2);
pub const XKB_KEY_rightdoublequotemark = @as(c_int, 0x0ad3);
pub const XKB_KEY_prescription = @as(c_int, 0x0ad4);
pub const XKB_KEY_permille = @as(c_int, 0x0ad5);
pub const XKB_KEY_minutes = @as(c_int, 0x0ad6);
pub const XKB_KEY_seconds = @as(c_int, 0x0ad7);
pub const XKB_KEY_latincross = @as(c_int, 0x0ad9);
pub const XKB_KEY_hexagram = @as(c_int, 0x0ada);
pub const XKB_KEY_filledrectbullet = @as(c_int, 0x0adb);
pub const XKB_KEY_filledlefttribullet = @as(c_int, 0x0adc);
pub const XKB_KEY_filledrighttribullet = @as(c_int, 0x0add);
pub const XKB_KEY_emfilledcircle = @as(c_int, 0x0ade);
pub const XKB_KEY_emfilledrect = @as(c_int, 0x0adf);
pub const XKB_KEY_enopencircbullet = @as(c_int, 0x0ae0);
pub const XKB_KEY_enopensquarebullet = @as(c_int, 0x0ae1);
pub const XKB_KEY_openrectbullet = @as(c_int, 0x0ae2);
pub const XKB_KEY_opentribulletup = @as(c_int, 0x0ae3);
pub const XKB_KEY_opentribulletdown = @as(c_int, 0x0ae4);
pub const XKB_KEY_openstar = @as(c_int, 0x0ae5);
pub const XKB_KEY_enfilledcircbullet = @as(c_int, 0x0ae6);
pub const XKB_KEY_enfilledsqbullet = @as(c_int, 0x0ae7);
pub const XKB_KEY_filledtribulletup = @as(c_int, 0x0ae8);
pub const XKB_KEY_filledtribulletdown = @as(c_int, 0x0ae9);
pub const XKB_KEY_leftpointer = @as(c_int, 0x0aea);
pub const XKB_KEY_rightpointer = @as(c_int, 0x0aeb);
pub const XKB_KEY_club = @as(c_int, 0x0aec);
pub const XKB_KEY_diamond = @as(c_int, 0x0aed);
pub const XKB_KEY_heart = @as(c_int, 0x0aee);
pub const XKB_KEY_maltesecross = @as(c_int, 0x0af0);
pub const XKB_KEY_dagger = @as(c_int, 0x0af1);
pub const XKB_KEY_doubledagger = @as(c_int, 0x0af2);
pub const XKB_KEY_checkmark = @as(c_int, 0x0af3);
pub const XKB_KEY_ballotcross = @as(c_int, 0x0af4);
pub const XKB_KEY_musicalsharp = @as(c_int, 0x0af5);
pub const XKB_KEY_musicalflat = @as(c_int, 0x0af6);
pub const XKB_KEY_malesymbol = @as(c_int, 0x0af7);
pub const XKB_KEY_femalesymbol = @as(c_int, 0x0af8);
pub const XKB_KEY_telephone = @as(c_int, 0x0af9);
pub const XKB_KEY_telephonerecorder = @as(c_int, 0x0afa);
pub const XKB_KEY_phonographcopyright = @as(c_int, 0x0afb);
pub const XKB_KEY_caret = @as(c_int, 0x0afc);
pub const XKB_KEY_singlelowquotemark = @as(c_int, 0x0afd);
pub const XKB_KEY_doublelowquotemark = @as(c_int, 0x0afe);
pub const XKB_KEY_cursor = @as(c_int, 0x0aff);
pub const XKB_KEY_leftcaret = @as(c_int, 0x0ba3);
pub const XKB_KEY_rightcaret = @as(c_int, 0x0ba6);
pub const XKB_KEY_downcaret = @as(c_int, 0x0ba8);
pub const XKB_KEY_upcaret = @as(c_int, 0x0ba9);
pub const XKB_KEY_overbar = @as(c_int, 0x0bc0);
pub const XKB_KEY_downtack = @as(c_int, 0x0bc2);
pub const XKB_KEY_upshoe = @as(c_int, 0x0bc3);
pub const XKB_KEY_downstile = @as(c_int, 0x0bc4);
pub const XKB_KEY_underbar = @as(c_int, 0x0bc6);
pub const XKB_KEY_jot = @as(c_int, 0x0bca);
pub const XKB_KEY_quad = @as(c_int, 0x0bcc);
pub const XKB_KEY_uptack = @as(c_int, 0x0bce);
pub const XKB_KEY_circle = @as(c_int, 0x0bcf);
pub const XKB_KEY_upstile = @as(c_int, 0x0bd3);
pub const XKB_KEY_downshoe = @as(c_int, 0x0bd6);
pub const XKB_KEY_rightshoe = @as(c_int, 0x0bd8);
pub const XKB_KEY_leftshoe = @as(c_int, 0x0bda);
pub const XKB_KEY_lefttack = @as(c_int, 0x0bdc);
pub const XKB_KEY_righttack = @as(c_int, 0x0bfc);
pub const XKB_KEY_hebrew_doublelowline = @as(c_int, 0x0cdf);
pub const XKB_KEY_hebrew_aleph = @as(c_int, 0x0ce0);
pub const XKB_KEY_hebrew_bet = @as(c_int, 0x0ce1);
pub const XKB_KEY_hebrew_beth = @as(c_int, 0x0ce1);
pub const XKB_KEY_hebrew_gimel = @as(c_int, 0x0ce2);
pub const XKB_KEY_hebrew_gimmel = @as(c_int, 0x0ce2);
pub const XKB_KEY_hebrew_dalet = @as(c_int, 0x0ce3);
pub const XKB_KEY_hebrew_daleth = @as(c_int, 0x0ce3);
pub const XKB_KEY_hebrew_he = @as(c_int, 0x0ce4);
pub const XKB_KEY_hebrew_waw = @as(c_int, 0x0ce5);
pub const XKB_KEY_hebrew_zain = @as(c_int, 0x0ce6);
pub const XKB_KEY_hebrew_zayin = @as(c_int, 0x0ce6);
pub const XKB_KEY_hebrew_chet = @as(c_int, 0x0ce7);
pub const XKB_KEY_hebrew_het = @as(c_int, 0x0ce7);
pub const XKB_KEY_hebrew_tet = @as(c_int, 0x0ce8);
pub const XKB_KEY_hebrew_teth = @as(c_int, 0x0ce8);
pub const XKB_KEY_hebrew_yod = @as(c_int, 0x0ce9);
pub const XKB_KEY_hebrew_finalkaph = @as(c_int, 0x0cea);
pub const XKB_KEY_hebrew_kaph = @as(c_int, 0x0ceb);
pub const XKB_KEY_hebrew_lamed = @as(c_int, 0x0cec);
pub const XKB_KEY_hebrew_finalmem = @as(c_int, 0x0ced);
pub const XKB_KEY_hebrew_mem = @as(c_int, 0x0cee);
pub const XKB_KEY_hebrew_finalnun = @as(c_int, 0x0cef);
pub const XKB_KEY_hebrew_nun = @as(c_int, 0x0cf0);
pub const XKB_KEY_hebrew_samech = @as(c_int, 0x0cf1);
pub const XKB_KEY_hebrew_samekh = @as(c_int, 0x0cf1);
pub const XKB_KEY_hebrew_ayin = @as(c_int, 0x0cf2);
pub const XKB_KEY_hebrew_finalpe = @as(c_int, 0x0cf3);
pub const XKB_KEY_hebrew_pe = @as(c_int, 0x0cf4);
pub const XKB_KEY_hebrew_finalzade = @as(c_int, 0x0cf5);
pub const XKB_KEY_hebrew_finalzadi = @as(c_int, 0x0cf5);
pub const XKB_KEY_hebrew_zade = @as(c_int, 0x0cf6);
pub const XKB_KEY_hebrew_zadi = @as(c_int, 0x0cf6);
pub const XKB_KEY_hebrew_qoph = @as(c_int, 0x0cf7);
pub const XKB_KEY_hebrew_kuf = @as(c_int, 0x0cf7);
pub const XKB_KEY_hebrew_resh = @as(c_int, 0x0cf8);
pub const XKB_KEY_hebrew_shin = @as(c_int, 0x0cf9);
pub const XKB_KEY_hebrew_taw = @as(c_int, 0x0cfa);
pub const XKB_KEY_hebrew_taf = @as(c_int, 0x0cfa);
pub const XKB_KEY_Hebrew_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_Thai_kokai = @as(c_int, 0x0da1);
pub const XKB_KEY_Thai_khokhai = @as(c_int, 0x0da2);
pub const XKB_KEY_Thai_khokhuat = @as(c_int, 0x0da3);
pub const XKB_KEY_Thai_khokhwai = @as(c_int, 0x0da4);
pub const XKB_KEY_Thai_khokhon = @as(c_int, 0x0da5);
pub const XKB_KEY_Thai_khorakhang = @as(c_int, 0x0da6);
pub const XKB_KEY_Thai_ngongu = @as(c_int, 0x0da7);
pub const XKB_KEY_Thai_chochan = @as(c_int, 0x0da8);
pub const XKB_KEY_Thai_choching = @as(c_int, 0x0da9);
pub const XKB_KEY_Thai_chochang = @as(c_int, 0x0daa);
pub const XKB_KEY_Thai_soso = @as(c_int, 0x0dab);
pub const XKB_KEY_Thai_chochoe = @as(c_int, 0x0dac);
pub const XKB_KEY_Thai_yoying = @as(c_int, 0x0dad);
pub const XKB_KEY_Thai_dochada = @as(c_int, 0x0dae);
pub const XKB_KEY_Thai_topatak = @as(c_int, 0x0daf);
pub const XKB_KEY_Thai_thothan = @as(c_int, 0x0db0);
pub const XKB_KEY_Thai_thonangmontho = @as(c_int, 0x0db1);
pub const XKB_KEY_Thai_thophuthao = @as(c_int, 0x0db2);
pub const XKB_KEY_Thai_nonen = @as(c_int, 0x0db3);
pub const XKB_KEY_Thai_dodek = @as(c_int, 0x0db4);
pub const XKB_KEY_Thai_totao = @as(c_int, 0x0db5);
pub const XKB_KEY_Thai_thothung = @as(c_int, 0x0db6);
pub const XKB_KEY_Thai_thothahan = @as(c_int, 0x0db7);
pub const XKB_KEY_Thai_thothong = @as(c_int, 0x0db8);
pub const XKB_KEY_Thai_nonu = @as(c_int, 0x0db9);
pub const XKB_KEY_Thai_bobaimai = @as(c_int, 0x0dba);
pub const XKB_KEY_Thai_popla = @as(c_int, 0x0dbb);
pub const XKB_KEY_Thai_phophung = @as(c_int, 0x0dbc);
pub const XKB_KEY_Thai_fofa = @as(c_int, 0x0dbd);
pub const XKB_KEY_Thai_phophan = @as(c_int, 0x0dbe);
pub const XKB_KEY_Thai_fofan = @as(c_int, 0x0dbf);
pub const XKB_KEY_Thai_phosamphao = @as(c_int, 0x0dc0);
pub const XKB_KEY_Thai_moma = @as(c_int, 0x0dc1);
pub const XKB_KEY_Thai_yoyak = @as(c_int, 0x0dc2);
pub const XKB_KEY_Thai_rorua = @as(c_int, 0x0dc3);
pub const XKB_KEY_Thai_ru = @as(c_int, 0x0dc4);
pub const XKB_KEY_Thai_loling = @as(c_int, 0x0dc5);
pub const XKB_KEY_Thai_lu = @as(c_int, 0x0dc6);
pub const XKB_KEY_Thai_wowaen = @as(c_int, 0x0dc7);
pub const XKB_KEY_Thai_sosala = @as(c_int, 0x0dc8);
pub const XKB_KEY_Thai_sorusi = @as(c_int, 0x0dc9);
pub const XKB_KEY_Thai_sosua = @as(c_int, 0x0dca);
pub const XKB_KEY_Thai_hohip = @as(c_int, 0x0dcb);
pub const XKB_KEY_Thai_lochula = @as(c_int, 0x0dcc);
pub const XKB_KEY_Thai_oang = @as(c_int, 0x0dcd);
pub const XKB_KEY_Thai_honokhuk = @as(c_int, 0x0dce);
pub const XKB_KEY_Thai_paiyannoi = @as(c_int, 0x0dcf);
pub const XKB_KEY_Thai_saraa = @as(c_int, 0x0dd0);
pub const XKB_KEY_Thai_maihanakat = @as(c_int, 0x0dd1);
pub const XKB_KEY_Thai_saraaa = @as(c_int, 0x0dd2);
pub const XKB_KEY_Thai_saraam = @as(c_int, 0x0dd3);
pub const XKB_KEY_Thai_sarai = @as(c_int, 0x0dd4);
pub const XKB_KEY_Thai_saraii = @as(c_int, 0x0dd5);
pub const XKB_KEY_Thai_saraue = @as(c_int, 0x0dd6);
pub const XKB_KEY_Thai_sarauee = @as(c_int, 0x0dd7);
pub const XKB_KEY_Thai_sarau = @as(c_int, 0x0dd8);
pub const XKB_KEY_Thai_sarauu = @as(c_int, 0x0dd9);
pub const XKB_KEY_Thai_phinthu = @as(c_int, 0x0dda);
pub const XKB_KEY_Thai_maihanakat_maitho = @as(c_int, 0x0dde);
pub const XKB_KEY_Thai_baht = @as(c_int, 0x0ddf);
pub const XKB_KEY_Thai_sarae = @as(c_int, 0x0de0);
pub const XKB_KEY_Thai_saraae = @as(c_int, 0x0de1);
pub const XKB_KEY_Thai_sarao = @as(c_int, 0x0de2);
pub const XKB_KEY_Thai_saraaimaimuan = @as(c_int, 0x0de3);
pub const XKB_KEY_Thai_saraaimaimalai = @as(c_int, 0x0de4);
pub const XKB_KEY_Thai_lakkhangyao = @as(c_int, 0x0de5);
pub const XKB_KEY_Thai_maiyamok = @as(c_int, 0x0de6);
pub const XKB_KEY_Thai_maitaikhu = @as(c_int, 0x0de7);
pub const XKB_KEY_Thai_maiek = @as(c_int, 0x0de8);
pub const XKB_KEY_Thai_maitho = @as(c_int, 0x0de9);
pub const XKB_KEY_Thai_maitri = @as(c_int, 0x0dea);
pub const XKB_KEY_Thai_maichattawa = @as(c_int, 0x0deb);
pub const XKB_KEY_Thai_thanthakhat = @as(c_int, 0x0dec);
pub const XKB_KEY_Thai_nikhahit = @as(c_int, 0x0ded);
pub const XKB_KEY_Thai_leksun = @as(c_int, 0x0df0);
pub const XKB_KEY_Thai_leknung = @as(c_int, 0x0df1);
pub const XKB_KEY_Thai_leksong = @as(c_int, 0x0df2);
pub const XKB_KEY_Thai_leksam = @as(c_int, 0x0df3);
pub const XKB_KEY_Thai_leksi = @as(c_int, 0x0df4);
pub const XKB_KEY_Thai_lekha = @as(c_int, 0x0df5);
pub const XKB_KEY_Thai_lekhok = @as(c_int, 0x0df6);
pub const XKB_KEY_Thai_lekchet = @as(c_int, 0x0df7);
pub const XKB_KEY_Thai_lekpaet = @as(c_int, 0x0df8);
pub const XKB_KEY_Thai_lekkao = @as(c_int, 0x0df9);
pub const XKB_KEY_Hangul = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff31, .hex);
pub const XKB_KEY_Hangul_Start = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff32, .hex);
pub const XKB_KEY_Hangul_End = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff33, .hex);
pub const XKB_KEY_Hangul_Hanja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff34, .hex);
pub const XKB_KEY_Hangul_Jamo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff35, .hex);
pub const XKB_KEY_Hangul_Romaja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff36, .hex);
pub const XKB_KEY_Hangul_Codeinput = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff37, .hex);
pub const XKB_KEY_Hangul_Jeonja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff38, .hex);
pub const XKB_KEY_Hangul_Banja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff39, .hex);
pub const XKB_KEY_Hangul_PreHanja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3a, .hex);
pub const XKB_KEY_Hangul_PostHanja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3b, .hex);
pub const XKB_KEY_Hangul_SingleCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3c, .hex);
pub const XKB_KEY_Hangul_MultipleCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3d, .hex);
pub const XKB_KEY_Hangul_PreviousCandidate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3e, .hex);
pub const XKB_KEY_Hangul_Special = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff3f, .hex);
pub const XKB_KEY_Hangul_switch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xff7e, .hex);
pub const XKB_KEY_Hangul_Kiyeog = @as(c_int, 0x0ea1);
pub const XKB_KEY_Hangul_SsangKiyeog = @as(c_int, 0x0ea2);
pub const XKB_KEY_Hangul_KiyeogSios = @as(c_int, 0x0ea3);
pub const XKB_KEY_Hangul_Nieun = @as(c_int, 0x0ea4);
pub const XKB_KEY_Hangul_NieunJieuj = @as(c_int, 0x0ea5);
pub const XKB_KEY_Hangul_NieunHieuh = @as(c_int, 0x0ea6);
pub const XKB_KEY_Hangul_Dikeud = @as(c_int, 0x0ea7);
pub const XKB_KEY_Hangul_SsangDikeud = @as(c_int, 0x0ea8);
pub const XKB_KEY_Hangul_Rieul = @as(c_int, 0x0ea9);
pub const XKB_KEY_Hangul_RieulKiyeog = @as(c_int, 0x0eaa);
pub const XKB_KEY_Hangul_RieulMieum = @as(c_int, 0x0eab);
pub const XKB_KEY_Hangul_RieulPieub = @as(c_int, 0x0eac);
pub const XKB_KEY_Hangul_RieulSios = @as(c_int, 0x0ead);
pub const XKB_KEY_Hangul_RieulTieut = @as(c_int, 0x0eae);
pub const XKB_KEY_Hangul_RieulPhieuf = @as(c_int, 0x0eaf);
pub const XKB_KEY_Hangul_RieulHieuh = @as(c_int, 0x0eb0);
pub const XKB_KEY_Hangul_Mieum = @as(c_int, 0x0eb1);
pub const XKB_KEY_Hangul_Pieub = @as(c_int, 0x0eb2);
pub const XKB_KEY_Hangul_SsangPieub = @as(c_int, 0x0eb3);
pub const XKB_KEY_Hangul_PieubSios = @as(c_int, 0x0eb4);
pub const XKB_KEY_Hangul_Sios = @as(c_int, 0x0eb5);
pub const XKB_KEY_Hangul_SsangSios = @as(c_int, 0x0eb6);
pub const XKB_KEY_Hangul_Ieung = @as(c_int, 0x0eb7);
pub const XKB_KEY_Hangul_Jieuj = @as(c_int, 0x0eb8);
pub const XKB_KEY_Hangul_SsangJieuj = @as(c_int, 0x0eb9);
pub const XKB_KEY_Hangul_Cieuc = @as(c_int, 0x0eba);
pub const XKB_KEY_Hangul_Khieuq = @as(c_int, 0x0ebb);
pub const XKB_KEY_Hangul_Tieut = @as(c_int, 0x0ebc);
pub const XKB_KEY_Hangul_Phieuf = @as(c_int, 0x0ebd);
pub const XKB_KEY_Hangul_Hieuh = @as(c_int, 0x0ebe);
pub const XKB_KEY_Hangul_A = @as(c_int, 0x0ebf);
pub const XKB_KEY_Hangul_AE = @as(c_int, 0x0ec0);
pub const XKB_KEY_Hangul_YA = @as(c_int, 0x0ec1);
pub const XKB_KEY_Hangul_YAE = @as(c_int, 0x0ec2);
pub const XKB_KEY_Hangul_EO = @as(c_int, 0x0ec3);
pub const XKB_KEY_Hangul_E = @as(c_int, 0x0ec4);
pub const XKB_KEY_Hangul_YEO = @as(c_int, 0x0ec5);
pub const XKB_KEY_Hangul_YE = @as(c_int, 0x0ec6);
pub const XKB_KEY_Hangul_O = @as(c_int, 0x0ec7);
pub const XKB_KEY_Hangul_WA = @as(c_int, 0x0ec8);
pub const XKB_KEY_Hangul_WAE = @as(c_int, 0x0ec9);
pub const XKB_KEY_Hangul_OE = @as(c_int, 0x0eca);
pub const XKB_KEY_Hangul_YO = @as(c_int, 0x0ecb);
pub const XKB_KEY_Hangul_U = @as(c_int, 0x0ecc);
pub const XKB_KEY_Hangul_WEO = @as(c_int, 0x0ecd);
pub const XKB_KEY_Hangul_WE = @as(c_int, 0x0ece);
pub const XKB_KEY_Hangul_WI = @as(c_int, 0x0ecf);
pub const XKB_KEY_Hangul_YU = @as(c_int, 0x0ed0);
pub const XKB_KEY_Hangul_EU = @as(c_int, 0x0ed1);
pub const XKB_KEY_Hangul_YI = @as(c_int, 0x0ed2);
pub const XKB_KEY_Hangul_I = @as(c_int, 0x0ed3);
pub const XKB_KEY_Hangul_J_Kiyeog = @as(c_int, 0x0ed4);
pub const XKB_KEY_Hangul_J_SsangKiyeog = @as(c_int, 0x0ed5);
pub const XKB_KEY_Hangul_J_KiyeogSios = @as(c_int, 0x0ed6);
pub const XKB_KEY_Hangul_J_Nieun = @as(c_int, 0x0ed7);
pub const XKB_KEY_Hangul_J_NieunJieuj = @as(c_int, 0x0ed8);
pub const XKB_KEY_Hangul_J_NieunHieuh = @as(c_int, 0x0ed9);
pub const XKB_KEY_Hangul_J_Dikeud = @as(c_int, 0x0eda);
pub const XKB_KEY_Hangul_J_Rieul = @as(c_int, 0x0edb);
pub const XKB_KEY_Hangul_J_RieulKiyeog = @as(c_int, 0x0edc);
pub const XKB_KEY_Hangul_J_RieulMieum = @as(c_int, 0x0edd);
pub const XKB_KEY_Hangul_J_RieulPieub = @as(c_int, 0x0ede);
pub const XKB_KEY_Hangul_J_RieulSios = @as(c_int, 0x0edf);
pub const XKB_KEY_Hangul_J_RieulTieut = @as(c_int, 0x0ee0);
pub const XKB_KEY_Hangul_J_RieulPhieuf = @as(c_int, 0x0ee1);
pub const XKB_KEY_Hangul_J_RieulHieuh = @as(c_int, 0x0ee2);
pub const XKB_KEY_Hangul_J_Mieum = @as(c_int, 0x0ee3);
pub const XKB_KEY_Hangul_J_Pieub = @as(c_int, 0x0ee4);
pub const XKB_KEY_Hangul_J_PieubSios = @as(c_int, 0x0ee5);
pub const XKB_KEY_Hangul_J_Sios = @as(c_int, 0x0ee6);
pub const XKB_KEY_Hangul_J_SsangSios = @as(c_int, 0x0ee7);
pub const XKB_KEY_Hangul_J_Ieung = @as(c_int, 0x0ee8);
pub const XKB_KEY_Hangul_J_Jieuj = @as(c_int, 0x0ee9);
pub const XKB_KEY_Hangul_J_Cieuc = @as(c_int, 0x0eea);
pub const XKB_KEY_Hangul_J_Khieuq = @as(c_int, 0x0eeb);
pub const XKB_KEY_Hangul_J_Tieut = @as(c_int, 0x0eec);
pub const XKB_KEY_Hangul_J_Phieuf = @as(c_int, 0x0eed);
pub const XKB_KEY_Hangul_J_Hieuh = @as(c_int, 0x0eee);
pub const XKB_KEY_Hangul_RieulYeorinHieuh = @as(c_int, 0x0eef);
pub const XKB_KEY_Hangul_SunkyeongeumMieum = @as(c_int, 0x0ef0);
pub const XKB_KEY_Hangul_SunkyeongeumPieub = @as(c_int, 0x0ef1);
pub const XKB_KEY_Hangul_PanSios = @as(c_int, 0x0ef2);
pub const XKB_KEY_Hangul_KkogjiDalrinIeung = @as(c_int, 0x0ef3);
pub const XKB_KEY_Hangul_SunkyeongeumPhieuf = @as(c_int, 0x0ef4);
pub const XKB_KEY_Hangul_YeorinHieuh = @as(c_int, 0x0ef5);
pub const XKB_KEY_Hangul_AraeA = @as(c_int, 0x0ef6);
pub const XKB_KEY_Hangul_AraeAE = @as(c_int, 0x0ef7);
pub const XKB_KEY_Hangul_J_PanSios = @as(c_int, 0x0ef8);
pub const XKB_KEY_Hangul_J_KkogjiDalrinIeung = @as(c_int, 0x0ef9);
pub const XKB_KEY_Hangul_J_YeorinHieuh = @as(c_int, 0x0efa);
pub const XKB_KEY_Korean_Won = @as(c_int, 0x0eff);
pub const XKB_KEY_Armenian_ligature_ew = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000587, .hex);
pub const XKB_KEY_Armenian_full_stop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000589, .hex);
pub const XKB_KEY_Armenian_verjaket = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000589, .hex);
pub const XKB_KEY_Armenian_separation_mark = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055d, .hex);
pub const XKB_KEY_Armenian_but = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055d, .hex);
pub const XKB_KEY_Armenian_hyphen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100058a, .hex);
pub const XKB_KEY_Armenian_yentamna = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100058a, .hex);
pub const XKB_KEY_Armenian_exclam = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055c, .hex);
pub const XKB_KEY_Armenian_amanak = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055c, .hex);
pub const XKB_KEY_Armenian_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055b, .hex);
pub const XKB_KEY_Armenian_shesht = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055b, .hex);
pub const XKB_KEY_Armenian_question = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055e, .hex);
pub const XKB_KEY_Armenian_paruyk = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055e, .hex);
pub const XKB_KEY_Armenian_AYB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000531, .hex);
pub const XKB_KEY_Armenian_ayb = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000561, .hex);
pub const XKB_KEY_Armenian_BEN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000532, .hex);
pub const XKB_KEY_Armenian_ben = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000562, .hex);
pub const XKB_KEY_Armenian_GIM = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000533, .hex);
pub const XKB_KEY_Armenian_gim = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000563, .hex);
pub const XKB_KEY_Armenian_DA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000534, .hex);
pub const XKB_KEY_Armenian_da = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000564, .hex);
pub const XKB_KEY_Armenian_YECH = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000535, .hex);
pub const XKB_KEY_Armenian_yech = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000565, .hex);
pub const XKB_KEY_Armenian_ZA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000536, .hex);
pub const XKB_KEY_Armenian_za = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000566, .hex);
pub const XKB_KEY_Armenian_E = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000537, .hex);
pub const XKB_KEY_Armenian_e = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000567, .hex);
pub const XKB_KEY_Armenian_AT = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000538, .hex);
pub const XKB_KEY_Armenian_at = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000568, .hex);
pub const XKB_KEY_Armenian_TO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000539, .hex);
pub const XKB_KEY_Armenian_to = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000569, .hex);
pub const XKB_KEY_Armenian_ZHE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053a, .hex);
pub const XKB_KEY_Armenian_zhe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056a, .hex);
pub const XKB_KEY_Armenian_INI = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053b, .hex);
pub const XKB_KEY_Armenian_ini = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056b, .hex);
pub const XKB_KEY_Armenian_LYUN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053c, .hex);
pub const XKB_KEY_Armenian_lyun = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056c, .hex);
pub const XKB_KEY_Armenian_KHE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053d, .hex);
pub const XKB_KEY_Armenian_khe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056d, .hex);
pub const XKB_KEY_Armenian_TSA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053e, .hex);
pub const XKB_KEY_Armenian_tsa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056e, .hex);
pub const XKB_KEY_Armenian_KEN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100053f, .hex);
pub const XKB_KEY_Armenian_ken = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100056f, .hex);
pub const XKB_KEY_Armenian_HO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000540, .hex);
pub const XKB_KEY_Armenian_ho = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000570, .hex);
pub const XKB_KEY_Armenian_DZA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000541, .hex);
pub const XKB_KEY_Armenian_dza = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000571, .hex);
pub const XKB_KEY_Armenian_GHAT = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000542, .hex);
pub const XKB_KEY_Armenian_ghat = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000572, .hex);
pub const XKB_KEY_Armenian_TCHE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000543, .hex);
pub const XKB_KEY_Armenian_tche = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000573, .hex);
pub const XKB_KEY_Armenian_MEN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000544, .hex);
pub const XKB_KEY_Armenian_men = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000574, .hex);
pub const XKB_KEY_Armenian_HI = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000545, .hex);
pub const XKB_KEY_Armenian_hi = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000575, .hex);
pub const XKB_KEY_Armenian_NU = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000546, .hex);
pub const XKB_KEY_Armenian_nu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000576, .hex);
pub const XKB_KEY_Armenian_SHA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000547, .hex);
pub const XKB_KEY_Armenian_sha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000577, .hex);
pub const XKB_KEY_Armenian_VO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000548, .hex);
pub const XKB_KEY_Armenian_vo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000578, .hex);
pub const XKB_KEY_Armenian_CHA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000549, .hex);
pub const XKB_KEY_Armenian_cha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000579, .hex);
pub const XKB_KEY_Armenian_PE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054a, .hex);
pub const XKB_KEY_Armenian_pe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057a, .hex);
pub const XKB_KEY_Armenian_JE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054b, .hex);
pub const XKB_KEY_Armenian_je = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057b, .hex);
pub const XKB_KEY_Armenian_RA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054c, .hex);
pub const XKB_KEY_Armenian_ra = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057c, .hex);
pub const XKB_KEY_Armenian_SE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054d, .hex);
pub const XKB_KEY_Armenian_se = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057d, .hex);
pub const XKB_KEY_Armenian_VEV = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054e, .hex);
pub const XKB_KEY_Armenian_vev = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057e, .hex);
pub const XKB_KEY_Armenian_TYUN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100054f, .hex);
pub const XKB_KEY_Armenian_tyun = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100057f, .hex);
pub const XKB_KEY_Armenian_RE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000550, .hex);
pub const XKB_KEY_Armenian_re = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000580, .hex);
pub const XKB_KEY_Armenian_TSO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000551, .hex);
pub const XKB_KEY_Armenian_tso = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000581, .hex);
pub const XKB_KEY_Armenian_VYUN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000552, .hex);
pub const XKB_KEY_Armenian_vyun = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000582, .hex);
pub const XKB_KEY_Armenian_PYUR = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000553, .hex);
pub const XKB_KEY_Armenian_pyur = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000583, .hex);
pub const XKB_KEY_Armenian_KE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000554, .hex);
pub const XKB_KEY_Armenian_ke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000584, .hex);
pub const XKB_KEY_Armenian_O = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000555, .hex);
pub const XKB_KEY_Armenian_o = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000585, .hex);
pub const XKB_KEY_Armenian_FE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000556, .hex);
pub const XKB_KEY_Armenian_fe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000586, .hex);
pub const XKB_KEY_Armenian_apostrophe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100055a, .hex);
pub const XKB_KEY_Georgian_an = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d0, .hex);
pub const XKB_KEY_Georgian_ban = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d1, .hex);
pub const XKB_KEY_Georgian_gan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d2, .hex);
pub const XKB_KEY_Georgian_don = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d3, .hex);
pub const XKB_KEY_Georgian_en = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d4, .hex);
pub const XKB_KEY_Georgian_vin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d5, .hex);
pub const XKB_KEY_Georgian_zen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d6, .hex);
pub const XKB_KEY_Georgian_tan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d7, .hex);
pub const XKB_KEY_Georgian_in = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d8, .hex);
pub const XKB_KEY_Georgian_kan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010d9, .hex);
pub const XKB_KEY_Georgian_las = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010da, .hex);
pub const XKB_KEY_Georgian_man = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010db, .hex);
pub const XKB_KEY_Georgian_nar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010dc, .hex);
pub const XKB_KEY_Georgian_on = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010dd, .hex);
pub const XKB_KEY_Georgian_par = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010de, .hex);
pub const XKB_KEY_Georgian_zhar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010df, .hex);
pub const XKB_KEY_Georgian_rae = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e0, .hex);
pub const XKB_KEY_Georgian_san = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e1, .hex);
pub const XKB_KEY_Georgian_tar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e2, .hex);
pub const XKB_KEY_Georgian_un = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e3, .hex);
pub const XKB_KEY_Georgian_phar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e4, .hex);
pub const XKB_KEY_Georgian_khar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e5, .hex);
pub const XKB_KEY_Georgian_ghan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e6, .hex);
pub const XKB_KEY_Georgian_qar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e7, .hex);
pub const XKB_KEY_Georgian_shin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e8, .hex);
pub const XKB_KEY_Georgian_chin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010e9, .hex);
pub const XKB_KEY_Georgian_can = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010ea, .hex);
pub const XKB_KEY_Georgian_jil = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010eb, .hex);
pub const XKB_KEY_Georgian_cil = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010ec, .hex);
pub const XKB_KEY_Georgian_char = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010ed, .hex);
pub const XKB_KEY_Georgian_xan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010ee, .hex);
pub const XKB_KEY_Georgian_jhan = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010ef, .hex);
pub const XKB_KEY_Georgian_hae = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f0, .hex);
pub const XKB_KEY_Georgian_he = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f1, .hex);
pub const XKB_KEY_Georgian_hie = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f2, .hex);
pub const XKB_KEY_Georgian_we = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f3, .hex);
pub const XKB_KEY_Georgian_har = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f4, .hex);
pub const XKB_KEY_Georgian_hoe = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f5, .hex);
pub const XKB_KEY_Georgian_fi = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10010f6, .hex);
pub const XKB_KEY_Xabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e8a, .hex);
pub const XKB_KEY_Ibreve = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100012c, .hex);
pub const XKB_KEY_Zstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001b5, .hex);
pub const XKB_KEY_Gcaron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001e6, .hex);
pub const XKB_KEY_Ocaron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001d1, .hex);
pub const XKB_KEY_Obarred = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100019f, .hex);
pub const XKB_KEY_xabovedot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e8b, .hex);
pub const XKB_KEY_ibreve = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100012d, .hex);
pub const XKB_KEY_zstroke = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001b6, .hex);
pub const XKB_KEY_gcaron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001e7, .hex);
pub const XKB_KEY_ocaron = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001d2, .hex);
pub const XKB_KEY_obarred = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000275, .hex);
pub const XKB_KEY_SCHWA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100018f, .hex);
pub const XKB_KEY_schwa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000259, .hex);
pub const XKB_KEY_EZH = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001b7, .hex);
pub const XKB_KEY_ezh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000292, .hex);
pub const XKB_KEY_Lbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e36, .hex);
pub const XKB_KEY_lbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001e37, .hex);
pub const XKB_KEY_Abelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea0, .hex);
pub const XKB_KEY_abelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea1, .hex);
pub const XKB_KEY_Ahook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea2, .hex);
pub const XKB_KEY_ahook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea3, .hex);
pub const XKB_KEY_Acircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea4, .hex);
pub const XKB_KEY_acircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea5, .hex);
pub const XKB_KEY_Acircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea6, .hex);
pub const XKB_KEY_acircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea7, .hex);
pub const XKB_KEY_Acircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea8, .hex);
pub const XKB_KEY_acircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ea9, .hex);
pub const XKB_KEY_Acircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eaa, .hex);
pub const XKB_KEY_acircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eab, .hex);
pub const XKB_KEY_Acircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eac, .hex);
pub const XKB_KEY_acircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ead, .hex);
pub const XKB_KEY_Abreveacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eae, .hex);
pub const XKB_KEY_abreveacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eaf, .hex);
pub const XKB_KEY_Abrevegrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb0, .hex);
pub const XKB_KEY_abrevegrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb1, .hex);
pub const XKB_KEY_Abrevehook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb2, .hex);
pub const XKB_KEY_abrevehook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb3, .hex);
pub const XKB_KEY_Abrevetilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb4, .hex);
pub const XKB_KEY_abrevetilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb5, .hex);
pub const XKB_KEY_Abrevebelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb6, .hex);
pub const XKB_KEY_abrevebelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb7, .hex);
pub const XKB_KEY_Ebelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb8, .hex);
pub const XKB_KEY_ebelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eb9, .hex);
pub const XKB_KEY_Ehook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eba, .hex);
pub const XKB_KEY_ehook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ebb, .hex);
pub const XKB_KEY_Etilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ebc, .hex);
pub const XKB_KEY_etilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ebd, .hex);
pub const XKB_KEY_Ecircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ebe, .hex);
pub const XKB_KEY_ecircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ebf, .hex);
pub const XKB_KEY_Ecircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec0, .hex);
pub const XKB_KEY_ecircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec1, .hex);
pub const XKB_KEY_Ecircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec2, .hex);
pub const XKB_KEY_ecircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec3, .hex);
pub const XKB_KEY_Ecircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec4, .hex);
pub const XKB_KEY_ecircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec5, .hex);
pub const XKB_KEY_Ecircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec6, .hex);
pub const XKB_KEY_ecircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec7, .hex);
pub const XKB_KEY_Ihook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec8, .hex);
pub const XKB_KEY_ihook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ec9, .hex);
pub const XKB_KEY_Ibelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eca, .hex);
pub const XKB_KEY_ibelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ecb, .hex);
pub const XKB_KEY_Obelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ecc, .hex);
pub const XKB_KEY_obelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ecd, .hex);
pub const XKB_KEY_Ohook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ece, .hex);
pub const XKB_KEY_ohook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ecf, .hex);
pub const XKB_KEY_Ocircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed0, .hex);
pub const XKB_KEY_ocircumflexacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed1, .hex);
pub const XKB_KEY_Ocircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed2, .hex);
pub const XKB_KEY_ocircumflexgrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed3, .hex);
pub const XKB_KEY_Ocircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed4, .hex);
pub const XKB_KEY_ocircumflexhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed5, .hex);
pub const XKB_KEY_Ocircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed6, .hex);
pub const XKB_KEY_ocircumflextilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed7, .hex);
pub const XKB_KEY_Ocircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed8, .hex);
pub const XKB_KEY_ocircumflexbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ed9, .hex);
pub const XKB_KEY_Ohornacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eda, .hex);
pub const XKB_KEY_ohornacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001edb, .hex);
pub const XKB_KEY_Ohorngrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001edc, .hex);
pub const XKB_KEY_ohorngrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001edd, .hex);
pub const XKB_KEY_Ohornhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ede, .hex);
pub const XKB_KEY_ohornhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001edf, .hex);
pub const XKB_KEY_Ohorntilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee0, .hex);
pub const XKB_KEY_ohorntilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee1, .hex);
pub const XKB_KEY_Ohornbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee2, .hex);
pub const XKB_KEY_ohornbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee3, .hex);
pub const XKB_KEY_Ubelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee4, .hex);
pub const XKB_KEY_ubelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee5, .hex);
pub const XKB_KEY_Uhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee6, .hex);
pub const XKB_KEY_uhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee7, .hex);
pub const XKB_KEY_Uhornacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee8, .hex);
pub const XKB_KEY_uhornacute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ee9, .hex);
pub const XKB_KEY_Uhorngrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eea, .hex);
pub const XKB_KEY_uhorngrave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eeb, .hex);
pub const XKB_KEY_Uhornhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eec, .hex);
pub const XKB_KEY_uhornhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eed, .hex);
pub const XKB_KEY_Uhorntilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eee, .hex);
pub const XKB_KEY_uhorntilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001eef, .hex);
pub const XKB_KEY_Uhornbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef0, .hex);
pub const XKB_KEY_uhornbelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef1, .hex);
pub const XKB_KEY_Ybelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef4, .hex);
pub const XKB_KEY_ybelowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef5, .hex);
pub const XKB_KEY_Yhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef6, .hex);
pub const XKB_KEY_yhook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef7, .hex);
pub const XKB_KEY_Ytilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef8, .hex);
pub const XKB_KEY_ytilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1001ef9, .hex);
pub const XKB_KEY_Ohorn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001a0, .hex);
pub const XKB_KEY_ohorn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001a1, .hex);
pub const XKB_KEY_Uhorn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001af, .hex);
pub const XKB_KEY_uhorn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10001b0, .hex);
pub const XKB_KEY_combining_tilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000303, .hex);
pub const XKB_KEY_combining_grave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000300, .hex);
pub const XKB_KEY_combining_acute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000301, .hex);
pub const XKB_KEY_combining_hook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000309, .hex);
pub const XKB_KEY_combining_belowdot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000323, .hex);
pub const XKB_KEY_EcuSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a0, .hex);
pub const XKB_KEY_ColonSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a1, .hex);
pub const XKB_KEY_CruzeiroSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a2, .hex);
pub const XKB_KEY_FFrancSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a3, .hex);
pub const XKB_KEY_LiraSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a4, .hex);
pub const XKB_KEY_MillSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a5, .hex);
pub const XKB_KEY_NairaSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a6, .hex);
pub const XKB_KEY_PesetaSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a7, .hex);
pub const XKB_KEY_RupeeSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a8, .hex);
pub const XKB_KEY_WonSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020a9, .hex);
pub const XKB_KEY_NewSheqelSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020aa, .hex);
pub const XKB_KEY_DongSign = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10020ab, .hex);
pub const XKB_KEY_EuroSign = @as(c_int, 0x20ac);
pub const XKB_KEY_zerosuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002070, .hex);
pub const XKB_KEY_foursuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002074, .hex);
pub const XKB_KEY_fivesuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002075, .hex);
pub const XKB_KEY_sixsuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002076, .hex);
pub const XKB_KEY_sevensuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002077, .hex);
pub const XKB_KEY_eightsuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002078, .hex);
pub const XKB_KEY_ninesuperior = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002079, .hex);
pub const XKB_KEY_zerosubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002080, .hex);
pub const XKB_KEY_onesubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002081, .hex);
pub const XKB_KEY_twosubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002082, .hex);
pub const XKB_KEY_threesubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002083, .hex);
pub const XKB_KEY_foursubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002084, .hex);
pub const XKB_KEY_fivesubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002085, .hex);
pub const XKB_KEY_sixsubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002086, .hex);
pub const XKB_KEY_sevensubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002087, .hex);
pub const XKB_KEY_eightsubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002088, .hex);
pub const XKB_KEY_ninesubscript = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002089, .hex);
pub const XKB_KEY_partdifferential = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002202, .hex);
pub const XKB_KEY_emptyset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002205, .hex);
pub const XKB_KEY_elementof = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002208, .hex);
pub const XKB_KEY_notelementof = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002209, .hex);
pub const XKB_KEY_containsas = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100220b, .hex);
pub const XKB_KEY_squareroot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100221a, .hex);
pub const XKB_KEY_cuberoot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100221b, .hex);
pub const XKB_KEY_fourthroot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100221c, .hex);
pub const XKB_KEY_dintegral = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100222c, .hex);
pub const XKB_KEY_tintegral = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100222d, .hex);
pub const XKB_KEY_because = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002235, .hex);
pub const XKB_KEY_approxeq = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002248, .hex);
pub const XKB_KEY_notapproxeq = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002247, .hex);
pub const XKB_KEY_notidentical = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002262, .hex);
pub const XKB_KEY_stricteq = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002263, .hex);
pub const XKB_KEY_braille_dot_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff1, .hex);
pub const XKB_KEY_braille_dot_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff2, .hex);
pub const XKB_KEY_braille_dot_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff3, .hex);
pub const XKB_KEY_braille_dot_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff4, .hex);
pub const XKB_KEY_braille_dot_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff5, .hex);
pub const XKB_KEY_braille_dot_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff6, .hex);
pub const XKB_KEY_braille_dot_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff7, .hex);
pub const XKB_KEY_braille_dot_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff8, .hex);
pub const XKB_KEY_braille_dot_9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfff9, .hex);
pub const XKB_KEY_braille_dot_10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xfffa, .hex);
pub const XKB_KEY_braille_blank = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002800, .hex);
pub const XKB_KEY_braille_dots_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002801, .hex);
pub const XKB_KEY_braille_dots_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002802, .hex);
pub const XKB_KEY_braille_dots_12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002803, .hex);
pub const XKB_KEY_braille_dots_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002804, .hex);
pub const XKB_KEY_braille_dots_13 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002805, .hex);
pub const XKB_KEY_braille_dots_23 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002806, .hex);
pub const XKB_KEY_braille_dots_123 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002807, .hex);
pub const XKB_KEY_braille_dots_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002808, .hex);
pub const XKB_KEY_braille_dots_14 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002809, .hex);
pub const XKB_KEY_braille_dots_24 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280a, .hex);
pub const XKB_KEY_braille_dots_124 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280b, .hex);
pub const XKB_KEY_braille_dots_34 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280c, .hex);
pub const XKB_KEY_braille_dots_134 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280d, .hex);
pub const XKB_KEY_braille_dots_234 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280e, .hex);
pub const XKB_KEY_braille_dots_1234 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100280f, .hex);
pub const XKB_KEY_braille_dots_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002810, .hex);
pub const XKB_KEY_braille_dots_15 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002811, .hex);
pub const XKB_KEY_braille_dots_25 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002812, .hex);
pub const XKB_KEY_braille_dots_125 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002813, .hex);
pub const XKB_KEY_braille_dots_35 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002814, .hex);
pub const XKB_KEY_braille_dots_135 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002815, .hex);
pub const XKB_KEY_braille_dots_235 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002816, .hex);
pub const XKB_KEY_braille_dots_1235 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002817, .hex);
pub const XKB_KEY_braille_dots_45 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002818, .hex);
pub const XKB_KEY_braille_dots_145 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002819, .hex);
pub const XKB_KEY_braille_dots_245 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281a, .hex);
pub const XKB_KEY_braille_dots_1245 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281b, .hex);
pub const XKB_KEY_braille_dots_345 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281c, .hex);
pub const XKB_KEY_braille_dots_1345 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281d, .hex);
pub const XKB_KEY_braille_dots_2345 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281e, .hex);
pub const XKB_KEY_braille_dots_12345 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100281f, .hex);
pub const XKB_KEY_braille_dots_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002820, .hex);
pub const XKB_KEY_braille_dots_16 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002821, .hex);
pub const XKB_KEY_braille_dots_26 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002822, .hex);
pub const XKB_KEY_braille_dots_126 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002823, .hex);
pub const XKB_KEY_braille_dots_36 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002824, .hex);
pub const XKB_KEY_braille_dots_136 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002825, .hex);
pub const XKB_KEY_braille_dots_236 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002826, .hex);
pub const XKB_KEY_braille_dots_1236 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002827, .hex);
pub const XKB_KEY_braille_dots_46 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002828, .hex);
pub const XKB_KEY_braille_dots_146 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002829, .hex);
pub const XKB_KEY_braille_dots_246 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282a, .hex);
pub const XKB_KEY_braille_dots_1246 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282b, .hex);
pub const XKB_KEY_braille_dots_346 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282c, .hex);
pub const XKB_KEY_braille_dots_1346 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282d, .hex);
pub const XKB_KEY_braille_dots_2346 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282e, .hex);
pub const XKB_KEY_braille_dots_12346 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100282f, .hex);
pub const XKB_KEY_braille_dots_56 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002830, .hex);
pub const XKB_KEY_braille_dots_156 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002831, .hex);
pub const XKB_KEY_braille_dots_256 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002832, .hex);
pub const XKB_KEY_braille_dots_1256 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002833, .hex);
pub const XKB_KEY_braille_dots_356 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002834, .hex);
pub const XKB_KEY_braille_dots_1356 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002835, .hex);
pub const XKB_KEY_braille_dots_2356 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002836, .hex);
pub const XKB_KEY_braille_dots_12356 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002837, .hex);
pub const XKB_KEY_braille_dots_456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002838, .hex);
pub const XKB_KEY_braille_dots_1456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002839, .hex);
pub const XKB_KEY_braille_dots_2456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283a, .hex);
pub const XKB_KEY_braille_dots_12456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283b, .hex);
pub const XKB_KEY_braille_dots_3456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283c, .hex);
pub const XKB_KEY_braille_dots_13456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283d, .hex);
pub const XKB_KEY_braille_dots_23456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283e, .hex);
pub const XKB_KEY_braille_dots_123456 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100283f, .hex);
pub const XKB_KEY_braille_dots_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002840, .hex);
pub const XKB_KEY_braille_dots_17 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002841, .hex);
pub const XKB_KEY_braille_dots_27 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002842, .hex);
pub const XKB_KEY_braille_dots_127 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002843, .hex);
pub const XKB_KEY_braille_dots_37 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002844, .hex);
pub const XKB_KEY_braille_dots_137 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002845, .hex);
pub const XKB_KEY_braille_dots_237 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002846, .hex);
pub const XKB_KEY_braille_dots_1237 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002847, .hex);
pub const XKB_KEY_braille_dots_47 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002848, .hex);
pub const XKB_KEY_braille_dots_147 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002849, .hex);
pub const XKB_KEY_braille_dots_247 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284a, .hex);
pub const XKB_KEY_braille_dots_1247 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284b, .hex);
pub const XKB_KEY_braille_dots_347 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284c, .hex);
pub const XKB_KEY_braille_dots_1347 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284d, .hex);
pub const XKB_KEY_braille_dots_2347 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284e, .hex);
pub const XKB_KEY_braille_dots_12347 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100284f, .hex);
pub const XKB_KEY_braille_dots_57 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002850, .hex);
pub const XKB_KEY_braille_dots_157 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002851, .hex);
pub const XKB_KEY_braille_dots_257 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002852, .hex);
pub const XKB_KEY_braille_dots_1257 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002853, .hex);
pub const XKB_KEY_braille_dots_357 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002854, .hex);
pub const XKB_KEY_braille_dots_1357 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002855, .hex);
pub const XKB_KEY_braille_dots_2357 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002856, .hex);
pub const XKB_KEY_braille_dots_12357 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002857, .hex);
pub const XKB_KEY_braille_dots_457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002858, .hex);
pub const XKB_KEY_braille_dots_1457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002859, .hex);
pub const XKB_KEY_braille_dots_2457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285a, .hex);
pub const XKB_KEY_braille_dots_12457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285b, .hex);
pub const XKB_KEY_braille_dots_3457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285c, .hex);
pub const XKB_KEY_braille_dots_13457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285d, .hex);
pub const XKB_KEY_braille_dots_23457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285e, .hex);
pub const XKB_KEY_braille_dots_123457 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100285f, .hex);
pub const XKB_KEY_braille_dots_67 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002860, .hex);
pub const XKB_KEY_braille_dots_167 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002861, .hex);
pub const XKB_KEY_braille_dots_267 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002862, .hex);
pub const XKB_KEY_braille_dots_1267 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002863, .hex);
pub const XKB_KEY_braille_dots_367 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002864, .hex);
pub const XKB_KEY_braille_dots_1367 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002865, .hex);
pub const XKB_KEY_braille_dots_2367 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002866, .hex);
pub const XKB_KEY_braille_dots_12367 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002867, .hex);
pub const XKB_KEY_braille_dots_467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002868, .hex);
pub const XKB_KEY_braille_dots_1467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002869, .hex);
pub const XKB_KEY_braille_dots_2467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286a, .hex);
pub const XKB_KEY_braille_dots_12467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286b, .hex);
pub const XKB_KEY_braille_dots_3467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286c, .hex);
pub const XKB_KEY_braille_dots_13467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286d, .hex);
pub const XKB_KEY_braille_dots_23467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286e, .hex);
pub const XKB_KEY_braille_dots_123467 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100286f, .hex);
pub const XKB_KEY_braille_dots_567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002870, .hex);
pub const XKB_KEY_braille_dots_1567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002871, .hex);
pub const XKB_KEY_braille_dots_2567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002872, .hex);
pub const XKB_KEY_braille_dots_12567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002873, .hex);
pub const XKB_KEY_braille_dots_3567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002874, .hex);
pub const XKB_KEY_braille_dots_13567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002875, .hex);
pub const XKB_KEY_braille_dots_23567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002876, .hex);
pub const XKB_KEY_braille_dots_123567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002877, .hex);
pub const XKB_KEY_braille_dots_4567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002878, .hex);
pub const XKB_KEY_braille_dots_14567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002879, .hex);
pub const XKB_KEY_braille_dots_24567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287a, .hex);
pub const XKB_KEY_braille_dots_124567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287b, .hex);
pub const XKB_KEY_braille_dots_34567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287c, .hex);
pub const XKB_KEY_braille_dots_134567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287d, .hex);
pub const XKB_KEY_braille_dots_234567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287e, .hex);
pub const XKB_KEY_braille_dots_1234567 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100287f, .hex);
pub const XKB_KEY_braille_dots_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002880, .hex);
pub const XKB_KEY_braille_dots_18 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002881, .hex);
pub const XKB_KEY_braille_dots_28 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002882, .hex);
pub const XKB_KEY_braille_dots_128 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002883, .hex);
pub const XKB_KEY_braille_dots_38 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002884, .hex);
pub const XKB_KEY_braille_dots_138 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002885, .hex);
pub const XKB_KEY_braille_dots_238 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002886, .hex);
pub const XKB_KEY_braille_dots_1238 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002887, .hex);
pub const XKB_KEY_braille_dots_48 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002888, .hex);
pub const XKB_KEY_braille_dots_148 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002889, .hex);
pub const XKB_KEY_braille_dots_248 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288a, .hex);
pub const XKB_KEY_braille_dots_1248 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288b, .hex);
pub const XKB_KEY_braille_dots_348 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288c, .hex);
pub const XKB_KEY_braille_dots_1348 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288d, .hex);
pub const XKB_KEY_braille_dots_2348 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288e, .hex);
pub const XKB_KEY_braille_dots_12348 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100288f, .hex);
pub const XKB_KEY_braille_dots_58 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002890, .hex);
pub const XKB_KEY_braille_dots_158 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002891, .hex);
pub const XKB_KEY_braille_dots_258 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002892, .hex);
pub const XKB_KEY_braille_dots_1258 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002893, .hex);
pub const XKB_KEY_braille_dots_358 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002894, .hex);
pub const XKB_KEY_braille_dots_1358 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002895, .hex);
pub const XKB_KEY_braille_dots_2358 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002896, .hex);
pub const XKB_KEY_braille_dots_12358 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002897, .hex);
pub const XKB_KEY_braille_dots_458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002898, .hex);
pub const XKB_KEY_braille_dots_1458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1002899, .hex);
pub const XKB_KEY_braille_dots_2458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289a, .hex);
pub const XKB_KEY_braille_dots_12458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289b, .hex);
pub const XKB_KEY_braille_dots_3458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289c, .hex);
pub const XKB_KEY_braille_dots_13458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289d, .hex);
pub const XKB_KEY_braille_dots_23458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289e, .hex);
pub const XKB_KEY_braille_dots_123458 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100289f, .hex);
pub const XKB_KEY_braille_dots_68 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a0, .hex);
pub const XKB_KEY_braille_dots_168 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a1, .hex);
pub const XKB_KEY_braille_dots_268 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a2, .hex);
pub const XKB_KEY_braille_dots_1268 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a3, .hex);
pub const XKB_KEY_braille_dots_368 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a4, .hex);
pub const XKB_KEY_braille_dots_1368 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a5, .hex);
pub const XKB_KEY_braille_dots_2368 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a6, .hex);
pub const XKB_KEY_braille_dots_12368 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a7, .hex);
pub const XKB_KEY_braille_dots_468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a8, .hex);
pub const XKB_KEY_braille_dots_1468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028a9, .hex);
pub const XKB_KEY_braille_dots_2468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028aa, .hex);
pub const XKB_KEY_braille_dots_12468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ab, .hex);
pub const XKB_KEY_braille_dots_3468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ac, .hex);
pub const XKB_KEY_braille_dots_13468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ad, .hex);
pub const XKB_KEY_braille_dots_23468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ae, .hex);
pub const XKB_KEY_braille_dots_123468 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028af, .hex);
pub const XKB_KEY_braille_dots_568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b0, .hex);
pub const XKB_KEY_braille_dots_1568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b1, .hex);
pub const XKB_KEY_braille_dots_2568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b2, .hex);
pub const XKB_KEY_braille_dots_12568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b3, .hex);
pub const XKB_KEY_braille_dots_3568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b4, .hex);
pub const XKB_KEY_braille_dots_13568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b5, .hex);
pub const XKB_KEY_braille_dots_23568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b6, .hex);
pub const XKB_KEY_braille_dots_123568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b7, .hex);
pub const XKB_KEY_braille_dots_4568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b8, .hex);
pub const XKB_KEY_braille_dots_14568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028b9, .hex);
pub const XKB_KEY_braille_dots_24568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ba, .hex);
pub const XKB_KEY_braille_dots_124568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028bb, .hex);
pub const XKB_KEY_braille_dots_34568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028bc, .hex);
pub const XKB_KEY_braille_dots_134568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028bd, .hex);
pub const XKB_KEY_braille_dots_234568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028be, .hex);
pub const XKB_KEY_braille_dots_1234568 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028bf, .hex);
pub const XKB_KEY_braille_dots_78 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c0, .hex);
pub const XKB_KEY_braille_dots_178 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c1, .hex);
pub const XKB_KEY_braille_dots_278 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c2, .hex);
pub const XKB_KEY_braille_dots_1278 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c3, .hex);
pub const XKB_KEY_braille_dots_378 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c4, .hex);
pub const XKB_KEY_braille_dots_1378 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c5, .hex);
pub const XKB_KEY_braille_dots_2378 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c6, .hex);
pub const XKB_KEY_braille_dots_12378 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c7, .hex);
pub const XKB_KEY_braille_dots_478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c8, .hex);
pub const XKB_KEY_braille_dots_1478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028c9, .hex);
pub const XKB_KEY_braille_dots_2478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ca, .hex);
pub const XKB_KEY_braille_dots_12478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028cb, .hex);
pub const XKB_KEY_braille_dots_3478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028cc, .hex);
pub const XKB_KEY_braille_dots_13478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028cd, .hex);
pub const XKB_KEY_braille_dots_23478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ce, .hex);
pub const XKB_KEY_braille_dots_123478 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028cf, .hex);
pub const XKB_KEY_braille_dots_578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d0, .hex);
pub const XKB_KEY_braille_dots_1578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d1, .hex);
pub const XKB_KEY_braille_dots_2578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d2, .hex);
pub const XKB_KEY_braille_dots_12578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d3, .hex);
pub const XKB_KEY_braille_dots_3578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d4, .hex);
pub const XKB_KEY_braille_dots_13578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d5, .hex);
pub const XKB_KEY_braille_dots_23578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d6, .hex);
pub const XKB_KEY_braille_dots_123578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d7, .hex);
pub const XKB_KEY_braille_dots_4578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d8, .hex);
pub const XKB_KEY_braille_dots_14578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028d9, .hex);
pub const XKB_KEY_braille_dots_24578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028da, .hex);
pub const XKB_KEY_braille_dots_124578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028db, .hex);
pub const XKB_KEY_braille_dots_34578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028dc, .hex);
pub const XKB_KEY_braille_dots_134578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028dd, .hex);
pub const XKB_KEY_braille_dots_234578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028de, .hex);
pub const XKB_KEY_braille_dots_1234578 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028df, .hex);
pub const XKB_KEY_braille_dots_678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e0, .hex);
pub const XKB_KEY_braille_dots_1678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e1, .hex);
pub const XKB_KEY_braille_dots_2678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e2, .hex);
pub const XKB_KEY_braille_dots_12678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e3, .hex);
pub const XKB_KEY_braille_dots_3678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e4, .hex);
pub const XKB_KEY_braille_dots_13678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e5, .hex);
pub const XKB_KEY_braille_dots_23678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e6, .hex);
pub const XKB_KEY_braille_dots_123678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e7, .hex);
pub const XKB_KEY_braille_dots_4678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e8, .hex);
pub const XKB_KEY_braille_dots_14678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028e9, .hex);
pub const XKB_KEY_braille_dots_24678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ea, .hex);
pub const XKB_KEY_braille_dots_124678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028eb, .hex);
pub const XKB_KEY_braille_dots_34678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ec, .hex);
pub const XKB_KEY_braille_dots_134678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ed, .hex);
pub const XKB_KEY_braille_dots_234678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ee, .hex);
pub const XKB_KEY_braille_dots_1234678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ef, .hex);
pub const XKB_KEY_braille_dots_5678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f0, .hex);
pub const XKB_KEY_braille_dots_15678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f1, .hex);
pub const XKB_KEY_braille_dots_25678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f2, .hex);
pub const XKB_KEY_braille_dots_125678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f3, .hex);
pub const XKB_KEY_braille_dots_35678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f4, .hex);
pub const XKB_KEY_braille_dots_135678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f5, .hex);
pub const XKB_KEY_braille_dots_235678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f6, .hex);
pub const XKB_KEY_braille_dots_1235678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f7, .hex);
pub const XKB_KEY_braille_dots_45678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f8, .hex);
pub const XKB_KEY_braille_dots_145678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028f9, .hex);
pub const XKB_KEY_braille_dots_245678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028fa, .hex);
pub const XKB_KEY_braille_dots_1245678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028fb, .hex);
pub const XKB_KEY_braille_dots_345678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028fc, .hex);
pub const XKB_KEY_braille_dots_1345678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028fd, .hex);
pub const XKB_KEY_braille_dots_2345678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028fe, .hex);
pub const XKB_KEY_braille_dots_12345678 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10028ff, .hex);
pub const XKB_KEY_Sinh_ng = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d82, .hex);
pub const XKB_KEY_Sinh_h2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d83, .hex);
pub const XKB_KEY_Sinh_a = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d85, .hex);
pub const XKB_KEY_Sinh_aa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d86, .hex);
pub const XKB_KEY_Sinh_ae = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d87, .hex);
pub const XKB_KEY_Sinh_aee = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d88, .hex);
pub const XKB_KEY_Sinh_i = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d89, .hex);
pub const XKB_KEY_Sinh_ii = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8a, .hex);
pub const XKB_KEY_Sinh_u = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8b, .hex);
pub const XKB_KEY_Sinh_uu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8c, .hex);
pub const XKB_KEY_Sinh_ri = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8d, .hex);
pub const XKB_KEY_Sinh_rii = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8e, .hex);
pub const XKB_KEY_Sinh_lu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d8f, .hex);
pub const XKB_KEY_Sinh_luu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d90, .hex);
pub const XKB_KEY_Sinh_e = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d91, .hex);
pub const XKB_KEY_Sinh_ee = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d92, .hex);
pub const XKB_KEY_Sinh_ai = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d93, .hex);
pub const XKB_KEY_Sinh_o = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d94, .hex);
pub const XKB_KEY_Sinh_oo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d95, .hex);
pub const XKB_KEY_Sinh_au = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d96, .hex);
pub const XKB_KEY_Sinh_ka = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9a, .hex);
pub const XKB_KEY_Sinh_kha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9b, .hex);
pub const XKB_KEY_Sinh_ga = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9c, .hex);
pub const XKB_KEY_Sinh_gha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9d, .hex);
pub const XKB_KEY_Sinh_ng2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9e, .hex);
pub const XKB_KEY_Sinh_nga = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000d9f, .hex);
pub const XKB_KEY_Sinh_ca = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da0, .hex);
pub const XKB_KEY_Sinh_cha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da1, .hex);
pub const XKB_KEY_Sinh_ja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da2, .hex);
pub const XKB_KEY_Sinh_jha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da3, .hex);
pub const XKB_KEY_Sinh_nya = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da4, .hex);
pub const XKB_KEY_Sinh_jnya = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da5, .hex);
pub const XKB_KEY_Sinh_nja = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da6, .hex);
pub const XKB_KEY_Sinh_tta = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da7, .hex);
pub const XKB_KEY_Sinh_ttha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da8, .hex);
pub const XKB_KEY_Sinh_dda = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000da9, .hex);
pub const XKB_KEY_Sinh_ddha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000daa, .hex);
pub const XKB_KEY_Sinh_nna = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dab, .hex);
pub const XKB_KEY_Sinh_ndda = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dac, .hex);
pub const XKB_KEY_Sinh_tha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dad, .hex);
pub const XKB_KEY_Sinh_thha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dae, .hex);
pub const XKB_KEY_Sinh_dha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000daf, .hex);
pub const XKB_KEY_Sinh_dhha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db0, .hex);
pub const XKB_KEY_Sinh_na = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db1, .hex);
pub const XKB_KEY_Sinh_ndha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db3, .hex);
pub const XKB_KEY_Sinh_pa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db4, .hex);
pub const XKB_KEY_Sinh_pha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db5, .hex);
pub const XKB_KEY_Sinh_ba = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db6, .hex);
pub const XKB_KEY_Sinh_bha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db7, .hex);
pub const XKB_KEY_Sinh_ma = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db8, .hex);
pub const XKB_KEY_Sinh_mba = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000db9, .hex);
pub const XKB_KEY_Sinh_ya = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dba, .hex);
pub const XKB_KEY_Sinh_ra = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dbb, .hex);
pub const XKB_KEY_Sinh_la = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dbd, .hex);
pub const XKB_KEY_Sinh_va = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc0, .hex);
pub const XKB_KEY_Sinh_sha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc1, .hex);
pub const XKB_KEY_Sinh_ssha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc2, .hex);
pub const XKB_KEY_Sinh_sa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc3, .hex);
pub const XKB_KEY_Sinh_ha = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc4, .hex);
pub const XKB_KEY_Sinh_lla = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc5, .hex);
pub const XKB_KEY_Sinh_fa = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dc6, .hex);
pub const XKB_KEY_Sinh_al = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dca, .hex);
pub const XKB_KEY_Sinh_aa2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dcf, .hex);
pub const XKB_KEY_Sinh_ae2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd0, .hex);
pub const XKB_KEY_Sinh_aee2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd1, .hex);
pub const XKB_KEY_Sinh_i2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd2, .hex);
pub const XKB_KEY_Sinh_ii2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd3, .hex);
pub const XKB_KEY_Sinh_u2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd4, .hex);
pub const XKB_KEY_Sinh_uu2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd6, .hex);
pub const XKB_KEY_Sinh_ru2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd8, .hex);
pub const XKB_KEY_Sinh_e2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dd9, .hex);
pub const XKB_KEY_Sinh_ee2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dda, .hex);
pub const XKB_KEY_Sinh_ai2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ddb, .hex);
pub const XKB_KEY_Sinh_o2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ddc, .hex);
pub const XKB_KEY_Sinh_oo2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ddd, .hex);
pub const XKB_KEY_Sinh_au2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000dde, .hex);
pub const XKB_KEY_Sinh_lu2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ddf, .hex);
pub const XKB_KEY_Sinh_ruu2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000df2, .hex);
pub const XKB_KEY_Sinh_luu2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000df3, .hex);
pub const XKB_KEY_Sinh_kunddaliya = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000df4, .hex);
pub const XKB_KEY_XF86ModeLock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff01, .hex);
pub const XKB_KEY_XF86MonBrightnessUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff02, .hex);
pub const XKB_KEY_XF86MonBrightnessDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff03, .hex);
pub const XKB_KEY_XF86KbdLightOnOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff04, .hex);
pub const XKB_KEY_XF86KbdBrightnessUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff05, .hex);
pub const XKB_KEY_XF86KbdBrightnessDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff06, .hex);
pub const XKB_KEY_XF86MonBrightnessCycle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff07, .hex);
pub const XKB_KEY_XF86Standby = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff10, .hex);
pub const XKB_KEY_XF86AudioLowerVolume = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff11, .hex);
pub const XKB_KEY_XF86AudioMute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff12, .hex);
pub const XKB_KEY_XF86AudioRaiseVolume = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff13, .hex);
pub const XKB_KEY_XF86AudioPlay = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff14, .hex);
pub const XKB_KEY_XF86AudioStop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff15, .hex);
pub const XKB_KEY_XF86AudioPrev = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff16, .hex);
pub const XKB_KEY_XF86AudioNext = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff17, .hex);
pub const XKB_KEY_XF86HomePage = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff18, .hex);
pub const XKB_KEY_XF86Mail = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff19, .hex);
pub const XKB_KEY_XF86Start = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1a, .hex);
pub const XKB_KEY_XF86Search = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1b, .hex);
pub const XKB_KEY_XF86AudioRecord = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1c, .hex);
pub const XKB_KEY_XF86Calculator = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1d, .hex);
pub const XKB_KEY_XF86Memo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1e, .hex);
pub const XKB_KEY_XF86ToDoList = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff1f, .hex);
pub const XKB_KEY_XF86Calendar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff20, .hex);
pub const XKB_KEY_XF86PowerDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff21, .hex);
pub const XKB_KEY_XF86ContrastAdjust = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff22, .hex);
pub const XKB_KEY_XF86RockerUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff23, .hex);
pub const XKB_KEY_XF86RockerDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff24, .hex);
pub const XKB_KEY_XF86RockerEnter = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff25, .hex);
pub const XKB_KEY_XF86Back = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff26, .hex);
pub const XKB_KEY_XF86Forward = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff27, .hex);
pub const XKB_KEY_XF86Stop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff28, .hex);
pub const XKB_KEY_XF86Refresh = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff29, .hex);
pub const XKB_KEY_XF86PowerOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2a, .hex);
pub const XKB_KEY_XF86WakeUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2b, .hex);
pub const XKB_KEY_XF86Eject = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2c, .hex);
pub const XKB_KEY_XF86ScreenSaver = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2d, .hex);
pub const XKB_KEY_XF86WWW = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2e, .hex);
pub const XKB_KEY_XF86Sleep = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff2f, .hex);
pub const XKB_KEY_XF86Favorites = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff30, .hex);
pub const XKB_KEY_XF86AudioPause = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff31, .hex);
pub const XKB_KEY_XF86AudioMedia = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff32, .hex);
pub const XKB_KEY_XF86MyComputer = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff33, .hex);
pub const XKB_KEY_XF86VendorHome = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff34, .hex);
pub const XKB_KEY_XF86LightBulb = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff35, .hex);
pub const XKB_KEY_XF86Shop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff36, .hex);
pub const XKB_KEY_XF86History = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff37, .hex);
pub const XKB_KEY_XF86OpenURL = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff38, .hex);
pub const XKB_KEY_XF86AddFavorite = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff39, .hex);
pub const XKB_KEY_XF86HotLinks = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3a, .hex);
pub const XKB_KEY_XF86BrightnessAdjust = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3b, .hex);
pub const XKB_KEY_XF86Finance = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3c, .hex);
pub const XKB_KEY_XF86Community = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3d, .hex);
pub const XKB_KEY_XF86AudioRewind = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3e, .hex);
pub const XKB_KEY_XF86BackForward = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff3f, .hex);
pub const XKB_KEY_XF86Launch0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff40, .hex);
pub const XKB_KEY_XF86Launch1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff41, .hex);
pub const XKB_KEY_XF86Launch2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff42, .hex);
pub const XKB_KEY_XF86Launch3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff43, .hex);
pub const XKB_KEY_XF86Launch4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff44, .hex);
pub const XKB_KEY_XF86Launch5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff45, .hex);
pub const XKB_KEY_XF86Launch6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff46, .hex);
pub const XKB_KEY_XF86Launch7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff47, .hex);
pub const XKB_KEY_XF86Launch8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff48, .hex);
pub const XKB_KEY_XF86Launch9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff49, .hex);
pub const XKB_KEY_XF86LaunchA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4a, .hex);
pub const XKB_KEY_XF86LaunchB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4b, .hex);
pub const XKB_KEY_XF86LaunchC = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4c, .hex);
pub const XKB_KEY_XF86LaunchD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4d, .hex);
pub const XKB_KEY_XF86LaunchE = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4e, .hex);
pub const XKB_KEY_XF86LaunchF = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff4f, .hex);
pub const XKB_KEY_XF86ApplicationLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff50, .hex);
pub const XKB_KEY_XF86ApplicationRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff51, .hex);
pub const XKB_KEY_XF86Book = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff52, .hex);
pub const XKB_KEY_XF86CD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff53, .hex);
pub const XKB_KEY_XF86MediaSelectCD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff53, .hex);
pub const XKB_KEY_XF86Calculater = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff54, .hex);
pub const XKB_KEY_XF86Clear = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff55, .hex);
pub const XKB_KEY_XF86Close = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff56, .hex);
pub const XKB_KEY_XF86Copy = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff57, .hex);
pub const XKB_KEY_XF86Cut = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff58, .hex);
pub const XKB_KEY_XF86Display = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff59, .hex);
pub const XKB_KEY_XF86DOS = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5a, .hex);
pub const XKB_KEY_XF86Documents = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5b, .hex);
pub const XKB_KEY_XF86Excel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5c, .hex);
pub const XKB_KEY_XF86Explorer = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5d, .hex);
pub const XKB_KEY_XF86Game = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5e, .hex);
pub const XKB_KEY_XF86Go = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff5f, .hex);
pub const XKB_KEY_XF86iTouch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff60, .hex);
pub const XKB_KEY_XF86LogOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff61, .hex);
pub const XKB_KEY_XF86Market = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff62, .hex);
pub const XKB_KEY_XF86Meeting = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff63, .hex);
pub const XKB_KEY_XF86MenuKB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff65, .hex);
pub const XKB_KEY_XF86MenuPB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff66, .hex);
pub const XKB_KEY_XF86MySites = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff67, .hex);
pub const XKB_KEY_XF86New = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff68, .hex);
pub const XKB_KEY_XF86News = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff69, .hex);
pub const XKB_KEY_XF86OfficeHome = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff6a, .hex);
pub const XKB_KEY_XF86Open = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff6b, .hex);
pub const XKB_KEY_XF86Option = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff6c, .hex);
pub const XKB_KEY_XF86Paste = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff6d, .hex);
pub const XKB_KEY_XF86Phone = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff6e, .hex);
pub const XKB_KEY_XF86Q = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff70, .hex);
pub const XKB_KEY_XF86Reply = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff72, .hex);
pub const XKB_KEY_XF86Reload = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff73, .hex);
pub const XKB_KEY_XF86RotateWindows = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff74, .hex);
pub const XKB_KEY_XF86RotationPB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff75, .hex);
pub const XKB_KEY_XF86RotationKB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff76, .hex);
pub const XKB_KEY_XF86Save = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff77, .hex);
pub const XKB_KEY_XF86ScrollUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff78, .hex);
pub const XKB_KEY_XF86ScrollDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff79, .hex);
pub const XKB_KEY_XF86ScrollClick = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7a, .hex);
pub const XKB_KEY_XF86Send = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7b, .hex);
pub const XKB_KEY_XF86Spell = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7c, .hex);
pub const XKB_KEY_XF86SplitScreen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7d, .hex);
pub const XKB_KEY_XF86Support = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7e, .hex);
pub const XKB_KEY_XF86TaskPane = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff7f, .hex);
pub const XKB_KEY_XF86Terminal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff80, .hex);
pub const XKB_KEY_XF86Tools = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff81, .hex);
pub const XKB_KEY_XF86Travel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff82, .hex);
pub const XKB_KEY_XF86UserPB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff84, .hex);
pub const XKB_KEY_XF86User1KB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff85, .hex);
pub const XKB_KEY_XF86User2KB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff86, .hex);
pub const XKB_KEY_XF86Video = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff87, .hex);
pub const XKB_KEY_XF86WheelButton = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff88, .hex);
pub const XKB_KEY_XF86Word = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff89, .hex);
pub const XKB_KEY_XF86Xfer = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8a, .hex);
pub const XKB_KEY_XF86ZoomIn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8b, .hex);
pub const XKB_KEY_XF86ZoomOut = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8c, .hex);
pub const XKB_KEY_XF86Away = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8d, .hex);
pub const XKB_KEY_XF86Messenger = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8e, .hex);
pub const XKB_KEY_XF86WebCam = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff8f, .hex);
pub const XKB_KEY_XF86MailForward = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff90, .hex);
pub const XKB_KEY_XF86Pictures = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff91, .hex);
pub const XKB_KEY_XF86Music = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff92, .hex);
pub const XKB_KEY_XF86Battery = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff93, .hex);
pub const XKB_KEY_XF86Bluetooth = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff94, .hex);
pub const XKB_KEY_XF86WLAN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff95, .hex);
pub const XKB_KEY_XF86UWB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff96, .hex);
pub const XKB_KEY_XF86AudioForward = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff97, .hex);
pub const XKB_KEY_XF86AudioRepeat = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff98, .hex);
pub const XKB_KEY_XF86AudioRandomPlay = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff99, .hex);
pub const XKB_KEY_XF86Subtitle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9a, .hex);
pub const XKB_KEY_XF86AudioCycleTrack = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9b, .hex);
pub const XKB_KEY_XF86CycleAngle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9c, .hex);
pub const XKB_KEY_XF86FrameBack = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9d, .hex);
pub const XKB_KEY_XF86FrameForward = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9e, .hex);
pub const XKB_KEY_XF86Time = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ff9f, .hex);
pub const XKB_KEY_XF86Select = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa0, .hex);
pub const XKB_KEY_XF86View = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa1, .hex);
pub const XKB_KEY_XF86TopMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa2, .hex);
pub const XKB_KEY_XF86Red = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa3, .hex);
pub const XKB_KEY_XF86Green = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa4, .hex);
pub const XKB_KEY_XF86Yellow = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa5, .hex);
pub const XKB_KEY_XF86Blue = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa6, .hex);
pub const XKB_KEY_XF86Suspend = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa7, .hex);
pub const XKB_KEY_XF86Hibernate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa8, .hex);
pub const XKB_KEY_XF86TouchpadToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffa9, .hex);
pub const XKB_KEY_XF86TouchpadOn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb0, .hex);
pub const XKB_KEY_XF86TouchpadOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb1, .hex);
pub const XKB_KEY_XF86AudioMicMute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb2, .hex);
pub const XKB_KEY_XF86Keyboard = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb3, .hex);
pub const XKB_KEY_XF86WWAN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb4, .hex);
pub const XKB_KEY_XF86RFKill = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb5, .hex);
pub const XKB_KEY_XF86AudioPreset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb6, .hex);
pub const XKB_KEY_XF86RotationLockToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb7, .hex);
pub const XKB_KEY_XF86FullScreen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008ffb8, .hex);
pub const XKB_KEY_XF86Switch_VT_1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe01, .hex);
pub const XKB_KEY_XF86Switch_VT_2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe02, .hex);
pub const XKB_KEY_XF86Switch_VT_3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe03, .hex);
pub const XKB_KEY_XF86Switch_VT_4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe04, .hex);
pub const XKB_KEY_XF86Switch_VT_5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe05, .hex);
pub const XKB_KEY_XF86Switch_VT_6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe06, .hex);
pub const XKB_KEY_XF86Switch_VT_7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe07, .hex);
pub const XKB_KEY_XF86Switch_VT_8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe08, .hex);
pub const XKB_KEY_XF86Switch_VT_9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe09, .hex);
pub const XKB_KEY_XF86Switch_VT_10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe0a, .hex);
pub const XKB_KEY_XF86Switch_VT_11 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe0b, .hex);
pub const XKB_KEY_XF86Switch_VT_12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe0c, .hex);
pub const XKB_KEY_XF86Ungrab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe20, .hex);
pub const XKB_KEY_XF86ClearGrab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe21, .hex);
pub const XKB_KEY_XF86Next_VMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe22, .hex);
pub const XKB_KEY_XF86Prev_VMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe23, .hex);
pub const XKB_KEY_XF86LogWindowTree = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe24, .hex);
pub const XKB_KEY_XF86LogGrabInfo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008fe25, .hex);
pub const XKB_KEY_XF86BrightnessAuto = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100810f4, .hex);
pub const XKB_KEY_XF86DisplayOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100810f5, .hex);
pub const XKB_KEY_XF86OK = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081160, .hex);
pub const XKB_KEY_XF86GoTo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081162, .hex);
pub const XKB_KEY_XF86Info = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081166, .hex);
pub const XKB_KEY_XF86VendorLogo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081168, .hex);
pub const XKB_KEY_XF86MediaSelectProgramGuide = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008116a, .hex);
pub const XKB_KEY_XF86MediaSelectHome = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008116e, .hex);
pub const XKB_KEY_XF86MediaLanguageMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081170, .hex);
pub const XKB_KEY_XF86MediaTitleMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081171, .hex);
pub const XKB_KEY_XF86AudioChannelMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081175, .hex);
pub const XKB_KEY_XF86AspectRatio = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081177, .hex);
pub const XKB_KEY_XF86MediaSelectPC = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081178, .hex);
pub const XKB_KEY_XF86MediaSelectTV = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081179, .hex);
pub const XKB_KEY_XF86MediaSelectCable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008117a, .hex);
pub const XKB_KEY_XF86MediaSelectVCR = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008117b, .hex);
pub const XKB_KEY_XF86MediaSelectVCRPlus = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008117c, .hex);
pub const XKB_KEY_XF86MediaSelectSatellite = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008117d, .hex);
pub const XKB_KEY_XF86MediaSelectTape = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081180, .hex);
pub const XKB_KEY_XF86MediaSelectRadio = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081181, .hex);
pub const XKB_KEY_XF86MediaSelectTuner = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081182, .hex);
pub const XKB_KEY_XF86MediaPlayer = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081183, .hex);
pub const XKB_KEY_XF86MediaSelectTeletext = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081184, .hex);
pub const XKB_KEY_XF86DVD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081185, .hex);
pub const XKB_KEY_XF86MediaSelectDVD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081185, .hex);
pub const XKB_KEY_XF86MediaSelectAuxiliary = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081186, .hex);
pub const XKB_KEY_XF86Audio = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081188, .hex);
pub const XKB_KEY_XF86ChannelUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081192, .hex);
pub const XKB_KEY_XF86ChannelDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081193, .hex);
pub const XKB_KEY_XF86MediaPlaySlow = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081199, .hex);
pub const XKB_KEY_XF86Break = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008119b, .hex);
pub const XKB_KEY_XF86NumberEntryMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008119d, .hex);
pub const XKB_KEY_XF86VideoPhone = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811a0, .hex);
pub const XKB_KEY_XF86ZoomReset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811a4, .hex);
pub const XKB_KEY_XF86Editor = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811a6, .hex);
pub const XKB_KEY_XF86GraphicsEditor = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811a8, .hex);
pub const XKB_KEY_XF86Presentation = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811a9, .hex);
pub const XKB_KEY_XF86Database = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811aa, .hex);
pub const XKB_KEY_XF86Voicemail = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811ac, .hex);
pub const XKB_KEY_XF86Addressbook = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811ad, .hex);
pub const XKB_KEY_XF86DisplayToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811af, .hex);
pub const XKB_KEY_XF86SpellCheck = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811b0, .hex);
pub const XKB_KEY_XF86ContextMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811b6, .hex);
pub const XKB_KEY_XF86MediaRepeat = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811b7, .hex);
pub const XKB_KEY_XF8610ChannelsUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811b8, .hex);
pub const XKB_KEY_XF8610ChannelsDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811b9, .hex);
pub const XKB_KEY_XF86Images = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811ba, .hex);
pub const XKB_KEY_XF86NotificationCenter = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811bc, .hex);
pub const XKB_KEY_XF86PickupPhone = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811bd, .hex);
pub const XKB_KEY_XF86HangupPhone = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811be, .hex);
pub const XKB_KEY_XF86Fn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811d0, .hex);
pub const XKB_KEY_XF86Fn_Esc = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811d1, .hex);
pub const XKB_KEY_XF86FnRightShift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100811e5, .hex);
pub const XKB_KEY_XF86Numeric0 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081200, .hex);
pub const XKB_KEY_XF86Numeric1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081201, .hex);
pub const XKB_KEY_XF86Numeric2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081202, .hex);
pub const XKB_KEY_XF86Numeric3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081203, .hex);
pub const XKB_KEY_XF86Numeric4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081204, .hex);
pub const XKB_KEY_XF86Numeric5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081205, .hex);
pub const XKB_KEY_XF86Numeric6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081206, .hex);
pub const XKB_KEY_XF86Numeric7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081207, .hex);
pub const XKB_KEY_XF86Numeric8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081208, .hex);
pub const XKB_KEY_XF86Numeric9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081209, .hex);
pub const XKB_KEY_XF86NumericStar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120a, .hex);
pub const XKB_KEY_XF86NumericPound = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120b, .hex);
pub const XKB_KEY_XF86NumericA = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120c, .hex);
pub const XKB_KEY_XF86NumericB = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120d, .hex);
pub const XKB_KEY_XF86NumericC = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120e, .hex);
pub const XKB_KEY_XF86NumericD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008120f, .hex);
pub const XKB_KEY_XF86CameraFocus = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081210, .hex);
pub const XKB_KEY_XF86WPSButton = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081211, .hex);
pub const XKB_KEY_XF86CameraZoomIn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081215, .hex);
pub const XKB_KEY_XF86CameraZoomOut = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081216, .hex);
pub const XKB_KEY_XF86CameraUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081217, .hex);
pub const XKB_KEY_XF86CameraDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081218, .hex);
pub const XKB_KEY_XF86CameraLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081219, .hex);
pub const XKB_KEY_XF86CameraRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008121a, .hex);
pub const XKB_KEY_XF86AttendantOn = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008121b, .hex);
pub const XKB_KEY_XF86AttendantOff = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008121c, .hex);
pub const XKB_KEY_XF86AttendantToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008121d, .hex);
pub const XKB_KEY_XF86LightsToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008121e, .hex);
pub const XKB_KEY_XF86ALSToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081230, .hex);
pub const XKB_KEY_XF86RefreshRateToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081232, .hex);
pub const XKB_KEY_XF86Buttonconfig = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081240, .hex);
pub const XKB_KEY_XF86Taskmanager = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081241, .hex);
pub const XKB_KEY_XF86Journal = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081242, .hex);
pub const XKB_KEY_XF86ControlPanel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081243, .hex);
pub const XKB_KEY_XF86AppSelect = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081244, .hex);
pub const XKB_KEY_XF86Screensaver = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081245, .hex);
pub const XKB_KEY_XF86VoiceCommand = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081246, .hex);
pub const XKB_KEY_XF86Assistant = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081247, .hex);
pub const XKB_KEY_XF86EmojiPicker = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081249, .hex);
pub const XKB_KEY_XF86Dictate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124a, .hex);
pub const XKB_KEY_XF86CameraAccessEnable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124b, .hex);
pub const XKB_KEY_XF86CameraAccessDisable = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124c, .hex);
pub const XKB_KEY_XF86CameraAccessToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124d, .hex);
pub const XKB_KEY_XF86Accessibility = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124e, .hex);
pub const XKB_KEY_XF86DoNotDisturb = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008124f, .hex);
pub const XKB_KEY_XF86BrightnessMin = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081250, .hex);
pub const XKB_KEY_XF86BrightnessMax = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081251, .hex);
pub const XKB_KEY_XF86KbdInputAssistPrev = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081260, .hex);
pub const XKB_KEY_XF86KbdInputAssistNext = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081261, .hex);
pub const XKB_KEY_XF86KbdInputAssistPrevgroup = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081262, .hex);
pub const XKB_KEY_XF86KbdInputAssistNextgroup = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081263, .hex);
pub const XKB_KEY_XF86KbdInputAssistAccept = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081264, .hex);
pub const XKB_KEY_XF86KbdInputAssistCancel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081265, .hex);
pub const XKB_KEY_XF86RightUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081266, .hex);
pub const XKB_KEY_XF86RightDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081267, .hex);
pub const XKB_KEY_XF86LeftUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081268, .hex);
pub const XKB_KEY_XF86LeftDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081269, .hex);
pub const XKB_KEY_XF86RootMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126a, .hex);
pub const XKB_KEY_XF86MediaTopMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126b, .hex);
pub const XKB_KEY_XF86Numeric11 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126c, .hex);
pub const XKB_KEY_XF86Numeric12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126d, .hex);
pub const XKB_KEY_XF86AudioDesc = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126e, .hex);
pub const XKB_KEY_XF863DMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008126f, .hex);
pub const XKB_KEY_XF86NextFavorite = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081270, .hex);
pub const XKB_KEY_XF86StopRecord = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081271, .hex);
pub const XKB_KEY_XF86PauseRecord = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081272, .hex);
pub const XKB_KEY_XF86VOD = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081273, .hex);
pub const XKB_KEY_XF86Unmute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081274, .hex);
pub const XKB_KEY_XF86FastReverse = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081275, .hex);
pub const XKB_KEY_XF86SlowReverse = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081276, .hex);
pub const XKB_KEY_XF86Data = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081277, .hex);
pub const XKB_KEY_XF86OnScreenKeyboard = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081278, .hex);
pub const XKB_KEY_XF86PrivacyScreenToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081279, .hex);
pub const XKB_KEY_XF86SelectiveScreenshot = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127a, .hex);
pub const XKB_KEY_XF86NextElement = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127b, .hex);
pub const XKB_KEY_XF86PreviousElement = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127c, .hex);
pub const XKB_KEY_XF86AutopilotEngageToggle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127d, .hex);
pub const XKB_KEY_XF86MarkWaypoint = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127e, .hex);
pub const XKB_KEY_XF86Sos = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008127f, .hex);
pub const XKB_KEY_XF86NavChart = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081280, .hex);
pub const XKB_KEY_XF86FishingChart = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081281, .hex);
pub const XKB_KEY_XF86SingleRangeRadar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081282, .hex);
pub const XKB_KEY_XF86DualRangeRadar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081283, .hex);
pub const XKB_KEY_XF86RadarOverlay = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081284, .hex);
pub const XKB_KEY_XF86TraditionalSonar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081285, .hex);
pub const XKB_KEY_XF86ClearvuSonar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081286, .hex);
pub const XKB_KEY_XF86SidevuSonar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081287, .hex);
pub const XKB_KEY_XF86NavInfo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081288, .hex);
pub const XKB_KEY_XF86Macro1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081290, .hex);
pub const XKB_KEY_XF86Macro2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081291, .hex);
pub const XKB_KEY_XF86Macro3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081292, .hex);
pub const XKB_KEY_XF86Macro4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081293, .hex);
pub const XKB_KEY_XF86Macro5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081294, .hex);
pub const XKB_KEY_XF86Macro6 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081295, .hex);
pub const XKB_KEY_XF86Macro7 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081296, .hex);
pub const XKB_KEY_XF86Macro8 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081297, .hex);
pub const XKB_KEY_XF86Macro9 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081298, .hex);
pub const XKB_KEY_XF86Macro10 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x10081299, .hex);
pub const XKB_KEY_XF86Macro11 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129a, .hex);
pub const XKB_KEY_XF86Macro12 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129b, .hex);
pub const XKB_KEY_XF86Macro13 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129c, .hex);
pub const XKB_KEY_XF86Macro14 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129d, .hex);
pub const XKB_KEY_XF86Macro15 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129e, .hex);
pub const XKB_KEY_XF86Macro16 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1008129f, .hex);
pub const XKB_KEY_XF86Macro17 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a0, .hex);
pub const XKB_KEY_XF86Macro18 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a1, .hex);
pub const XKB_KEY_XF86Macro19 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a2, .hex);
pub const XKB_KEY_XF86Macro20 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a3, .hex);
pub const XKB_KEY_XF86Macro21 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a4, .hex);
pub const XKB_KEY_XF86Macro22 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a5, .hex);
pub const XKB_KEY_XF86Macro23 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a6, .hex);
pub const XKB_KEY_XF86Macro24 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a7, .hex);
pub const XKB_KEY_XF86Macro25 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a8, .hex);
pub const XKB_KEY_XF86Macro26 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812a9, .hex);
pub const XKB_KEY_XF86Macro27 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812aa, .hex);
pub const XKB_KEY_XF86Macro28 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812ab, .hex);
pub const XKB_KEY_XF86Macro29 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812ac, .hex);
pub const XKB_KEY_XF86Macro30 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812ad, .hex);
pub const XKB_KEY_XF86MacroRecordStart = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b0, .hex);
pub const XKB_KEY_XF86MacroRecordStop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b1, .hex);
pub const XKB_KEY_XF86MacroPresetCycle = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b2, .hex);
pub const XKB_KEY_XF86MacroPreset1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b3, .hex);
pub const XKB_KEY_XF86MacroPreset2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b4, .hex);
pub const XKB_KEY_XF86MacroPreset3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b5, .hex);
pub const XKB_KEY_XF86KbdLcdMenu1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b8, .hex);
pub const XKB_KEY_XF86KbdLcdMenu2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812b9, .hex);
pub const XKB_KEY_XF86KbdLcdMenu3 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812ba, .hex);
pub const XKB_KEY_XF86KbdLcdMenu4 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812bb, .hex);
pub const XKB_KEY_XF86KbdLcdMenu5 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100812bc, .hex);
pub const XKB_KEY_SunFA_Grave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff00, .hex);
pub const XKB_KEY_SunFA_Circum = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff01, .hex);
pub const XKB_KEY_SunFA_Tilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff02, .hex);
pub const XKB_KEY_SunFA_Acute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff03, .hex);
pub const XKB_KEY_SunFA_Diaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff04, .hex);
pub const XKB_KEY_SunFA_Cedilla = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff05, .hex);
pub const XKB_KEY_SunF36 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff10, .hex);
pub const XKB_KEY_SunF37 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff11, .hex);
pub const XKB_KEY_SunSys_Req = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff60, .hex);
pub const XKB_KEY_SunPrint_Screen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff61, .hex);
pub const XKB_KEY_SunCompose = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff20, .hex);
pub const XKB_KEY_SunAltGraph = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff7e, .hex);
pub const XKB_KEY_SunPageUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff55, .hex);
pub const XKB_KEY_SunPageDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff56, .hex);
pub const XKB_KEY_SunUndo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff65, .hex);
pub const XKB_KEY_SunAgain = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff66, .hex);
pub const XKB_KEY_SunFind = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff68, .hex);
pub const XKB_KEY_SunStop = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x0000ff69, .hex);
pub const XKB_KEY_SunProps = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff70, .hex);
pub const XKB_KEY_SunFront = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff71, .hex);
pub const XKB_KEY_SunCopy = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff72, .hex);
pub const XKB_KEY_SunOpen = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff73, .hex);
pub const XKB_KEY_SunPaste = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff74, .hex);
pub const XKB_KEY_SunCut = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff75, .hex);
pub const XKB_KEY_SunPowerSwitch = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff76, .hex);
pub const XKB_KEY_SunAudioLowerVolume = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff77, .hex);
pub const XKB_KEY_SunAudioMute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff78, .hex);
pub const XKB_KEY_SunAudioRaiseVolume = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff79, .hex);
pub const XKB_KEY_SunVideoDegauss = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff7a, .hex);
pub const XKB_KEY_SunVideoLowerBrightness = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff7b, .hex);
pub const XKB_KEY_SunVideoRaiseBrightness = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff7c, .hex);
pub const XKB_KEY_SunPowerSwitchShift = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1005ff7d, .hex);
pub const XKB_KEY_Dring_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000feb0, .hex);
pub const XKB_KEY_Dcircumflex_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe5e, .hex);
pub const XKB_KEY_Dcedilla_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe2c, .hex);
pub const XKB_KEY_Dacute_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe27, .hex);
pub const XKB_KEY_Dgrave_accent = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe60, .hex);
pub const XKB_KEY_Dtilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe7e, .hex);
pub const XKB_KEY_Ddiaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000fe22, .hex);
pub const XKB_KEY_DRemove = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff00, .hex);
pub const XKB_KEY_hpClearLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6f, .hex);
pub const XKB_KEY_hpInsertLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff70, .hex);
pub const XKB_KEY_hpDeleteLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff71, .hex);
pub const XKB_KEY_hpInsertChar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff72, .hex);
pub const XKB_KEY_hpDeleteChar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff73, .hex);
pub const XKB_KEY_hpBackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff74, .hex);
pub const XKB_KEY_hpKP_BackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff75, .hex);
pub const XKB_KEY_hpModelock1 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff48, .hex);
pub const XKB_KEY_hpModelock2 = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff49, .hex);
pub const XKB_KEY_hpReset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6c, .hex);
pub const XKB_KEY_hpSystem = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6d, .hex);
pub const XKB_KEY_hpUser = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6e, .hex);
pub const XKB_KEY_hpmute_acute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000a8, .hex);
pub const XKB_KEY_hpmute_grave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000a9, .hex);
pub const XKB_KEY_hpmute_asciicircum = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000aa, .hex);
pub const XKB_KEY_hpmute_diaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ab, .hex);
pub const XKB_KEY_hpmute_asciitilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ac, .hex);
pub const XKB_KEY_hplira = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000af, .hex);
pub const XKB_KEY_hpguilder = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000be, .hex);
pub const XKB_KEY_hpYdiaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ee, .hex);
pub const XKB_KEY_hpIO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ee, .hex);
pub const XKB_KEY_hplongminus = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000f6, .hex);
pub const XKB_KEY_hpblock = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000fc, .hex);
pub const XKB_KEY_osfCopy = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff02, .hex);
pub const XKB_KEY_osfCut = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff03, .hex);
pub const XKB_KEY_osfPaste = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff04, .hex);
pub const XKB_KEY_osfBackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff07, .hex);
pub const XKB_KEY_osfBackSpace = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff08, .hex);
pub const XKB_KEY_osfClear = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff0b, .hex);
pub const XKB_KEY_osfEscape = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff1b, .hex);
pub const XKB_KEY_osfAddMode = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff31, .hex);
pub const XKB_KEY_osfPrimaryPaste = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff32, .hex);
pub const XKB_KEY_osfQuickPaste = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff33, .hex);
pub const XKB_KEY_osfPageLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff40, .hex);
pub const XKB_KEY_osfPageUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff41, .hex);
pub const XKB_KEY_osfPageDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff42, .hex);
pub const XKB_KEY_osfPageRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff43, .hex);
pub const XKB_KEY_osfActivate = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff44, .hex);
pub const XKB_KEY_osfMenuBar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff45, .hex);
pub const XKB_KEY_osfLeft = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff51, .hex);
pub const XKB_KEY_osfUp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff52, .hex);
pub const XKB_KEY_osfRight = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff53, .hex);
pub const XKB_KEY_osfDown = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff54, .hex);
pub const XKB_KEY_osfEndLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff57, .hex);
pub const XKB_KEY_osfBeginLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff58, .hex);
pub const XKB_KEY_osfEndData = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff59, .hex);
pub const XKB_KEY_osfBeginData = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff5a, .hex);
pub const XKB_KEY_osfPrevMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff5b, .hex);
pub const XKB_KEY_osfNextMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff5c, .hex);
pub const XKB_KEY_osfPrevField = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff5d, .hex);
pub const XKB_KEY_osfNextField = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff5e, .hex);
pub const XKB_KEY_osfSelect = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff60, .hex);
pub const XKB_KEY_osfInsert = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff63, .hex);
pub const XKB_KEY_osfUndo = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff65, .hex);
pub const XKB_KEY_osfMenu = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff67, .hex);
pub const XKB_KEY_osfCancel = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff69, .hex);
pub const XKB_KEY_osfHelp = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff6a, .hex);
pub const XKB_KEY_osfSelectAll = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff71, .hex);
pub const XKB_KEY_osfDeselectAll = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff72, .hex);
pub const XKB_KEY_osfReselect = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff73, .hex);
pub const XKB_KEY_osfExtend = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff74, .hex);
pub const XKB_KEY_osfRestore = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ff78, .hex);
pub const XKB_KEY_osfDelete = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1004ffff, .hex);
pub const XKB_KEY_Reset = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6c, .hex);
pub const XKB_KEY_System = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6d, .hex);
pub const XKB_KEY_User = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6e, .hex);
pub const XKB_KEY_ClearLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff6f, .hex);
pub const XKB_KEY_InsertLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff70, .hex);
pub const XKB_KEY_DeleteLine = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff71, .hex);
pub const XKB_KEY_InsertChar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff72, .hex);
pub const XKB_KEY_DeleteChar = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff73, .hex);
pub const XKB_KEY_BackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff74, .hex);
pub const XKB_KEY_KP_BackTab = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff75, .hex);
pub const XKB_KEY_Ext16bit_L = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff76, .hex);
pub const XKB_KEY_Ext16bit_R = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1000ff77, .hex);
pub const XKB_KEY_mute_acute = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000a8, .hex);
pub const XKB_KEY_mute_grave = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000a9, .hex);
pub const XKB_KEY_mute_asciicircum = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000aa, .hex);
pub const XKB_KEY_mute_diaeresis = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ab, .hex);
pub const XKB_KEY_mute_asciitilde = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ac, .hex);
pub const XKB_KEY_lira = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000af, .hex);
pub const XKB_KEY_guilder = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000be, .hex);
pub const XKB_KEY_IO = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000ee, .hex);
pub const XKB_KEY_longminus = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000f6, .hex);
pub const XKB_KEY_block = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x100000fc, .hex);
pub const XKB_EXPORT = @compileError("unable to translate macro: undefined identifier `visibility`");
// /usr/include/xkbcommon/xkbcommon.h:36:10
pub const XKB_KEYCODE_INVALID = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex);
pub const XKB_LAYOUT_INVALID = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex);
pub const XKB_LEVEL_INVALID = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex);
pub const XKB_MOD_INVALID = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex);
pub const XKB_LED_INVALID = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex);
pub const XKB_KEYCODE_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0xffffffff, .hex) - @as(c_int, 1);
pub const XKB_KEYSYM_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_int, 0x1fffffff, .hex);
pub inline fn xkb_keycode_is_legal_ext(key: anytype) @TypeOf(key <= XKB_KEYCODE_MAX) {
    _ = &key;
    return key <= XKB_KEYCODE_MAX;
}
pub inline fn xkb_keycode_is_legal_x11(key: anytype) @TypeOf((key >= @as(c_int, 8)) and (key <= @as(c_int, 255))) {
    _ = &key;
    return (key >= @as(c_int, 8)) and (key <= @as(c_int, 255));
}
pub const XKB_KEYMAP_USE_ORIGINAL_FORMAT = @import("std").zig.c_translation.cast(enum_xkb_keymap_format, -@as(c_int, 1));
pub const _XKBCOMMON_COMPAT_H = "";
pub const xkb_group_index_t = xkb_layout_index_t;
pub const xkb_group_mask_t = xkb_layout_mask_t;
pub const xkb_map_compile_flags = xkb_keymap_compile_flags;
pub const XKB_GROUP_INVALID = XKB_LAYOUT_INVALID;
pub const XKB_STATE_DEPRESSED = XKB_STATE_MODS_DEPRESSED | XKB_STATE_LAYOUT_DEPRESSED;
pub const XKB_STATE_LATCHED = XKB_STATE_MODS_LATCHED | XKB_STATE_LAYOUT_LATCHED;
pub const XKB_STATE_LOCKED = XKB_STATE_MODS_LOCKED | XKB_STATE_LAYOUT_LOCKED;
pub const XKB_STATE_EFFECTIVE = (((XKB_STATE_DEPRESSED | XKB_STATE_LATCHED) | XKB_STATE_LOCKED) | XKB_STATE_MODS_EFFECTIVE) | XKB_STATE_LAYOUT_EFFECTIVE;
pub inline fn xkb_map_new_from_names(context: anytype, names: anytype, flags: anytype) @TypeOf(xkb_keymap_new_from_names(context, names, flags)) {
    _ = &context;
    _ = &names;
    _ = &flags;
    return xkb_keymap_new_from_names(context, names, flags);
}
pub inline fn xkb_map_new_from_file(context: anytype, file: anytype, format: anytype, flags: anytype) @TypeOf(xkb_keymap_new_from_file(context, file, format, flags)) {
    _ = &context;
    _ = &file;
    _ = &format;
    _ = &flags;
    return xkb_keymap_new_from_file(context, file, format, flags);
}
pub inline fn xkb_map_new_from_string(context: anytype, string: anytype, format: anytype, flags: anytype) @TypeOf(xkb_keymap_new_from_string(context, string, format, flags)) {
    _ = &context;
    _ = &string;
    _ = &format;
    _ = &flags;
    return xkb_keymap_new_from_string(context, string, format, flags);
}
pub inline fn xkb_map_get_as_string(keymap: anytype) @TypeOf(xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1)) {
    _ = &keymap;
    return xkb_keymap_get_as_string(keymap, XKB_KEYMAP_FORMAT_TEXT_V1);
}
pub inline fn xkb_map_ref(keymap: anytype) @TypeOf(xkb_keymap_ref(keymap)) {
    _ = &keymap;
    return xkb_keymap_ref(keymap);
}
pub inline fn xkb_map_unref(keymap: anytype) @TypeOf(xkb_keymap_unref(keymap)) {
    _ = &keymap;
    return xkb_keymap_unref(keymap);
}
pub inline fn xkb_map_num_mods(keymap: anytype) @TypeOf(xkb_keymap_num_mods(keymap)) {
    _ = &keymap;
    return xkb_keymap_num_mods(keymap);
}
pub inline fn xkb_map_mod_get_name(keymap: anytype, idx: anytype) @TypeOf(xkb_keymap_mod_get_name(keymap, idx)) {
    _ = &keymap;
    _ = &idx;
    return xkb_keymap_mod_get_name(keymap, idx);
}
pub inline fn xkb_map_mod_get_index(keymap: anytype, str: anytype) @TypeOf(xkb_keymap_mod_get_index(keymap, str)) {
    _ = &keymap;
    _ = &str;
    return xkb_keymap_mod_get_index(keymap, str);
}
pub inline fn xkb_key_mod_index_is_consumed(state: anytype, key: anytype, mod: anytype) @TypeOf(xkb_state_mod_index_is_consumed(state, key, mod)) {
    _ = &state;
    _ = &key;
    _ = &mod;
    return xkb_state_mod_index_is_consumed(state, key, mod);
}
pub inline fn xkb_key_mod_mask_remove_consumed(state: anytype, key: anytype, modmask: anytype) @TypeOf(xkb_state_mod_mask_remove_consumed(state, key, modmask)) {
    _ = &state;
    _ = &key;
    _ = &modmask;
    return xkb_state_mod_mask_remove_consumed(state, key, modmask);
}
pub inline fn xkb_map_num_groups(keymap: anytype) @TypeOf(xkb_keymap_num_layouts(keymap)) {
    _ = &keymap;
    return xkb_keymap_num_layouts(keymap);
}
pub inline fn xkb_key_num_groups(keymap: anytype, key: anytype) @TypeOf(xkb_keymap_num_layouts_for_key(keymap, key)) {
    _ = &keymap;
    _ = &key;
    return xkb_keymap_num_layouts_for_key(keymap, key);
}
pub inline fn xkb_map_group_get_name(keymap: anytype, idx: anytype) @TypeOf(xkb_keymap_layout_get_name(keymap, idx)) {
    _ = &keymap;
    _ = &idx;
    return xkb_keymap_layout_get_name(keymap, idx);
}
pub inline fn xkb_map_group_get_index(keymap: anytype, str: anytype) @TypeOf(xkb_keymap_layout_get_index(keymap, str)) {
    _ = &keymap;
    _ = &str;
    return xkb_keymap_layout_get_index(keymap, str);
}
pub inline fn xkb_map_num_leds(keymap: anytype) @TypeOf(xkb_keymap_num_leds(keymap)) {
    _ = &keymap;
    return xkb_keymap_num_leds(keymap);
}
pub inline fn xkb_map_led_get_name(keymap: anytype, idx: anytype) @TypeOf(xkb_keymap_led_get_name(keymap, idx)) {
    _ = &keymap;
    _ = &idx;
    return xkb_keymap_led_get_name(keymap, idx);
}
pub inline fn xkb_map_led_get_index(keymap: anytype, str: anytype) @TypeOf(xkb_keymap_led_get_index(keymap, str)) {
    _ = &keymap;
    _ = &str;
    return xkb_keymap_led_get_index(keymap, str);
}
pub inline fn xkb_key_repeats(keymap: anytype, key: anytype) @TypeOf(xkb_keymap_key_repeats(keymap, key)) {
    _ = &keymap;
    _ = &key;
    return xkb_keymap_key_repeats(keymap, key);
}
pub inline fn xkb_key_get_syms(state: anytype, key: anytype, syms_out: anytype) @TypeOf(xkb_state_key_get_syms(state, key, syms_out)) {
    _ = &state;
    _ = &key;
    _ = &syms_out;
    return xkb_state_key_get_syms(state, key, syms_out);
}
pub inline fn xkb_state_group_name_is_active(state: anytype, name: anytype, @"type": anytype) @TypeOf(xkb_state_layout_name_is_active(state, name, @"type")) {
    _ = &state;
    _ = &name;
    _ = &@"type";
    return xkb_state_layout_name_is_active(state, name, @"type");
}
pub inline fn xkb_state_group_index_is_active(state: anytype, idx: anytype, @"type": anytype) @TypeOf(xkb_state_layout_index_is_active(state, idx, @"type")) {
    _ = &state;
    _ = &idx;
    _ = &@"type";
    return xkb_state_layout_index_is_active(state, idx, @"type");
}
pub inline fn xkb_state_serialize_group(state: anytype, component: anytype) @TypeOf(xkb_state_serialize_layout(state, component)) {
    _ = &state;
    _ = &component;
    return xkb_state_serialize_layout(state, component);
}
pub inline fn xkb_state_get_map(state: anytype) @TypeOf(xkb_state_get_keymap(state)) {
    _ = &state;
    return xkb_state_get_keymap(state);
}
pub const XKB_MAP_COMPILE_PLACEHOLDER = XKB_KEYMAP_COMPILE_NO_FLAGS;
pub const XKB_MAP_COMPILE_NO_FLAGS = XKB_KEYMAP_COMPILE_NO_FLAGS;
pub const _XKBCOMMON_X11_H = "";
pub const __XCB_H__ = "";
pub const _SYS_TYPES_H = @as(c_int, 1);
pub const __u_char_defined = "";
pub const __ino_t_defined = "";
pub const __dev_t_defined = "";
pub const __gid_t_defined = "";
pub const __mode_t_defined = "";
pub const __nlink_t_defined = "";
pub const __uid_t_defined = "";
pub const __pid_t_defined = "";
pub const __id_t_defined = "";
pub const __daddr_t_defined = "";
pub const __key_t_defined = "";
pub const __clock_t_defined = @as(c_int, 1);
pub const __clockid_t_defined = @as(c_int, 1);
pub const __time_t_defined = @as(c_int, 1);
pub const __timer_t_defined = @as(c_int, 1);
pub const __BIT_TYPES_DEFINED__ = @as(c_int, 1);
pub const _ENDIAN_H = @as(c_int, 1);
pub const _BITS_ENDIAN_H = @as(c_int, 1);
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __PDP_ENDIAN = @as(c_int, 3412);
pub const _BITS_ENDIANNESS_H = @as(c_int, 1);
pub const __BYTE_ORDER = __LITTLE_ENDIAN;
pub const __FLOAT_WORD_ORDER = __BYTE_ORDER;
pub inline fn __LONG_LONG_PAIR(HI: anytype, LO: anytype) @TypeOf(HI) {
    _ = &HI;
    _ = &LO;
    return blk: {
        _ = &LO;
        break :blk HI;
    };
}
pub const LITTLE_ENDIAN = __LITTLE_ENDIAN;
pub const BIG_ENDIAN = __BIG_ENDIAN;
pub const PDP_ENDIAN = __PDP_ENDIAN;
pub const BYTE_ORDER = __BYTE_ORDER;
pub const _BITS_BYTESWAP_H = @as(c_int, 1);
pub inline fn __bswap_constant_16(x: anytype) __uint16_t {
    _ = &x;
    return @import("std").zig.c_translation.cast(__uint16_t, ((x >> @as(c_int, 8)) & @as(c_int, 0xff)) | ((x & @as(c_int, 0xff)) << @as(c_int, 8)));
}
pub inline fn __bswap_constant_32(x: anytype) @TypeOf(((((x & @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24))) {
    _ = &x;
    return ((((x & @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0xff000000, .hex)) >> @as(c_int, 24)) | ((x & @import("std").zig.c_translation.promoteIntLiteral(c_uint, 0x00ff0000, .hex)) >> @as(c_int, 8))) | ((x & @as(c_uint, 0x0000ff00)) << @as(c_int, 8))) | ((x & @as(c_uint, 0x000000ff)) << @as(c_int, 24));
}
pub inline fn __bswap_constant_64(x: anytype) @TypeOf(((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56))) {
    _ = &x;
    return ((((((((x & @as(c_ulonglong, 0xff00000000000000)) >> @as(c_int, 56)) | ((x & @as(c_ulonglong, 0x00ff000000000000)) >> @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x0000ff0000000000)) >> @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000ff00000000)) >> @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x00000000ff000000)) << @as(c_int, 8))) | ((x & @as(c_ulonglong, 0x0000000000ff0000)) << @as(c_int, 24))) | ((x & @as(c_ulonglong, 0x000000000000ff00)) << @as(c_int, 40))) | ((x & @as(c_ulonglong, 0x00000000000000ff)) << @as(c_int, 56));
}
pub const _BITS_UINTN_IDENTITY_H = @as(c_int, 1);
pub inline fn htobe16(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn htole16(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn be16toh(x: anytype) @TypeOf(__bswap_16(x)) {
    _ = &x;
    return __bswap_16(x);
}
pub inline fn le16toh(x: anytype) @TypeOf(__uint16_identity(x)) {
    _ = &x;
    return __uint16_identity(x);
}
pub inline fn htobe32(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn htole32(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn be32toh(x: anytype) @TypeOf(__bswap_32(x)) {
    _ = &x;
    return __bswap_32(x);
}
pub inline fn le32toh(x: anytype) @TypeOf(__uint32_identity(x)) {
    _ = &x;
    return __uint32_identity(x);
}
pub inline fn htobe64(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn htole64(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub inline fn be64toh(x: anytype) @TypeOf(__bswap_64(x)) {
    _ = &x;
    return __bswap_64(x);
}
pub inline fn le64toh(x: anytype) @TypeOf(__uint64_identity(x)) {
    _ = &x;
    return __uint64_identity(x);
}
pub const _SYS_SELECT_H = @as(c_int, 1);
pub const __FD_ZERO = @compileError("unable to translate macro: undefined identifier `__i`");
// /usr/include/bits/select.h:25:9
pub const __FD_SET = @compileError("unable to translate C expr: expected ')' instead got '|='");
// /usr/include/bits/select.h:32:9
pub const __FD_CLR = @compileError("unable to translate C expr: expected ')' instead got '&='");
// /usr/include/bits/select.h:34:9
pub inline fn __FD_ISSET(d: anytype, s: anytype) @TypeOf((__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0)) {
    _ = &d;
    _ = &s;
    return (__FDS_BITS(s)[@as(usize, @intCast(__FD_ELT(d)))] & __FD_MASK(d)) != @as(c_int, 0);
}
pub const __sigset_t_defined = @as(c_int, 1);
pub const ____sigset_t_defined = "";
pub const _SIGSET_NWORDS = @import("std").zig.c_translation.MacroArithmetic.div(@as(c_int, 1024), @as(c_int, 8) * @import("std").zig.c_translation.sizeof(c_ulong));
pub const __timeval_defined = @as(c_int, 1);
pub const _STRUCT_TIMESPEC = @as(c_int, 1);
pub const __suseconds_t_defined = "";
pub const __NFDBITS = @as(c_int, 8) * @import("std").zig.c_translation.cast(c_int, @import("std").zig.c_translation.sizeof(__fd_mask));
pub inline fn __FD_ELT(d: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(d, __NFDBITS)) {
    _ = &d;
    return @import("std").zig.c_translation.MacroArithmetic.div(d, __NFDBITS);
}
pub inline fn __FD_MASK(d: anytype) __fd_mask {
    _ = &d;
    return @import("std").zig.c_translation.cast(__fd_mask, @as(c_ulong, 1) << @import("std").zig.c_translation.MacroArithmetic.rem(d, __NFDBITS));
}
pub inline fn __FDS_BITS(set: anytype) @TypeOf(set.*.__fds_bits) {
    _ = &set;
    return set.*.__fds_bits;
}
pub const FD_SETSIZE = __FD_SETSIZE;
pub const NFDBITS = __NFDBITS;
pub inline fn FD_SET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_SET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_SET(fd, fdsetp);
}
pub inline fn FD_CLR(fd: anytype, fdsetp: anytype) @TypeOf(__FD_CLR(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_CLR(fd, fdsetp);
}
pub inline fn FD_ISSET(fd: anytype, fdsetp: anytype) @TypeOf(__FD_ISSET(fd, fdsetp)) {
    _ = &fd;
    _ = &fdsetp;
    return __FD_ISSET(fd, fdsetp);
}
pub inline fn FD_ZERO(fdsetp: anytype) @TypeOf(__FD_ZERO(fdsetp)) {
    _ = &fdsetp;
    return __FD_ZERO(fdsetp);
}
pub const __blksize_t_defined = "";
pub const __blkcnt_t_defined = "";
pub const __fsblkcnt_t_defined = "";
pub const __fsfilcnt_t_defined = "";
pub const _BITS_PTHREADTYPES_COMMON_H = @as(c_int, 1);
pub const _THREAD_SHARED_TYPES_H = @as(c_int, 1);
pub const _BITS_PTHREADTYPES_ARCH_H = @as(c_int, 1);
pub const __SIZEOF_PTHREAD_ATTR_T = @as(c_int, 64);
pub const __SIZEOF_PTHREAD_MUTEX_T = @as(c_int, 48);
pub const __SIZEOF_PTHREAD_MUTEXATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_CONDATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_RWLOCK_T = @as(c_int, 56);
pub const __SIZEOF_PTHREAD_BARRIER_T = @as(c_int, 32);
pub const __SIZEOF_PTHREAD_BARRIERATTR_T = @as(c_int, 8);
pub const __SIZEOF_PTHREAD_COND_T = @as(c_int, 48);
pub const __SIZEOF_PTHREAD_RWLOCKATTR_T = @as(c_int, 8);
pub const __LOCK_ALIGNMENT = "";
pub const __ONCE_ALIGNMENT = "";
pub const _BITS_ATOMIC_WIDE_COUNTER_H = "";
pub const _THREAD_MUTEX_INTERNAL_H = @as(c_int, 1);
pub const __PTHREAD_MUTEX_HAVE_PREV = @as(c_int, 1);
pub const __PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'");
// /usr/include/bits/struct_mutex.h:77:10
pub const _RWLOCK_INTERNAL_H = "";
pub inline fn __PTHREAD_RWLOCK_INITIALIZER(__flags: anytype) @TypeOf(__flags) {
    _ = &__flags;
    return blk: {
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        _ = @as(c_int, 0);
        break :blk __flags;
    };
}
pub const __ONCE_FLAG_INIT = @compileError("unable to translate C expr: unexpected token '{'");
// /usr/include/bits/thread-shared-types.h:114:9
pub const __have_pthread_attr_t = @as(c_int, 1);
pub const _SYS_UIO_H = @as(c_int, 1);
pub const __iovec_defined = @as(c_int, 1);
pub const _BITS_UIO_LIM_H = @as(c_int, 1);
pub const __IOV_MAX = @as(c_int, 1024);
pub const UIO_MAXIOV = __IOV_MAX;
pub const _PTHREAD_H = @as(c_int, 1);
pub const _SCHED_H = @as(c_int, 1);
pub const _BITS_SCHED_H = @as(c_int, 1);
pub const SCHED_OTHER = @as(c_int, 0);
pub const SCHED_FIFO = @as(c_int, 1);
pub const SCHED_RR = @as(c_int, 2);
pub const _BITS_TYPES_STRUCT_SCHED_PARAM = @as(c_int, 1);
pub const _BITS_CPU_SET_H = @as(c_int, 1);
pub const __CPU_SETSIZE = @as(c_int, 1024);
pub const __NCPUBITS = @as(c_int, 8) * @import("std").zig.c_translation.sizeof(__cpu_mask);
pub inline fn __CPUELT(cpu: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div(cpu, __NCPUBITS)) {
    _ = &cpu;
    return @import("std").zig.c_translation.MacroArithmetic.div(cpu, __NCPUBITS);
}
pub inline fn __CPUMASK(cpu: anytype) @TypeOf(@import("std").zig.c_translation.cast(__cpu_mask, @as(c_int, 1)) << @import("std").zig.c_translation.MacroArithmetic.rem(cpu, __NCPUBITS)) {
    _ = &cpu;
    return @import("std").zig.c_translation.cast(__cpu_mask, @as(c_int, 1)) << @import("std").zig.c_translation.MacroArithmetic.rem(cpu, __NCPUBITS);
}
pub const __CPU_ZERO_S = @compileError("unable to translate C expr: unexpected token 'do'");
// /usr/include/bits/cpu-set.h:46:10
pub const __CPU_SET_S = @compileError("unable to translate macro: undefined identifier `__cpu`");
// /usr/include/bits/cpu-set.h:58:9
pub const __CPU_CLR_S = @compileError("unable to translate macro: undefined identifier `__cpu`");
// /usr/include/bits/cpu-set.h:65:9
pub const __CPU_ISSET_S = @compileError("unable to translate macro: undefined identifier `__cpu`");
// /usr/include/bits/cpu-set.h:72:9
pub inline fn __CPU_COUNT_S(setsize: anytype, cpusetp: anytype) @TypeOf(__sched_cpucount(setsize, cpusetp)) {
    _ = &setsize;
    _ = &cpusetp;
    return __sched_cpucount(setsize, cpusetp);
}
pub const __CPU_EQUAL_S = @compileError("unable to translate macro: undefined identifier `__builtin_memcmp`");
// /usr/include/bits/cpu-set.h:84:10
pub const __CPU_OP_S = @compileError("unable to translate macro: undefined identifier `__dest`");
// /usr/include/bits/cpu-set.h:99:9
pub inline fn __CPU_ALLOC_SIZE(count: anytype) @TypeOf(@import("std").zig.c_translation.MacroArithmetic.div((count + __NCPUBITS) - @as(c_int, 1), __NCPUBITS) * @import("std").zig.c_translation.sizeof(__cpu_mask)) {
    _ = &count;
    return @import("std").zig.c_translation.MacroArithmetic.div((count + __NCPUBITS) - @as(c_int, 1), __NCPUBITS) * @import("std").zig.c_translation.sizeof(__cpu_mask);
}
pub inline fn __CPU_ALLOC(count: anytype) @TypeOf(__sched_cpualloc(count)) {
    _ = &count;
    return __sched_cpualloc(count);
}
pub inline fn __CPU_FREE(cpuset: anytype) @TypeOf(__sched_cpufree(cpuset)) {
    _ = &cpuset;
    return __sched_cpufree(cpuset);
}
pub const __sched_priority = @compileError("unable to translate macro: undefined identifier `sched_priority`");
// /usr/include/sched.h:48:9
pub const _TIME_H = @as(c_int, 1);
pub const _BITS_TIME_H = @as(c_int, 1);
pub const CLOCKS_PER_SEC = @import("std").zig.c_translation.cast(__clock_t, @import("std").zig.c_translation.promoteIntLiteral(c_int, 1000000, .decimal));
pub const CLOCK_REALTIME = @as(c_int, 0);
pub const CLOCK_MONOTONIC = @as(c_int, 1);
pub const CLOCK_PROCESS_CPUTIME_ID = @as(c_int, 2);
pub const CLOCK_THREAD_CPUTIME_ID = @as(c_int, 3);
pub const CLOCK_MONOTONIC_RAW = @as(c_int, 4);
pub const CLOCK_REALTIME_COARSE = @as(c_int, 5);
pub const CLOCK_MONOTONIC_COARSE = @as(c_int, 6);
pub const CLOCK_BOOTTIME = @as(c_int, 7);
pub const CLOCK_REALTIME_ALARM = @as(c_int, 8);
pub const CLOCK_BOOTTIME_ALARM = @as(c_int, 9);
pub const CLOCK_TAI = @as(c_int, 11);
pub const TIMER_ABSTIME = @as(c_int, 1);
pub const __struct_tm_defined = @as(c_int, 1);
pub const __itimerspec_defined = @as(c_int, 1);
pub const _BITS_TYPES_LOCALE_T_H = @as(c_int, 1);
pub const _BITS_TYPES___LOCALE_T_H = @as(c_int, 1);
pub const TIME_UTC = @as(c_int, 1);
pub inline fn __isleap(year: anytype) @TypeOf((@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 4)) == @as(c_int, 0)) and ((@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 100)) != @as(c_int, 0)) or (@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 400)) == @as(c_int, 0)))) {
    _ = &year;
    return (@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 4)) == @as(c_int, 0)) and ((@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 100)) != @as(c_int, 0)) or (@import("std").zig.c_translation.MacroArithmetic.rem(year, @as(c_int, 400)) == @as(c_int, 0)));
}
pub const _BITS_SETJMP_H = @as(c_int, 1);
pub const __jmp_buf_tag_defined = @as(c_int, 1);
pub const PTHREAD_STACK_MIN = @import("std").zig.c_translation.promoteIntLiteral(c_int, 131072, .decimal);
pub const PTHREAD_MUTEX_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'");
// /usr/include/pthread.h:90:9
pub const PTHREAD_RWLOCK_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'");
// /usr/include/pthread.h:114:10
pub const PTHREAD_COND_INITIALIZER = @compileError("unable to translate C expr: unexpected token '{'");
// /usr/include/pthread.h:155:9
pub const PTHREAD_CANCELED = @import("std").zig.c_translation.cast(?*anyopaque, -@as(c_int, 1));
pub const PTHREAD_ONCE_INIT = @as(c_int, 0);
pub const PTHREAD_BARRIER_SERIAL_THREAD = -@as(c_int, 1);
pub const __cleanup_fct_attribute = "";
pub const pthread_cleanup_push = @compileError("unable to translate macro: undefined identifier `__cancel_buf`");
// /usr/include/pthread.h:681:10
pub const pthread_cleanup_pop = @compileError("unable to translate macro: undefined identifier `__cancel_buf`");
// /usr/include/pthread.h:702:10
pub inline fn __sigsetjmp_cancel(env: anytype, savemask: anytype) @TypeOf(__sigsetjmp(@import("std").zig.c_translation.cast([*c]struct___jmp_buf_tag, @import("std").zig.c_translation.cast(?*anyopaque, env)), savemask)) {
    _ = &env;
    _ = &savemask;
    return __sigsetjmp(@import("std").zig.c_translation.cast([*c]struct___jmp_buf_tag, @import("std").zig.c_translation.cast(?*anyopaque, env)), savemask);
}
pub const XCB_PACKED = @compileError("unable to translate macro: undefined identifier `__packed__`");
// /usr/include/xcb/xcb.h:55:9
pub const X_PROTOCOL = @as(c_int, 11);
pub const X_PROTOCOL_REVISION = @as(c_int, 0);
pub const X_TCP_PORT = @as(c_int, 6000);
pub const XCB_CONN_ERROR = @as(c_int, 1);
pub const XCB_CONN_CLOSED_EXT_NOTSUPPORTED = @as(c_int, 2);
pub const XCB_CONN_CLOSED_MEM_INSUFFICIENT = @as(c_int, 3);
pub const XCB_CONN_CLOSED_REQ_LEN_EXCEED = @as(c_int, 4);
pub const XCB_CONN_CLOSED_PARSE_ERR = @as(c_int, 5);
pub const XCB_CONN_CLOSED_INVALID_SCREEN = @as(c_int, 6);
pub const XCB_CONN_CLOSED_FDPASSING_FAILED = @as(c_int, 7);
pub inline fn XCB_TYPE_PAD(T: anytype, I: anytype) @TypeOf(-I & (if (@import("std").zig.c_translation.sizeof(T) > @as(c_int, 4)) @as(c_int, 3) else @import("std").zig.c_translation.sizeof(T) - @as(c_int, 1))) {
    _ = &T;
    _ = &I;
    return -I & (if (@import("std").zig.c_translation.sizeof(T) > @as(c_int, 4)) @as(c_int, 3) else @import("std").zig.c_translation.sizeof(T) - @as(c_int, 1));
}
pub const __XPROTO_H = "";
pub const XCB_KEY_PRESS = @as(c_int, 2);
pub const XCB_KEY_RELEASE = @as(c_int, 3);
pub const XCB_BUTTON_PRESS = @as(c_int, 4);
pub const XCB_BUTTON_RELEASE = @as(c_int, 5);
pub const XCB_MOTION_NOTIFY = @as(c_int, 6);
pub const XCB_ENTER_NOTIFY = @as(c_int, 7);
pub const XCB_LEAVE_NOTIFY = @as(c_int, 8);
pub const XCB_FOCUS_IN = @as(c_int, 9);
pub const XCB_FOCUS_OUT = @as(c_int, 10);
pub const XCB_KEYMAP_NOTIFY = @as(c_int, 11);
pub const XCB_EXPOSE = @as(c_int, 12);
pub const XCB_GRAPHICS_EXPOSURE = @as(c_int, 13);
pub const XCB_NO_EXPOSURE = @as(c_int, 14);
pub const XCB_VISIBILITY_NOTIFY = @as(c_int, 15);
pub const XCB_CREATE_NOTIFY = @as(c_int, 16);
pub const XCB_DESTROY_NOTIFY = @as(c_int, 17);
pub const XCB_UNMAP_NOTIFY = @as(c_int, 18);
pub const XCB_MAP_NOTIFY = @as(c_int, 19);
pub const XCB_MAP_REQUEST = @as(c_int, 20);
pub const XCB_REPARENT_NOTIFY = @as(c_int, 21);
pub const XCB_CONFIGURE_NOTIFY = @as(c_int, 22);
pub const XCB_CONFIGURE_REQUEST = @as(c_int, 23);
pub const XCB_GRAVITY_NOTIFY = @as(c_int, 24);
pub const XCB_RESIZE_REQUEST = @as(c_int, 25);
pub const XCB_CIRCULATE_NOTIFY = @as(c_int, 26);
pub const XCB_CIRCULATE_REQUEST = @as(c_int, 27);
pub const XCB_PROPERTY_NOTIFY = @as(c_int, 28);
pub const XCB_SELECTION_CLEAR = @as(c_int, 29);
pub const XCB_SELECTION_REQUEST = @as(c_int, 30);
pub const XCB_SELECTION_NOTIFY = @as(c_int, 31);
pub const XCB_COLORMAP_NOTIFY = @as(c_int, 32);
pub const XCB_CLIENT_MESSAGE = @as(c_int, 33);
pub const XCB_MAPPING_NOTIFY = @as(c_int, 34);
pub const XCB_GE_GENERIC = @as(c_int, 35);
pub const XCB_REQUEST = @as(c_int, 1);
pub const XCB_VALUE = @as(c_int, 2);
pub const XCB_WINDOW = @as(c_int, 3);
pub const XCB_PIXMAP = @as(c_int, 4);
pub const XCB_ATOM = @as(c_int, 5);
pub const XCB_CURSOR = @as(c_int, 6);
pub const XCB_FONT = @as(c_int, 7);
pub const XCB_MATCH = @as(c_int, 8);
pub const XCB_DRAWABLE = @as(c_int, 9);
pub const XCB_ACCESS = @as(c_int, 10);
pub const XCB_ALLOC = @as(c_int, 11);
pub const XCB_COLORMAP = @as(c_int, 12);
pub const XCB_G_CONTEXT = @as(c_int, 13);
pub const XCB_ID_CHOICE = @as(c_int, 14);
pub const XCB_NAME = @as(c_int, 15);
pub const XCB_LENGTH = @as(c_int, 16);
pub const XCB_IMPLEMENTATION = @as(c_int, 17);
pub const XCB_CREATE_WINDOW = @as(c_int, 1);
pub const XCB_CHANGE_WINDOW_ATTRIBUTES = @as(c_int, 2);
pub const XCB_GET_WINDOW_ATTRIBUTES = @as(c_int, 3);
pub const XCB_DESTROY_WINDOW = @as(c_int, 4);
pub const XCB_DESTROY_SUBWINDOWS = @as(c_int, 5);
pub const XCB_CHANGE_SAVE_SET = @as(c_int, 6);
pub const XCB_REPARENT_WINDOW = @as(c_int, 7);
pub const XCB_MAP_WINDOW = @as(c_int, 8);
pub const XCB_MAP_SUBWINDOWS = @as(c_int, 9);
pub const XCB_UNMAP_WINDOW = @as(c_int, 10);
pub const XCB_UNMAP_SUBWINDOWS = @as(c_int, 11);
pub const XCB_CONFIGURE_WINDOW = @as(c_int, 12);
pub const XCB_CIRCULATE_WINDOW = @as(c_int, 13);
pub const XCB_GET_GEOMETRY = @as(c_int, 14);
pub const XCB_QUERY_TREE = @as(c_int, 15);
pub const XCB_INTERN_ATOM = @as(c_int, 16);
pub const XCB_GET_ATOM_NAME = @as(c_int, 17);
pub const XCB_CHANGE_PROPERTY = @as(c_int, 18);
pub const XCB_DELETE_PROPERTY = @as(c_int, 19);
pub const XCB_GET_PROPERTY = @as(c_int, 20);
pub const XCB_LIST_PROPERTIES = @as(c_int, 21);
pub const XCB_SET_SELECTION_OWNER = @as(c_int, 22);
pub const XCB_GET_SELECTION_OWNER = @as(c_int, 23);
pub const XCB_CONVERT_SELECTION = @as(c_int, 24);
pub const XCB_SEND_EVENT = @as(c_int, 25);
pub const XCB_GRAB_POINTER = @as(c_int, 26);
pub const XCB_UNGRAB_POINTER = @as(c_int, 27);
pub const XCB_GRAB_BUTTON = @as(c_int, 28);
pub const XCB_UNGRAB_BUTTON = @as(c_int, 29);
pub const XCB_CHANGE_ACTIVE_POINTER_GRAB = @as(c_int, 30);
pub const XCB_GRAB_KEYBOARD = @as(c_int, 31);
pub const XCB_UNGRAB_KEYBOARD = @as(c_int, 32);
pub const XCB_GRAB_KEY = @as(c_int, 33);
pub const XCB_UNGRAB_KEY = @as(c_int, 34);
pub const XCB_ALLOW_EVENTS = @as(c_int, 35);
pub const XCB_GRAB_SERVER = @as(c_int, 36);
pub const XCB_UNGRAB_SERVER = @as(c_int, 37);
pub const XCB_QUERY_POINTER = @as(c_int, 38);
pub const XCB_GET_MOTION_EVENTS = @as(c_int, 39);
pub const XCB_TRANSLATE_COORDINATES = @as(c_int, 40);
pub const XCB_WARP_POINTER = @as(c_int, 41);
pub const XCB_SET_INPUT_FOCUS = @as(c_int, 42);
pub const XCB_GET_INPUT_FOCUS = @as(c_int, 43);
pub const XCB_QUERY_KEYMAP = @as(c_int, 44);
pub const XCB_OPEN_FONT = @as(c_int, 45);
pub const XCB_CLOSE_FONT = @as(c_int, 46);
pub const XCB_QUERY_FONT = @as(c_int, 47);
pub const XCB_QUERY_TEXT_EXTENTS = @as(c_int, 48);
pub const XCB_LIST_FONTS = @as(c_int, 49);
pub const XCB_LIST_FONTS_WITH_INFO = @as(c_int, 50);
pub const XCB_SET_FONT_PATH = @as(c_int, 51);
pub const XCB_GET_FONT_PATH = @as(c_int, 52);
pub const XCB_CREATE_PIXMAP = @as(c_int, 53);
pub const XCB_FREE_PIXMAP = @as(c_int, 54);
pub const XCB_CREATE_GC = @as(c_int, 55);
pub const XCB_CHANGE_GC = @as(c_int, 56);
pub const XCB_COPY_GC = @as(c_int, 57);
pub const XCB_SET_DASHES = @as(c_int, 58);
pub const XCB_SET_CLIP_RECTANGLES = @as(c_int, 59);
pub const XCB_FREE_GC = @as(c_int, 60);
pub const XCB_CLEAR_AREA = @as(c_int, 61);
pub const XCB_COPY_AREA = @as(c_int, 62);
pub const XCB_COPY_PLANE = @as(c_int, 63);
pub const XCB_POLY_POINT = @as(c_int, 64);
pub const XCB_POLY_LINE = @as(c_int, 65);
pub const XCB_POLY_SEGMENT = @as(c_int, 66);
pub const XCB_POLY_RECTANGLE = @as(c_int, 67);
pub const XCB_POLY_ARC = @as(c_int, 68);
pub const XCB_FILL_POLY = @as(c_int, 69);
pub const XCB_POLY_FILL_RECTANGLE = @as(c_int, 70);
pub const XCB_POLY_FILL_ARC = @as(c_int, 71);
pub const XCB_PUT_IMAGE = @as(c_int, 72);
pub const XCB_GET_IMAGE = @as(c_int, 73);
pub const XCB_POLY_TEXT_8 = @as(c_int, 74);
pub const XCB_POLY_TEXT_16 = @as(c_int, 75);
pub const XCB_IMAGE_TEXT_8 = @as(c_int, 76);
pub const XCB_IMAGE_TEXT_16 = @as(c_int, 77);
pub const XCB_CREATE_COLORMAP = @as(c_int, 78);
pub const XCB_FREE_COLORMAP = @as(c_int, 79);
pub const XCB_COPY_COLORMAP_AND_FREE = @as(c_int, 80);
pub const XCB_INSTALL_COLORMAP = @as(c_int, 81);
pub const XCB_UNINSTALL_COLORMAP = @as(c_int, 82);
pub const XCB_LIST_INSTALLED_COLORMAPS = @as(c_int, 83);
pub const XCB_ALLOC_COLOR = @as(c_int, 84);
pub const XCB_ALLOC_NAMED_COLOR = @as(c_int, 85);
pub const XCB_ALLOC_COLOR_CELLS = @as(c_int, 86);
pub const XCB_ALLOC_COLOR_PLANES = @as(c_int, 87);
pub const XCB_FREE_COLORS = @as(c_int, 88);
pub const XCB_STORE_COLORS = @as(c_int, 89);
pub const XCB_STORE_NAMED_COLOR = @as(c_int, 90);
pub const XCB_QUERY_COLORS = @as(c_int, 91);
pub const XCB_LOOKUP_COLOR = @as(c_int, 92);
pub const XCB_CREATE_CURSOR = @as(c_int, 93);
pub const XCB_CREATE_GLYPH_CURSOR = @as(c_int, 94);
pub const XCB_FREE_CURSOR = @as(c_int, 95);
pub const XCB_RECOLOR_CURSOR = @as(c_int, 96);
pub const XCB_QUERY_BEST_SIZE = @as(c_int, 97);
pub const XCB_QUERY_EXTENSION = @as(c_int, 98);
pub const XCB_LIST_EXTENSIONS = @as(c_int, 99);
pub const XCB_CHANGE_KEYBOARD_MAPPING = @as(c_int, 100);
pub const XCB_GET_KEYBOARD_MAPPING = @as(c_int, 101);
pub const XCB_CHANGE_KEYBOARD_CONTROL = @as(c_int, 102);
pub const XCB_GET_KEYBOARD_CONTROL = @as(c_int, 103);
pub const XCB_BELL = @as(c_int, 104);
pub const XCB_CHANGE_POINTER_CONTROL = @as(c_int, 105);
pub const XCB_GET_POINTER_CONTROL = @as(c_int, 106);
pub const XCB_SET_SCREEN_SAVER = @as(c_int, 107);
pub const XCB_GET_SCREEN_SAVER = @as(c_int, 108);
pub const XCB_CHANGE_HOSTS = @as(c_int, 109);
pub const XCB_LIST_HOSTS = @as(c_int, 110);
pub const XCB_SET_ACCESS_CONTROL = @as(c_int, 111);
pub const XCB_SET_CLOSE_DOWN_MODE = @as(c_int, 112);
pub const XCB_KILL_CLIENT = @as(c_int, 113);
pub const XCB_ROTATE_PROPERTIES = @as(c_int, 114);
pub const XCB_FORCE_SCREEN_SAVER = @as(c_int, 115);
pub const XCB_SET_POINTER_MAPPING = @as(c_int, 116);
pub const XCB_GET_POINTER_MAPPING = @as(c_int, 117);
pub const XCB_SET_MODIFIER_MAPPING = @as(c_int, 118);
pub const XCB_GET_MODIFIER_MAPPING = @as(c_int, 119);
pub const XCB_NO_OPERATION = @as(c_int, 127);
pub const XCB_NONE = @as(c_long, 0);
pub const XCB_COPY_FROM_PARENT = @as(c_long, 0);
pub const XCB_CURRENT_TIME = @as(c_long, 0);
pub const XCB_NO_SYMBOL = @as(c_long, 0);
pub const XKB_X11_MIN_MAJOR_XKB_VERSION = @as(c_int, 1);
pub const XKB_X11_MIN_MINOR_XKB_VERSION = @as(c_int, 0);
pub const _XKBCOMMON_COMPOSE_H = "";
pub const _G_fpos_t = struct__G_fpos_t;
pub const _G_fpos64_t = struct__G_fpos64_t;
pub const _IO_marker = struct__IO_marker;
pub const _IO_FILE = struct__IO_FILE;
pub const _IO_codecvt = struct__IO_codecvt;
pub const _IO_wide_data = struct__IO_wide_data;
pub const _IO_cookie_io_functions_t = struct__IO_cookie_io_functions_t;
pub const xkb_context = struct_xkb_context;
pub const xkb_keymap = struct_xkb_keymap;
pub const xkb_state = struct_xkb_state;
pub const xkb_rmlvo_builder = struct_xkb_rmlvo_builder;
pub const xkb_rmlvo_builder_flags = enum_xkb_rmlvo_builder_flags;
pub const xkb_rule_names = struct_xkb_rule_names;
pub const xkb_component_names = struct_xkb_component_names;
pub const xkb_keysym_flags = enum_xkb_keysym_flags;
pub const xkb_context_flags = enum_xkb_context_flags;
pub const xkb_log_level = enum_xkb_log_level;
pub const xkb_keymap_compile_flags = enum_xkb_keymap_compile_flags;
pub const xkb_keymap_format = enum_xkb_keymap_format;
pub const xkb_key_direction = enum_xkb_key_direction;
pub const xkb_state_component = enum_xkb_state_component;
pub const xkb_state_match = enum_xkb_state_match;
pub const xkb_consumed_mode = enum_xkb_consumed_mode;
pub const timeval = struct_timeval;
pub const timespec = struct_timespec;
pub const __pthread_internal_list = struct___pthread_internal_list;
pub const __pthread_internal_slist = struct___pthread_internal_slist;
pub const __pthread_mutex_s = struct___pthread_mutex_s;
pub const __pthread_rwlock_arch_t = struct___pthread_rwlock_arch_t;
pub const __pthread_cond_s = struct___pthread_cond_s;
pub const iovec = struct_iovec;
pub const sched_param = struct_sched_param;
pub const tm = struct_tm;
pub const itimerspec = struct_itimerspec;
pub const sigevent = struct_sigevent;
pub const __locale_struct = struct___locale_struct;
pub const __jmp_buf_tag = struct___jmp_buf_tag;
pub const _pthread_cleanup_buffer = struct__pthread_cleanup_buffer;
pub const __cancel_jmp_buf_tag = struct___cancel_jmp_buf_tag;
pub const __pthread_cleanup_frame = struct___pthread_cleanup_frame;
pub const xcb_special_event = struct_xcb_special_event;
pub const xkb_x11_setup_xkb_extension_flags = enum_xkb_x11_setup_xkb_extension_flags;
pub const xkb_compose_table = struct_xkb_compose_table;
pub const xkb_compose_state = struct_xkb_compose_state;
pub const xkb_compose_compile_flags = enum_xkb_compose_compile_flags;
pub const xkb_compose_format = enum_xkb_compose_format;
pub const xkb_compose_table_entry = struct_xkb_compose_table_entry;
pub const xkb_compose_table_iterator = struct_xkb_compose_table_iterator;
pub const xkb_compose_state_flags = enum_xkb_compose_state_flags;
pub const xkb_compose_status = enum_xkb_compose_status;
pub const xkb_compose_feed_result = enum_xkb_compose_feed_result;
