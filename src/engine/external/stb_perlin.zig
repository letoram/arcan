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
pub export fn stb_perlin_noise3(arg_x: f32, arg_y: f32, arg_z: f32, arg_x_wrap: c_int, arg_y_wrap: c_int, arg_z_wrap: c_int) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var x_wrap = arg_x_wrap;
    _ = &x_wrap;
    var y_wrap = arg_y_wrap;
    _ = &y_wrap;
    var z_wrap = arg_z_wrap;
    _ = &z_wrap;
    return stb_perlin_noise3_internal(x, y, z, x_wrap, y_wrap, z_wrap, @as(u8, @bitCast(@as(i8, @truncate(@as(c_int, 0))))));
}
pub export fn stb_perlin_noise3_seed(arg_x: f32, arg_y: f32, arg_z: f32, arg_x_wrap: c_int, arg_y_wrap: c_int, arg_z_wrap: c_int, arg_seed: c_int) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var x_wrap = arg_x_wrap;
    _ = &x_wrap;
    var y_wrap = arg_y_wrap;
    _ = &y_wrap;
    var z_wrap = arg_z_wrap;
    _ = &z_wrap;
    var seed = arg_seed;
    _ = &seed;
    return stb_perlin_noise3_internal(x, y, z, x_wrap, y_wrap, z_wrap, @as(u8, @bitCast(@as(i8, @truncate(seed)))));
}
pub export fn stb_perlin_ridge_noise3(arg_x: f32, arg_y: f32, arg_z: f32, arg_lacunarity: f32, arg_gain: f32, arg_offset: f32, arg_octaves: c_int) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var lacunarity = arg_lacunarity;
    _ = &lacunarity;
    var gain = arg_gain;
    _ = &gain;
    var offset = arg_offset;
    _ = &offset;
    var octaves = arg_octaves;
    _ = &octaves;
    var i: c_int = undefined;
    _ = &i;
    var frequency: f32 = 1.0;
    _ = &frequency;
    var prev: f32 = 1.0;
    _ = &prev;
    var amplitude: f32 = 0.5;
    _ = &amplitude;
    var sum: f32 = 0.0;
    _ = &sum;
    {
        i = 0;
        while (i < octaves) : (i += 1) {
            var r: f32 = stb_perlin_noise3_internal(x * frequency, y * frequency, z * frequency, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(u8, @bitCast(@as(i8, @truncate(i)))));
            _ = &r;
            r = offset - @as(f32, @floatCast(fabs(@as(f64, @floatCast(r)))));
            r = r * r;
            sum += (r * amplitude) * prev;
            prev = r;
            frequency *= lacunarity;
            amplitude *= gain;
        }
    }
    return sum;
}
pub export fn stb_perlin_fbm_noise3(arg_x: f32, arg_y: f32, arg_z: f32, arg_lacunarity: f32, arg_gain: f32, arg_octaves: c_int) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var lacunarity = arg_lacunarity;
    _ = &lacunarity;
    var gain = arg_gain;
    _ = &gain;
    var octaves = arg_octaves;
    _ = &octaves;
    var i: c_int = undefined;
    _ = &i;
    var frequency: f32 = 1.0;
    _ = &frequency;
    var amplitude: f32 = 1.0;
    _ = &amplitude;
    var sum: f32 = 0.0;
    _ = &sum;
    {
        i = 0;
        while (i < octaves) : (i += 1) {
            sum += stb_perlin_noise3_internal(x * frequency, y * frequency, z * frequency, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(u8, @bitCast(@as(i8, @truncate(i))))) * amplitude;
            frequency *= lacunarity;
            amplitude *= gain;
        }
    }
    return sum;
}
pub export fn stb_perlin_turbulence_noise3(arg_x: f32, arg_y: f32, arg_z: f32, arg_lacunarity: f32, arg_gain: f32, arg_octaves: c_int) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var lacunarity = arg_lacunarity;
    _ = &lacunarity;
    var gain = arg_gain;
    _ = &gain;
    var octaves = arg_octaves;
    _ = &octaves;
    var i: c_int = undefined;
    _ = &i;
    var frequency: f32 = 1.0;
    _ = &frequency;
    var amplitude: f32 = 1.0;
    _ = &amplitude;
    var sum: f32 = 0.0;
    _ = &sum;
    {
        i = 0;
        while (i < octaves) : (i += 1) {
            var r: f32 = stb_perlin_noise3_internal(x * frequency, y * frequency, z * frequency, @as(c_int, 0), @as(c_int, 0), @as(c_int, 0), @as(u8, @bitCast(@as(i8, @truncate(i))))) * amplitude;
            _ = &r;
            sum += @as(f32, @floatCast(fabs(@as(f64, @floatCast(r)))));
            frequency *= lacunarity;
            amplitude *= gain;
        }
    }
    return sum;
}
pub export fn stb_perlin_noise3_wrap_nonpow2(arg_x: f32, arg_y: f32, arg_z: f32, arg_x_wrap: c_int, arg_y_wrap: c_int, arg_z_wrap: c_int, arg_seed: u8) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var x_wrap = arg_x_wrap;
    _ = &x_wrap;
    var y_wrap = arg_y_wrap;
    _ = &y_wrap;
    var z_wrap = arg_z_wrap;
    _ = &z_wrap;
    var seed = arg_seed;
    _ = &seed;
    var u: f32 = undefined;
    _ = &u;
    var v: f32 = undefined;
    _ = &v;
    var w: f32 = undefined;
    _ = &w;
    var n000: f32 = undefined;
    _ = &n000;
    var n001: f32 = undefined;
    _ = &n001;
    var n010: f32 = undefined;
    _ = &n010;
    var n011: f32 = undefined;
    _ = &n011;
    var n100: f32 = undefined;
    _ = &n100;
    var n101: f32 = undefined;
    _ = &n101;
    var n110: f32 = undefined;
    _ = &n110;
    var n111: f32 = undefined;
    _ = &n111;
    var n00: f32 = undefined;
    _ = &n00;
    var n01: f32 = undefined;
    _ = &n01;
    var n10: f32 = undefined;
    _ = &n10;
    var n11: f32 = undefined;
    _ = &n11;
    var n0: f32 = undefined;
    _ = &n0;
    var n1: f32 = undefined;
    _ = &n1;
    var px: c_int = stb__perlin_fastfloor(x);
    _ = &px;
    var py: c_int = stb__perlin_fastfloor(y);
    _ = &py;
    var pz: c_int = stb__perlin_fastfloor(z);
    _ = &pz;
    var x_wrap2: c_int = if (x_wrap != 0) x_wrap else @as(c_int, 256);
    _ = &x_wrap2;
    var y_wrap2: c_int = if (y_wrap != 0) y_wrap else @as(c_int, 256);
    _ = &y_wrap2;
    var z_wrap2: c_int = if (z_wrap != 0) z_wrap else @as(c_int, 256);
    _ = &z_wrap2;
    var x0: c_int = @import("std").zig.c_translation.signedRemainder(px, x_wrap2);
    _ = &x0;
    var x1: c_int = undefined;
    _ = &x1;
    var y0_1: c_int = @import("std").zig.c_translation.signedRemainder(py, y_wrap2);
    _ = &y0_1;
    var y1_2: c_int = undefined;
    _ = &y1_2;
    var z0: c_int = @import("std").zig.c_translation.signedRemainder(pz, z_wrap2);
    _ = &z0;
    var z1: c_int = undefined;
    _ = &z1;
    var r0: c_int = undefined;
    _ = &r0;
    var r1: c_int = undefined;
    _ = &r1;
    var r00: c_int = undefined;
    _ = &r00;
    var r01: c_int = undefined;
    _ = &r01;
    var r10: c_int = undefined;
    _ = &r10;
    var r11: c_int = undefined;
    _ = &r11;
    if (x0 < @as(c_int, 0)) {
        x0 += x_wrap2;
    }
    if (y0_1 < @as(c_int, 0)) {
        y0_1 += y_wrap2;
    }
    if (z0 < @as(c_int, 0)) {
        z0 += z_wrap2;
    }
    x1 = @import("std").zig.c_translation.signedRemainder(x0 + @as(c_int, 1), x_wrap2);
    y1_2 = @import("std").zig.c_translation.signedRemainder(y0_1 + @as(c_int, 1), y_wrap2);
    z1 = @import("std").zig.c_translation.signedRemainder(z0 + @as(c_int, 1), z_wrap2);
    x -= @as(f32, @floatFromInt(px));
    u = ((((((x * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * x) + @as(f32, @floatFromInt(@as(c_int, 10)))) * x) * x) * x;
    y -= @as(f32, @floatFromInt(py));
    v = ((((((y * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * y) + @as(f32, @floatFromInt(@as(c_int, 10)))) * y) * y) * y;
    z -= @as(f32, @floatFromInt(pz));
    w = ((((((z * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * z) + @as(f32, @floatFromInt(@as(c_int, 10)))) * z) * z) * z;
    r0 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(x0))])));
    r0 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r0 + @as(c_int, @bitCast(@as(c_uint, seed)))))])));
    r1 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(x1))])));
    r1 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r1 + @as(c_int, @bitCast(@as(c_uint, seed)))))])));
    r00 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r0 + y0_1))])));
    r01 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r0 + y1_2))])));
    r10 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r1 + y0_1))])));
    r11 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r1 + y1_2))])));
    n000 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r00 + z0))]))), x, y, z);
    n001 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r00 + z1))]))), x, y, z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n010 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r01 + z0))]))), x, y - @as(f32, @floatFromInt(@as(c_int, 1))), z);
    n011 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r01 + z1))]))), x, y - @as(f32, @floatFromInt(@as(c_int, 1))), z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n100 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r10 + z0))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y, z);
    n101 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r10 + z1))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y, z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n110 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r11 + z0))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y - @as(f32, @floatFromInt(@as(c_int, 1))), z);
    n111 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r11 + z1))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y - @as(f32, @floatFromInt(@as(c_int, 1))), z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n00 = stb__perlin_lerp(n000, n001, w);
    n01 = stb__perlin_lerp(n010, n011, w);
    n10 = stb__perlin_lerp(n100, n101, w);
    n11 = stb__perlin_lerp(n110, n111, w);
    n0 = stb__perlin_lerp(n00, n01, v);
    n1 = stb__perlin_lerp(n10, n11, v);
    return stb__perlin_lerp(n0, n1, u);
}
pub const float_t = f32;
pub const double_t = f64;
pub extern fn __fpclassify(f64) c_int;
pub extern fn __fpclassifyf(f32) c_int;
pub extern fn __fpclassifyl(c_longdouble) c_int;
pub fn __FLOAT_BITS(arg___f: f32) callconv(.c) c_uint {
    var __f = arg___f;
    _ = &__f;
    const union_unnamed_1 = extern union {
        __f: f32,
        __i: c_uint,
    };
    _ = &union_unnamed_1;
    var __u: union_unnamed_1 = undefined;
    _ = &__u;
    __u.__f = __f;
    return __u.__i;
}
pub fn __DOUBLE_BITS(arg___f: f64) callconv(.c) c_ulonglong {
    var __f = arg___f;
    _ = &__f;
    const union_unnamed_2 = extern union {
        __f: f64,
        __i: c_ulonglong,
    };
    _ = &union_unnamed_2;
    var __u: union_unnamed_2 = undefined;
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
pub var stb__perlin_randtab: [512]u8 = [512]u8{
    23,
    125,
    161,
    52,
    103,
    117,
    70,
    37,
    247,
    101,
    203,
    169,
    124,
    126,
    44,
    123,
    152,
    238,
    145,
    45,
    171,
    114,
    253,
    10,
    192,
    136,
    4,
    157,
    249,
    30,
    35,
    72,
    175,
    63,
    77,
    90,
    181,
    16,
    96,
    111,
    133,
    104,
    75,
    162,
    93,
    56,
    66,
    240,
    8,
    50,
    84,
    229,
    49,
    210,
    173,
    239,
    141,
    1,
    87,
    18,
    2,
    198,
    143,
    57,
    225,
    160,
    58,
    217,
    168,
    206,
    245,
    204,
    199,
    6,
    73,
    60,
    20,
    230,
    211,
    233,
    94,
    200,
    88,
    9,
    74,
    155,
    33,
    15,
    219,
    130,
    226,
    202,
    83,
    236,
    42,
    172,
    165,
    218,
    55,
    222,
    46,
    107,
    98,
    154,
    109,
    67,
    196,
    178,
    127,
    158,
    13,
    243,
    65,
    79,
    166,
    248,
    25,
    224,
    115,
    80,
    68,
    51,
    184,
    128,
    232,
    208,
    151,
    122,
    26,
    212,
    105,
    43,
    179,
    213,
    235,
    148,
    146,
    89,
    14,
    195,
    28,
    78,
    112,
    76,
    250,
    47,
    24,
    251,
    140,
    108,
    186,
    190,
    228,
    170,
    183,
    139,
    39,
    188,
    244,
    246,
    132,
    48,
    119,
    144,
    180,
    138,
    134,
    193,
    82,
    182,
    120,
    121,
    86,
    220,
    209,
    3,
    91,
    241,
    149,
    85,
    205,
    150,
    113,
    216,
    31,
    100,
    41,
    164,
    177,
    214,
    153,
    231,
    38,
    71,
    185,
    174,
    97,
    201,
    29,
    95,
    7,
    92,
    54,
    254,
    191,
    118,
    34,
    221,
    131,
    11,
    163,
    99,
    234,
    81,
    227,
    147,
    156,
    176,
    17,
    142,
    69,
    12,
    110,
    62,
    27,
    255,
    0,
    194,
    59,
    116,
    242,
    252,
    19,
    21,
    187,
    53,
    207,
    129,
    64,
    135,
    61,
    40,
    167,
    237,
    102,
    223,
    106,
    159,
    197,
    189,
    215,
    137,
    36,
    32,
    22,
    5,
    23,
    125,
    161,
    52,
    103,
    117,
    70,
    37,
    247,
    101,
    203,
    169,
    124,
    126,
    44,
    123,
    152,
    238,
    145,
    45,
    171,
    114,
    253,
    10,
    192,
    136,
    4,
    157,
    249,
    30,
    35,
    72,
    175,
    63,
    77,
    90,
    181,
    16,
    96,
    111,
    133,
    104,
    75,
    162,
    93,
    56,
    66,
    240,
    8,
    50,
    84,
    229,
    49,
    210,
    173,
    239,
    141,
    1,
    87,
    18,
    2,
    198,
    143,
    57,
    225,
    160,
    58,
    217,
    168,
    206,
    245,
    204,
    199,
    6,
    73,
    60,
    20,
    230,
    211,
    233,
    94,
    200,
    88,
    9,
    74,
    155,
    33,
    15,
    219,
    130,
    226,
    202,
    83,
    236,
    42,
    172,
    165,
    218,
    55,
    222,
    46,
    107,
    98,
    154,
    109,
    67,
    196,
    178,
    127,
    158,
    13,
    243,
    65,
    79,
    166,
    248,
    25,
    224,
    115,
    80,
    68,
    51,
    184,
    128,
    232,
    208,
    151,
    122,
    26,
    212,
    105,
    43,
    179,
    213,
    235,
    148,
    146,
    89,
    14,
    195,
    28,
    78,
    112,
    76,
    250,
    47,
    24,
    251,
    140,
    108,
    186,
    190,
    228,
    170,
    183,
    139,
    39,
    188,
    244,
    246,
    132,
    48,
    119,
    144,
    180,
    138,
    134,
    193,
    82,
    182,
    120,
    121,
    86,
    220,
    209,
    3,
    91,
    241,
    149,
    85,
    205,
    150,
    113,
    216,
    31,
    100,
    41,
    164,
    177,
    214,
    153,
    231,
    38,
    71,
    185,
    174,
    97,
    201,
    29,
    95,
    7,
    92,
    54,
    254,
    191,
    118,
    34,
    221,
    131,
    11,
    163,
    99,
    234,
    81,
    227,
    147,
    156,
    176,
    17,
    142,
    69,
    12,
    110,
    62,
    27,
    255,
    0,
    194,
    59,
    116,
    242,
    252,
    19,
    21,
    187,
    53,
    207,
    129,
    64,
    135,
    61,
    40,
    167,
    237,
    102,
    223,
    106,
    159,
    197,
    189,
    215,
    137,
    36,
    32,
    22,
    5,
};
pub var stb__perlin_randtab_grad_idx: [512]u8 = [512]u8{
    7,
    9,
    5,
    0,
    11,
    1,
    6,
    9,
    3,
    9,
    11,
    1,
    8,
    10,
    4,
    7,
    8,
    6,
    1,
    5,
    3,
    10,
    9,
    10,
    0,
    8,
    4,
    1,
    5,
    2,
    7,
    8,
    7,
    11,
    9,
    10,
    1,
    0,
    4,
    7,
    5,
    0,
    11,
    6,
    1,
    4,
    2,
    8,
    8,
    10,
    4,
    9,
    9,
    2,
    5,
    7,
    9,
    1,
    7,
    2,
    2,
    6,
    11,
    5,
    5,
    4,
    6,
    9,
    0,
    1,
    1,
    0,
    7,
    6,
    9,
    8,
    4,
    10,
    3,
    1,
    2,
    8,
    8,
    9,
    10,
    11,
    5,
    11,
    11,
    2,
    6,
    10,
    3,
    4,
    2,
    4,
    9,
    10,
    3,
    2,
    6,
    3,
    6,
    10,
    5,
    3,
    4,
    10,
    11,
    2,
    9,
    11,
    1,
    11,
    10,
    4,
    9,
    4,
    11,
    0,
    4,
    11,
    4,
    0,
    0,
    0,
    7,
    6,
    10,
    4,
    1,
    3,
    11,
    5,
    3,
    4,
    2,
    9,
    1,
    3,
    0,
    1,
    8,
    0,
    6,
    7,
    8,
    7,
    0,
    4,
    6,
    10,
    8,
    2,
    3,
    11,
    11,
    8,
    0,
    2,
    4,
    8,
    3,
    0,
    0,
    10,
    6,
    1,
    2,
    2,
    4,
    5,
    6,
    0,
    1,
    3,
    11,
    9,
    5,
    5,
    9,
    6,
    9,
    8,
    3,
    8,
    1,
    8,
    9,
    6,
    9,
    11,
    10,
    7,
    5,
    6,
    5,
    9,
    1,
    3,
    7,
    0,
    2,
    10,
    11,
    2,
    6,
    1,
    3,
    11,
    7,
    7,
    2,
    1,
    7,
    3,
    0,
    8,
    1,
    1,
    5,
    0,
    6,
    10,
    11,
    11,
    0,
    2,
    7,
    0,
    10,
    8,
    3,
    5,
    7,
    1,
    11,
    1,
    0,
    7,
    9,
    0,
    11,
    5,
    10,
    3,
    2,
    3,
    5,
    9,
    7,
    9,
    8,
    4,
    6,
    5,
    7,
    9,
    5,
    0,
    11,
    1,
    6,
    9,
    3,
    9,
    11,
    1,
    8,
    10,
    4,
    7,
    8,
    6,
    1,
    5,
    3,
    10,
    9,
    10,
    0,
    8,
    4,
    1,
    5,
    2,
    7,
    8,
    7,
    11,
    9,
    10,
    1,
    0,
    4,
    7,
    5,
    0,
    11,
    6,
    1,
    4,
    2,
    8,
    8,
    10,
    4,
    9,
    9,
    2,
    5,
    7,
    9,
    1,
    7,
    2,
    2,
    6,
    11,
    5,
    5,
    4,
    6,
    9,
    0,
    1,
    1,
    0,
    7,
    6,
    9,
    8,
    4,
    10,
    3,
    1,
    2,
    8,
    8,
    9,
    10,
    11,
    5,
    11,
    11,
    2,
    6,
    10,
    3,
    4,
    2,
    4,
    9,
    10,
    3,
    2,
    6,
    3,
    6,
    10,
    5,
    3,
    4,
    10,
    11,
    2,
    9,
    11,
    1,
    11,
    10,
    4,
    9,
    4,
    11,
    0,
    4,
    11,
    4,
    0,
    0,
    0,
    7,
    6,
    10,
    4,
    1,
    3,
    11,
    5,
    3,
    4,
    2,
    9,
    1,
    3,
    0,
    1,
    8,
    0,
    6,
    7,
    8,
    7,
    0,
    4,
    6,
    10,
    8,
    2,
    3,
    11,
    11,
    8,
    0,
    2,
    4,
    8,
    3,
    0,
    0,
    10,
    6,
    1,
    2,
    2,
    4,
    5,
    6,
    0,
    1,
    3,
    11,
    9,
    5,
    5,
    9,
    6,
    9,
    8,
    3,
    8,
    1,
    8,
    9,
    6,
    9,
    11,
    10,
    7,
    5,
    6,
    5,
    9,
    1,
    3,
    7,
    0,
    2,
    10,
    11,
    2,
    6,
    1,
    3,
    11,
    7,
    7,
    2,
    1,
    7,
    3,
    0,
    8,
    1,
    1,
    5,
    0,
    6,
    10,
    11,
    11,
    0,
    2,
    7,
    0,
    10,
    8,
    3,
    5,
    7,
    1,
    11,
    1,
    0,
    7,
    9,
    0,
    11,
    5,
    10,
    3,
    2,
    3,
    5,
    9,
    7,
    9,
    8,
    4,
    6,
    5,
};
pub fn stb__perlin_lerp(arg_a: f32, arg_b: f32, arg_t: f32) callconv(.c) f32 {
    var a = arg_a;
    _ = &a;
    var b = arg_b;
    _ = &b;
    var t = arg_t;
    _ = &t;
    return a + ((b - a) * t);
}
pub fn stb__perlin_fastfloor(arg_a: f32) callconv(.c) c_int {
    var a = arg_a;
    _ = &a;
    var ai: c_int = @as(c_int, @intFromFloat(a));
    _ = &ai;
    return if (a < @as(f32, @floatFromInt(ai))) ai - @as(c_int, 1) else ai;
}
pub fn stb__perlin_grad(arg_grad_idx: c_int, arg_x: f32, arg_y: f32, arg_z: f32) callconv(.c) f32 {
    var grad_idx = arg_grad_idx;
    _ = &grad_idx;
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    const basis = struct {
        var static: [12][4]f32 = [12][4]f32{
            [3]f32{
                1,
                1,
                0,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                1,
                0,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                1,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                0,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                0,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                1,
                0,
                1,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                0,
                1,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                1,
                0,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
            } ++ [1]f32{0} ** 1,
            [3]f32{
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                0,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
            } ++ [1]f32{0} ** 1,
            [3]f32{
                0,
                1,
                1,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                0,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                1,
            } ++ [1]f32{0} ** 1,
            [3]f32{
                0,
                1,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
            } ++ [1]f32{0} ** 1,
            [3]f32{
                0,
                @as(f32, @floatFromInt(-@as(c_int, 1))),
                @as(f32, @floatFromInt(-@as(c_int, 1))),
            } ++ [1]f32{0} ** 1,
        };
    };
    _ = &basis;
    var grad: [*c]f32 = @as([*c]f32, @ptrCast(@alignCast(&basis.static[@as(c_uint, @intCast(grad_idx))][@as(usize, @intCast(0))])));
    _ = &grad;
    return ((grad[@as(c_uint, @intCast(@as(c_int, 0)))] * x) + (grad[@as(c_uint, @intCast(@as(c_int, 1)))] * y)) + (grad[@as(c_uint, @intCast(@as(c_int, 2)))] * z);
}
pub export fn stb_perlin_noise3_internal(arg_x: f32, arg_y: f32, arg_z: f32, arg_x_wrap: c_int, arg_y_wrap: c_int, arg_z_wrap: c_int, arg_seed: u8) f32 {
    var x = arg_x;
    _ = &x;
    var y = arg_y;
    _ = &y;
    var z = arg_z;
    _ = &z;
    var x_wrap = arg_x_wrap;
    _ = &x_wrap;
    var y_wrap = arg_y_wrap;
    _ = &y_wrap;
    var z_wrap = arg_z_wrap;
    _ = &z_wrap;
    var seed = arg_seed;
    _ = &seed;
    var u: f32 = undefined;
    _ = &u;
    var v: f32 = undefined;
    _ = &v;
    var w: f32 = undefined;
    _ = &w;
    var n000: f32 = undefined;
    _ = &n000;
    var n001: f32 = undefined;
    _ = &n001;
    var n010: f32 = undefined;
    _ = &n010;
    var n011: f32 = undefined;
    _ = &n011;
    var n100: f32 = undefined;
    _ = &n100;
    var n101: f32 = undefined;
    _ = &n101;
    var n110: f32 = undefined;
    _ = &n110;
    var n111: f32 = undefined;
    _ = &n111;
    var n00: f32 = undefined;
    _ = &n00;
    var n01: f32 = undefined;
    _ = &n01;
    var n10: f32 = undefined;
    _ = &n10;
    var n11: f32 = undefined;
    _ = &n11;
    var n0: f32 = undefined;
    _ = &n0;
    var n1: f32 = undefined;
    _ = &n1;
    var x_mask: c_uint = @as(c_uint, @bitCast((x_wrap - @as(c_int, 1)) & @as(c_int, 255)));
    _ = &x_mask;
    var y_mask: c_uint = @as(c_uint, @bitCast((y_wrap - @as(c_int, 1)) & @as(c_int, 255)));
    _ = &y_mask;
    var z_mask: c_uint = @as(c_uint, @bitCast((z_wrap - @as(c_int, 1)) & @as(c_int, 255)));
    _ = &z_mask;
    var px: c_int = stb__perlin_fastfloor(x);
    _ = &px;
    var py: c_int = stb__perlin_fastfloor(y);
    _ = &py;
    var pz: c_int = stb__perlin_fastfloor(z);
    _ = &pz;
    var x0: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(px)) & x_mask));
    _ = &x0;
    var x1: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(px + @as(c_int, 1))) & x_mask));
    _ = &x1;
    var y0_1: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(py)) & y_mask));
    _ = &y0_1;
    var y1_2: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(py + @as(c_int, 1))) & y_mask));
    _ = &y1_2;
    var z0: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(pz)) & z_mask));
    _ = &z0;
    var z1: c_int = @as(c_int, @bitCast(@as(c_uint, @bitCast(pz + @as(c_int, 1))) & z_mask));
    _ = &z1;
    var r0: c_int = undefined;
    _ = &r0;
    var r1: c_int = undefined;
    _ = &r1;
    var r00: c_int = undefined;
    _ = &r00;
    var r01: c_int = undefined;
    _ = &r01;
    var r10: c_int = undefined;
    _ = &r10;
    var r11: c_int = undefined;
    _ = &r11;
    x -= @as(f32, @floatFromInt(px));
    u = ((((((x * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * x) + @as(f32, @floatFromInt(@as(c_int, 10)))) * x) * x) * x;
    y -= @as(f32, @floatFromInt(py));
    v = ((((((y * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * y) + @as(f32, @floatFromInt(@as(c_int, 10)))) * y) * y) * y;
    z -= @as(f32, @floatFromInt(pz));
    w = ((((((z * @as(f32, @floatFromInt(@as(c_int, 6)))) - @as(f32, @floatFromInt(@as(c_int, 15)))) * z) + @as(f32, @floatFromInt(@as(c_int, 10)))) * z) * z) * z;
    r0 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(x0 + @as(c_int, @bitCast(@as(c_uint, seed)))))])));
    r1 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(x1 + @as(c_int, @bitCast(@as(c_uint, seed)))))])));
    r00 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r0 + y0_1))])));
    r01 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r0 + y1_2))])));
    r10 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r1 + y0_1))])));
    r11 = @as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab[@as(c_uint, @intCast(r1 + y1_2))])));
    n000 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r00 + z0))]))), x, y, z);
    n001 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r00 + z1))]))), x, y, z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n010 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r01 + z0))]))), x, y - @as(f32, @floatFromInt(@as(c_int, 1))), z);
    n011 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r01 + z1))]))), x, y - @as(f32, @floatFromInt(@as(c_int, 1))), z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n100 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r10 + z0))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y, z);
    n101 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r10 + z1))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y, z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n110 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r11 + z0))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y - @as(f32, @floatFromInt(@as(c_int, 1))), z);
    n111 = stb__perlin_grad(@as(c_int, @bitCast(@as(c_uint, stb__perlin_randtab_grad_idx[@as(c_uint, @intCast(r11 + z1))]))), x - @as(f32, @floatFromInt(@as(c_int, 1))), y - @as(f32, @floatFromInt(@as(c_int, 1))), z - @as(f32, @floatFromInt(@as(c_int, 1))));
    n00 = stb__perlin_lerp(n000, n001, w);
    n01 = stb__perlin_lerp(n010, n011, w);
    n10 = stb__perlin_lerp(n100, n101, w);
    n11 = stb__perlin_lerp(n110, n111, w);
    n0 = stb__perlin_lerp(n00, n01, v);
    n1 = stb__perlin_lerp(n10, n11, v);
    return stb__perlin_lerp(n0, n1, u);
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
pub const STB_PERLIN_IMPLEMENTATION = "";
pub const _MATH_H = "";
pub const _FEATURES_H = "";
pub const _BSD_SOURCE = @as(c_int, 1);
pub const _XOPEN_SOURCE = @as(c_int, 700);
pub const __restrict = @compileError("unable to translate C expr: unexpected token 'restrict'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:20:9
pub const __inline = @compileError("unable to translate C expr: unexpected token 'inline'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:26:9
pub const __REDIR = @compileError("unable to translate C expr: unexpected token '__typeof__'");
// /usr/local/zig-aarch64-linux-0.15.2/lib/libc/include/generic-musl/features.h:38:9
pub const __NEED_float_t = "";
pub const __NEED_double_t = "";
pub const _Addr = c_long;
pub const _Int64 = c_long;
pub const _Reg = c_long;
pub const __BYTE_ORDER = @as(c_int, 1234);
pub const __LONG_MAX = @import("std").zig.c_translation.promoteIntLiteral(c_long, 0x7fffffffffffffff, .hex);
pub const __DEFINED_float_t = "";
pub const __DEFINED_double_t = "";
pub const __LITTLE_ENDIAN = @as(c_int, 1234);
pub const __BIG_ENDIAN = @as(c_int, 4321);
pub const __USE_TIME_BITS64 = @as(c_int, 1);
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
pub inline fn stb__perlin_ease(a: anytype) @TypeOf(((((((a * @as(c_int, 6)) - @as(c_int, 15)) * a) + @as(c_int, 10)) * a) * a) * a) {
    _ = &a;
    return ((((((a * @as(c_int, 6)) - @as(c_int, 15)) * a) + @as(c_int, 10)) * a) * a) * a;
}
