// No copyright claimed, Public Domain
//
// Pure Zig port of arcan_math.c — 4x4 matrix ops, vector/quaternion math,
// interpolation, frustum culling, ray intersection, utilities.

const std = @import("std");
const math = std.math;

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const EPSILON: f32 = 0.000001;
const MM_PER_PT: f32 = 0.3527;
const M_PI: f32 = math.pi;

// ---------------------------------------------------------------------------
// Types
//
// The exported vector/quat types MUST match arcan_math.h layout:
//   typedef struct { union { struct { float x,y,z; }; float xyz[3]; }; } vector;
//   typedef struct { union { struct { float x,y,z,w; }; float xyzw[4]; }; } quat;
//
// On aarch64, a plain extern struct {x,y,z} is classified as an HFA (passed in
// FP registers), but C's struct-with-union is NOT an HFA (passed in GP regs).
// Using extern union here prevents HFA classification, matching the C ABI.
//
// Internal code uses V3/Q4 (clean structs) and @bitCast at export boundaries.
// ---------------------------------------------------------------------------

// Internal clean types — used inside all function bodies
const V3 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
const Q4 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0, w: f32 = 0 };

// C-ABI-compatible exported types (extern union prevents HFA on aarch64)
pub const vector = extern union {
    s: extern struct { x: f32, y: f32, z: f32 },
    xyz: [3]f32,
};

pub const quat = extern union {
    s: extern struct { x: f32, y: f32, z: f32, w: f32 },
    xyzw: [4]f32,
};

pub const point = vector;
pub const scalefactor = vector;

// Zero-cost conversions. Route through the union's array field rather than
// @bitCast(union ↔ struct), which the aarch64 SH backend does not handle.
// [N]f32 ↔ extern struct is accepted as an aggregate memcpy bitcast.
inline fn v3(cv: vector) V3 {
    return @bitCast(cv.xyz);
}
inline fn cv3(val: V3) vector {
    return .{ .xyz = @bitCast(val) };
}
inline fn q4(cq: quat) Q4 {
    return @bitCast(cq.xyzw);
}
inline fn cq4(val: Q4) quat {
    return .{ .xyzw = @bitCast(val) };
}

pub const orientation = extern struct {
    rollf: f32 = 0,
    pitchf: f32 = 0,
    yawf: f32 = 0,
    matr: [16]f32 = [_]f32{0} ** 16,
};

pub const cstate = enum(c_int) {
    inside = 0,
    intersect = 1,
    outside = 2,
};

// ---------------------------------------------------------------------------
// Global exported variable
// ---------------------------------------------------------------------------
export var default_quat: quat = std.mem.zeroes(quat);

// ---------------------------------------------------------------------------
// Helper: identity matrix constant
// ---------------------------------------------------------------------------
const midentity = [16]f32{
    1.0, 0.0, 0.0, 0.0,
    0.0, 1.0, 0.0, 0.0,
    0.0, 0.0, 1.0, 0.0,
    0.0, 0.0, 0.0, 1.0,
};

// ---------------------------------------------------------------------------
// Matrix operations
// ---------------------------------------------------------------------------

export fn mult_matrix_vecf(
    matrix: [*]const f32,
    inv: [*]const f32,
    out: [*]f32,
) callconv(.c) void {
    for (0..4) |i| {
        out[i] =
            inv[0] * matrix[0 * 4 + i] +
            inv[1] * matrix[1 * 4 + i] +
            inv[2] * matrix[2 * 4 + i] +
            inv[3] * matrix[3 * 4 + i];
    }
}

export fn multiply_matrix(
    dst: [*]f32,
    a: [*]const f32,
    b: [*]const f32,
) callconv(.c) void {
    var i: usize = 0;
    while (i < 16) : (i += 4) {
        for (0..4) |j| {
            dst[i + j] =
                b[i] * a[j] +
                b[i + 1] * a[j + 4] +
                b[i + 2] * a[j + 8] +
                b[i + 3] * a[j + 12];
        }
    }
}

export fn scale_matrix(m: [*]f32, xs: f32, ys: f32, zs: f32) callconv(.c) void {
    m[0] *= xs;
    m[4] *= ys;
    m[8] *= zs;
    m[1] *= xs;
    m[5] *= ys;
    m[9] *= zs;
    m[2] *= xs;
    m[6] *= ys;
    m[10] *= zs;
    m[3] *= xs;
    m[7] *= ys;
    m[11] *= zs;
}

export fn translate_matrix(m: [*]f32, xt: f32, yt: f32, zt: f32) callconv(.c) void {
    m[12] += xt;
    m[13] += yt;
    m[14] += zt;
}

export fn identity_matrix(m: [*]f32) callconv(.c) void {
    @memcpy(m[0..16], &midentity);
}

export fn matr_lookat(m: [*]f32, cposition: vector, cdstpos: vector, cup: vector) callconv(.c) void {
    const position = v3(cposition);
    const dstpos = v3(cdstpos);
    const up = v3(cup);
    const fwd = norm_impl(sub_impl(dstpos, position));
    const side = norm_impl(crossp_impl(fwd, up));
    const rup = crossp_impl(side, fwd);

    m[0] = side.x;
    m[1] = rup.x;
    m[2] = -fwd.x;

    m[4] = side.y;
    m[5] = rup.y;
    m[6] = -fwd.y;

    m[8] = side.z;
    m[9] = rup.z;
    m[10] = -fwd.z;

    m[15] = 1.0;

    translate_matrix(m, -position.x, -position.y, -position.z);
}

export fn build_orthographic_matrix(
    m: [*]f32,
    left: f32,
    right: f32,
    bottom: f32,
    top: f32,
    nearf: f32,
    farf: f32,
) callconv(.c) void {
    const irml: f32 = 1.0 / (right - left);
    const itmb: f32 = 1.0 / (top - bottom);
    const ifmn: f32 = 1.0 / (farf - nearf);

    m[0] = 2.0 * irml;
    m[1] = 0.0;
    m[2] = 0.0;
    m[3] = 0.0;

    m[4] = 0.0;
    m[5] = 2.0 * itmb;
    m[6] = 0.0;
    m[7] = 0.0;

    m[8] = 0.0;
    m[9] = 0.0;
    m[10] = 2.0 * ifmn;
    m[11] = 0.0;

    m[12] = -(right + left) * irml;
    m[13] = -(top + bottom) * itmb;
    m[14] = -(farf + nearf) * ifmn;
    m[15] = 1.0;
}

export fn build_projection_matrix(
    m: [*]f32,
    nearv: f32,
    farv: f32,
    aspect: f32,
    fov: f32,
) callconv(.c) void {
    const h: f32 = 1.0 / @tan(fov * (M_PI / 360.0));
    const neg_depth: f32 = nearv - farv;

    m[0] = h / aspect;
    m[1] = 0;
    m[2] = 0;
    m[3] = 0;
    m[4] = 0;
    m[5] = h;
    m[6] = 0;
    m[7] = 0;
    m[8] = 0;
    m[9] = 0;
    m[10] = (farv + nearv) / neg_depth;
    m[11] = -1;
    m[12] = 0;
    m[13] = 0;
    m[14] = 2.0 * (nearv * farv) / neg_depth;
    m[15] = 0;
}

export fn project_matrix(
    objx: f32,
    objy: f32,
    objz: f32,
    modelMatrix: [*]const f32,
    projMatrix: [*]const f32,
    viewport: [*]const c_int,
    winx: *f32,
    winy: *f32,
    winz: *f32,
) callconv(.c) c_int {
    var in align(16) = [4]f32{ objx, objy, objz, 1.0 };
    var out: [4]f32 align(16) = undefined;

    mult_matrix_vecf(modelMatrix, &in, &out);
    mult_matrix_vecf(projMatrix, &out, &in);

    if (in[3] == 0.0)
        return 0;

    in[0] /= in[3];
    in[1] /= in[3];
    in[2] /= in[3];

    // Map x, y and z to range 0-1
    in[0] = in[0] * 0.5 + 0.5;
    in[1] = in[1] * 0.5 + 0.5;
    in[2] = in[2] * 0.5 + 0.5;

    // Map x,y to viewport
    const vp2: f32 = @floatFromInt(viewport[2]);
    const vp3: f32 = @floatFromInt(viewport[3]);
    const vp0: f32 = @floatFromInt(viewport[0]);
    const vp1: f32 = @floatFromInt(viewport[1]);
    in[0] = in[0] * vp2 + vp0;
    in[1] = in[1] * vp3 + vp1;

    winx.* = in[0];
    winy.* = in[1];
    winz.* = in[2];
    return 1;
}

export fn matr_rotatef(ang: f32, dmatr: [*]f32) callconv(.c) [*]f32 {
    const cval = @cos(ang);
    const sf = @sin(ang);
    @memcpy(dmatr[0..16], &midentity);
    dmatr[0] = cval;
    dmatr[5] = cval;
    dmatr[1] = sf;
    dmatr[4] = -sf;
    return dmatr;
}

export fn matr_invf(m: [*]const f32, out: [*]f32) callconv(.c) bool {
    var inv: [16]f32 = undefined;

    inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] + m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
    inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] - m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
    inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] + m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
    inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] - m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
    inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] - m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
    inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] + m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
    inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] - m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
    inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] + m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
    inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] + m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
    inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] - m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
    inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] + m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
    inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] - m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
    inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] - m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
    inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] + m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
    inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] - m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
    inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] + m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

    var det: f32 = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];

    if (det == 0)
        return false;

    det = 1.0 / det;

    for (0..16) |i| {
        out[i] = inv[i] * det;
    }

    return true;
}

// ---------------------------------------------------------------------------
// Quaternion -> matrix (float)
// ---------------------------------------------------------------------------

export fn matr_quatf(ca: quat, dmatr: ?[*]f32) callconv(.c) ?[*]f32 {
    const a = q4(ca);
    if (dmatr) |dm| {
        dm[0] = 1.0 - 2.0 * (a.y * a.y + a.z * a.z);
        dm[1] = 2.0 * (a.x * a.y + a.z * a.w);
        dm[2] = 2.0 * (a.x * a.z - a.y * a.w);
        dm[3] = 0.0;
        dm[4] = 2.0 * (a.x * a.y - a.z * a.w);
        dm[5] = 1.0 - 2.0 * (a.x * a.x + a.z * a.z);
        dm[6] = 2.0 * (a.z * a.y + a.x * a.w);
        dm[7] = 0.0;
        dm[8] = 2.0 * (a.x * a.z + a.y * a.w);
        dm[9] = 2.0 * (a.y * a.z - a.x * a.w);
        dm[10] = 1.0 - 2.0 * (a.x * a.x + a.y * a.y);
        dm[11] = 0.0;
        dm[12] = 0.0;
        dm[13] = 0.0;
        dm[14] = 0.0;
        dm[15] = 1.0;
    }
    return dmatr;
}

// ---------------------------------------------------------------------------
// Quaternion -> matrix (double)
// ---------------------------------------------------------------------------

export fn matr_quat(ca: quat, dmatr: ?[*]f64) callconv(.c) ?[*]f64 {
    const a = q4(ca);
    if (dmatr) |dm| {
        dm[0] = 1.0 - 2.0 * (@as(f64, a.y) * @as(f64, a.y) + @as(f64, a.z) * @as(f64, a.z));
        dm[1] = 2.0 * (@as(f64, a.x) * @as(f64, a.y) + @as(f64, a.z) * @as(f64, a.w));
        dm[2] = 2.0 * (@as(f64, a.x) * @as(f64, a.z) - @as(f64, a.y) * @as(f64, a.w));
        dm[3] = 0.0;
        dm[4] = 2.0 * (@as(f64, a.x) * @as(f64, a.y) - @as(f64, a.z) * @as(f64, a.w));
        dm[5] = 1.0 - 2.0 * (@as(f64, a.x) * @as(f64, a.x) + @as(f64, a.z) * @as(f64, a.z));
        dm[6] = 2.0 * (@as(f64, a.z) * @as(f64, a.y) + @as(f64, a.x) * @as(f64, a.w));
        dm[7] = 0.0;
        dm[8] = 2.0 * (@as(f64, a.x) * @as(f64, a.z) + @as(f64, a.y) * @as(f64, a.w));
        dm[9] = 2.0 * (@as(f64, a.y) * @as(f64, a.z) - @as(f64, a.x) * @as(f64, a.w));
        dm[10] = 1.0 - 2.0 * (@as(f64, a.x) * @as(f64, a.x) + @as(f64, a.y) * @as(f64, a.y));
        dm[11] = 0.0;
        dm[12] = 0.0;
        dm[13] = 0.0;
        dm[14] = 0.0;
        dm[15] = 1.0;
    }
    return dmatr;
}

// ---------------------------------------------------------------------------
// quat_matrix — extract quaternion from 4x4 rotation matrix
// ---------------------------------------------------------------------------

export fn quat_matrix(src: [*]f32) callconv(.c) quat {
    const trace = src[0] + src[5] + src[10];
    var q: Q4 = .{};

    if (trace > 0) {
        const s: f32 = @sqrt(trace + 1.0) * 2.0;
        q.w = 0.25 * s;
        q.x = (src[6] - src[9]) / s;
        q.y = (src[8] - src[2]) / s;
        q.z = (src[1] - src[4]) / s;
    } else if (src[0] > src[5] and src[0] > src[10]) {
        const s: f32 = @sqrt(1.0 + src[0] - src[5] - src[10]) * 2.0;
        q.w = (src[6] - src[9]) / s;
        q.x = 0.25 * s;
        q.y = (src[4] + src[1]) / s;
        q.z = (src[8] + src[2]) / s;
    } else if (src[5] > src[10]) {
        const s: f32 = @sqrt(1.0 + src[5] - src[0] - src[10]) * 2.0;
        q.w = (src[8] - src[2]) / s;
        q.x = (src[4] + src[1]) / s;
        q.y = 0.25 * s;
        q.z = (src[9] + src[6]) / s;
    } else {
        const s: f32 = @sqrt(1.0 + src[10] - src[0] - src[5]) * 2.0;
        q.w = (src[1] - src[4]) / s;
        q.x = (src[8] + src[2]) / s;
        q.y = (src[9] + src[6]) / s;
        q.z = 0.25 * s;
    }
    return cq4(q);
}

// ---------------------------------------------------------------------------
// Vector operations — internal implementations (V3)
// ---------------------------------------------------------------------------

fn sub_impl(a: V3, b: V3) V3 {
    return .{ .x = a.x - b.x, .y = a.y - b.y, .z = a.z - b.z };
}

fn add_impl(a: V3, b: V3) V3 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z };
}

fn mul_impl(a: V3, b: V3) V3 {
    return .{ .x = a.x * b.x, .y = a.y * b.y, .z = a.z * b.z };
}

fn mulf_impl(a: V3, f: f32) V3 {
    return .{ .x = a.x * f, .y = a.y * f, .z = a.z * f };
}

fn len_impl(v: V3) f32 {
    return @sqrt(v.x * v.x + v.y * v.y + v.z * v.z);
}

fn crossp_impl(a: V3, b: V3) V3 {
    return .{
        .x = a.y * b.z - a.z * b.y,
        .y = a.z * b.x - a.x * b.z,
        .z = a.x * b.y - a.y * b.x,
    };
}

fn dotp_impl(a: V3, b: V3) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z;
}

fn norm_impl(v: V3) V3 {
    const len = len_impl(v);
    if (len < EPSILON)
        return .{ .x = 0.0, .y = 0.0, .z = 0.0 };
    return .{ .x = v.x / len, .y = v.y / len, .z = v.z / len };
}

// ---------------------------------------------------------------------------
// Vector operations — exported C ABI wrappers
// ---------------------------------------------------------------------------

export fn build_vect_polar(phi: f32, theta: f32) callconv(.c) vector {
    return cv3(.{
        .x = @sin(phi) * @cos(theta),
        .y = @sin(phi) * @sin(theta),
        .z = @sin(phi),
    });
}

export fn build_vect(x: f32, y: f32, z: f32) callconv(.c) vector {
    return cv3(.{ .x = x, .y = y, .z = z });
}

export fn mul_vectorf(ca: vector, f: f32) callconv(.c) vector {
    return cv3(mulf_impl(v3(ca), f));
}

export fn len_vector(cv: vector) callconv(.c) f32 {
    return len_impl(v3(cv));
}

export fn crossp_vector(ca: vector, cb: vector) callconv(.c) vector {
    return cv3(crossp_impl(v3(ca), v3(cb)));
}

export fn dotp_vector(ca: vector, cb: vector) callconv(.c) f32 {
    return dotp_impl(v3(ca), v3(cb));
}

export fn sub_vector(ca: vector, cb: vector) callconv(.c) vector {
    return cv3(sub_impl(v3(ca), v3(cb)));
}

export fn add_vector(ca: vector, cb: vector) callconv(.c) vector {
    return cv3(add_impl(v3(ca), v3(cb)));
}

export fn mul_vector(ca: vector, cb: vector) callconv(.c) vector {
    return cv3(mul_impl(v3(ca), v3(cb)));
}

export fn norm_vector(cv: vector) callconv(.c) vector {
    return cv3(norm_impl(v3(cv)));
}

export fn taitbryan_forwardv(roll: f32, pitch: f32, yaw: f32) callconv(.c) vector {
    _ = roll;
    var dmatr: [16]f32 align(16) = undefined;

    const pitchq = build_quat_impl(pitch, 1.0, 0.0, 0.0);
    const yawq = build_quat_impl(yaw, 0.0, 1.0, 0.0);

    _ = matr_quatf(cq4(pitchq), &dmatr);

    var view: V3 = undefined;
    view.y = -dmatr[9];
    const res = mul_quat_impl(pitchq, yawq);
    _ = matr_quatf(cq4(res), &dmatr);
    view.x = -dmatr[8];
    view.z = dmatr[10];

    return cv3(view);
}

export fn lerp_vector(ca: vector, cb: vector, fact: f32) callconv(.c) vector {
    const a = v3(ca);
    const b = v3(cb);
    return cv3(.{
        .x = a.x + fact * (b.x - a.x),
        .y = a.y + fact * (b.y - a.y),
        .z = a.z + fact * (b.z - a.z),
    });
}

// ---------------------------------------------------------------------------
// Quaternion operations — internal implementations (Q4)
// ---------------------------------------------------------------------------

fn build_quat_impl(angdeg: f32, vx: f32, vy: f32, vz: f32) Q4 {
    const ang = angdeg / 180.0 * M_PI;
    const res = @sin(ang / 2.0);
    return .{ .w = @cos(ang / 2.0), .x = vx * res, .y = vy * res, .z = vz * res };
}

fn mul_quat_impl(a: Q4, b: Q4) Q4 {
    return .{
        .w = a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
        .x = a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        .y = a.w * b.y + a.y * b.w + a.z * b.x - a.x * b.z,
        .z = a.w * b.z + a.z * b.w + a.x * b.y - a.y * b.x,
    };
}

fn add_quat_impl(a: Q4, b: Q4) Q4 {
    return .{ .x = a.x + b.x, .y = a.y + b.y, .z = a.z + b.z, .w = a.w + b.w };
}

fn dot_quat_impl(a: Q4, b: Q4) f32 {
    return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w;
}

fn mul_quatf_impl(a: Q4, val: f32) Q4 {
    return .{ .x = a.x * val, .y = a.y * val, .z = a.z * val, .w = a.w * val };
}

fn norm_quat_impl(src: Q4) Q4 {
    var val = src.x * src.x + src.y * src.y + src.z * src.z + src.w * src.w;
    if (val > 0.99999 and val < 1.000001)
        return src;
    val = @sqrt(val);
    return .{ .x = src.x / val, .y = src.y / val, .z = src.z / val, .w = src.w / val };
}

// ---------------------------------------------------------------------------
// Quaternion operations — exported C ABI wrappers
// ---------------------------------------------------------------------------

export fn build_quat(angdeg: f32, vx: f32, vy: f32, vz: f32) callconv(.c) quat {
    return cq4(build_quat_impl(angdeg, vx, vy, vz));
}

export fn inv_quat(csrc: quat) callconv(.c) quat {
    const src = q4(csrc);
    return cq4(.{ .x = -src.x, .y = -src.y, .z = -src.z, .w = src.w });
}

export fn len_quat(csrc: quat) callconv(.c) f32 {
    const src = q4(csrc);
    return @sqrt(src.x * src.x + src.y * src.y + src.z * src.z + src.w * src.w);
}

export fn norm_quat(csrc: quat) callconv(.c) quat {
    return cq4(norm_quat_impl(q4(csrc)));
}

export fn div_quatf(ca: quat, val: f32) callconv(.c) quat {
    const a = q4(ca);
    // Note: C original has a bug here (a.z / v for .w). Preserving exact C behavior.
    return cq4(.{ .x = a.x / val, .y = a.y / val, .z = a.z / val, .w = a.z / val });
}

export fn mul_quatf(ca: quat, val: f32) callconv(.c) quat {
    return cq4(mul_quatf_impl(q4(ca), val));
}

export fn mul_quat(ca: quat, cb: quat) callconv(.c) quat {
    return cq4(mul_quat_impl(q4(ca), q4(cb)));
}

export fn add_quat(ca: quat, cb: quat) callconv(.c) quat {
    return cq4(add_quat_impl(q4(ca), q4(cb)));
}

export fn dot_quat(ca: quat, cb: quat) callconv(.c) f32 {
    return dot_quat_impl(q4(ca), q4(cb));
}

export fn angle_quat(ca: quat) callconv(.c) vector {
    const a = q4(ca);
    const sqw = a.w * a.w;
    const sqx = a.x * a.x;
    const sqy = a.y * a.y;
    const sqz = a.z * a.z;
    const mpi: f32 = 180.0 / M_PI;
    return cv3(.{
        .x = math.atan2(2.0 * (a.x * a.y + a.z * a.w), sqx - sqy - sqz + sqw) * mpi,
        .y = math.asin(@as(f32, -2.0 * (a.x * a.z - a.y * a.w))) * mpi,
        .z = math.atan2(2.0 * (a.y * a.z + a.x * a.w), -sqx - sqy + sqz + sqw) * mpi,
    });
}

export fn build_quat_taitbryan(roll: f32, pitch: f32, yaw: f32) callconv(.c) quat {
    const r = @mod(roll + 180.0, @as(f32, 360.0)) - 180.0;
    const p = @mod(pitch + 180.0, @as(f32, 360.0)) - 180.0;
    const y = @mod(yaw + 180.0, @as(f32, 360.0)) - 180.0;
    return cq4(mul_quat_impl(
        mul_quat_impl(build_quat_impl(p, 1.0, 0.0, 0.0), build_quat_impl(y, 0.0, 1.0, 0.0)),
        build_quat_impl(r, 0.0, 0.0, 1.0),
    ));
}

export fn quat_lookat(cpos: vector, cdstpos: vector) callconv(.c) quat {
    const diff = norm_impl(sub_impl(v3(cdstpos), v3(cpos)));
    const xang = math.acos(dotp_impl(diff, .{ .x = 1.0, .y = 0.0, .z = 0.0 }));
    const yang = math.acos(dotp_impl(diff, .{ .x = 0.0, .y = 1.0, .z = 0.0 }));
    const zang = math.acos(dotp_impl(diff, .{ .x = 0.0, .y = 0.0, .z = 1.0 }));
    return build_quat_taitbryan(xang, yang, zang);
}

export fn update_view(dst: *orientation, roll: f32, pitch: f32, yaw: f32) callconv(.c) void {
    dst.pitchf = pitch;
    dst.rollf = roll;
    dst.yawf = yaw;
    const pitchq = build_quat_impl(pitch, 1.0, 0.0, 0.0);
    const rollq = build_quat_impl(yaw, 0.0, 1.0, 0.0);
    const yawq = build_quat_impl(roll, 0.0, 0.0, 1.0);
    const res = mul_quat_impl(mul_quat_impl(pitchq, yawq), rollq);
    _ = matr_quatf(cq4(res), &dst.matr);
}

// ---------------------------------------------------------------------------
// Slerp / Nlerp helpers
// ---------------------------------------------------------------------------

fn slerp_quatfl(a: Q4, b: Q4, fact: f32, r360: bool) Q4 {
    var flip = false;
    var ct = dot_quat_impl(a, b);
    if (r360 and ct > 1.0) {
        ct = -ct;
        flip = true;
    }
    const th = math.acos(ct);
    const sth = @sin(th);
    var weight_a: f32 = undefined;
    var weight_b: f32 = undefined;
    if (sth > 0.005) {
        weight_a = @sin((1.0 - fact) * th) / sth;
        weight_b = @sin(fact * th) / sth;
    } else {
        weight_a = 1.0 - fact;
        weight_b = fact;
    }
    if (flip)
        weight_b = -weight_b;
    return add_quat_impl(mul_quatf_impl(a, weight_a), mul_quatf_impl(b, weight_b));
}

fn nlerp_quatfl(a: Q4, b: Q4, fact: f32, r360: bool) Q4 {
    const tinv: f32 = 1.0 - fact;
    const rq = if (r360 and dot_quat_impl(a, b) < 0.0)
        add_quat_impl(mul_quatf_impl(a, tinv), mul_quatf_impl(a, -fact))
    else
        add_quat_impl(mul_quatf_impl(a, tinv), mul_quatf_impl(b, fact));
    return norm_quat_impl(rq);
}

export fn slerp_quat180(ca: quat, cb: quat, fact: f32) callconv(.c) quat {
    return cq4(slerp_quatfl(q4(ca), q4(cb), fact, false));
}

export fn slerp_quat360(ca: quat, cb: quat, fact: f32) callconv(.c) quat {
    return cq4(slerp_quatfl(q4(ca), q4(cb), fact, true));
}

export fn nlerp_quat180(ca: quat, cb: quat, fact: f32) callconv(.c) quat {
    return cq4(nlerp_quatfl(q4(ca), q4(cb), fact, false));
}

export fn nlerp_quat360(ca: quat, cb: quat, fact: f32) callconv(.c) quat {
    return cq4(nlerp_quatfl(q4(ca), q4(cb), fact, true));
}

// ---------------------------------------------------------------------------
// 1D Interpolation
// ---------------------------------------------------------------------------

export fn interp_1d_linear(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    return sv + (ev - sv) * fract;
}

export fn interp_1d_sine(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    return sv + (ev - sv) * @sin(0.5 * fract * M_PI);
}

export fn interp_1d_smoothstep(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    var res: f32 = (fract - 0.1) / (0.9 - 0.1);
    if (res < 0)
        res = 0.0
    else if (res > 1.0)
        res = 1.0;
    res = res * res * (3.0 - 2.0 * res);
    return sv + res * (ev - sv);
}

export fn interp_1d_expout(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    return if (fract < EPSILON) sv else sv + (ev - sv) * (1.0 - math.pow(f32, 2.0, -10.0 * fract));
}

export fn interp_1d_expin(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    return if (fract < EPSILON) sv else sv + (ev - sv) * math.pow(f32, 2.0, 10.0 * (fract - 1.0));
}

export fn interp_1d_expinout(sv: f32, ev: f32, fract: f32) callconv(.c) f32 {
    if (fract < EPSILON) return sv;
    if (fract > 1.0 - EPSILON) return ev;
    if (fract < 0.5)
        return sv + (ev - sv) * (0.5 * math.pow(f32, 2.0, (20.0 * fract) - 10.0));
    return sv + (ev - sv) * ((-0.5 * math.pow(f32, 2.0, (-20.0 * fract) + 10.0)) + 1.0);
}

// ---------------------------------------------------------------------------
// 3D Interpolation
// ---------------------------------------------------------------------------

export fn interp_3d_linear(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    return cv3(.{
        .x = sv.x + (ev.x - sv.x) * fract,
        .y = sv.y + (ev.y - sv.y) * fract,
        .z = sv.z + (ev.z - sv.z) * fract,
    });
}

export fn interp_3d_sine(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    const s = @sin(@as(f32, 0.5) * fract * M_PI);
    return cv3(.{
        .x = sv.x + (ev.x - sv.x) * s,
        .y = sv.y + (ev.y - sv.y) * s,
        .z = sv.z + (ev.z - sv.z) * s,
    });
}

export fn interp_3d_smoothstep(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    return cv3(.{
        .x = interp_1d_smoothstep(sv.x, ev.x, fract),
        .y = interp_1d_smoothstep(sv.y, ev.y, fract),
        .z = interp_1d_smoothstep(sv.z, ev.z, fract),
    });
}

export fn interp_3d_expin(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    // Note: C original uses sv.x (not sv.y/sv.z) in the fallback case. Preserving exact behavior.
    const pw = math.pow(f32, 2.0, 10.0 * (fract - 1.0));
    return cv3(.{
        .x = if (fract < EPSILON) sv.x else sv.x + (ev.x - sv.x) * pw,
        .y = if (fract < EPSILON) sv.x else sv.y + (ev.y - sv.y) * pw,
        .z = if (fract < EPSILON) sv.x else sv.z + (ev.z - sv.z) * pw,
    });
}

export fn interp_3d_expout(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    // Note: C original uses sv.x (not sv.y/sv.z) in the fallback case. Preserving exact behavior.
    const pw = 1.0 - math.pow(f32, 2.0, -10.0 * fract);
    return cv3(.{
        .x = if (fract < EPSILON) sv.x else sv.x + (ev.x - sv.x) * pw,
        .y = if (fract < EPSILON) sv.x else sv.y + (ev.y - sv.y) * pw,
        .z = if (fract < EPSILON) sv.x else sv.z + (ev.z - sv.z) * pw,
    });
}

export fn interp_3d_expinout(csv: vector, cev: vector, fract: f32) callconv(.c) vector {
    const sv = v3(csv);
    const ev = v3(cev);
    const pw_in = 0.5 * math.pow(f32, 2.0, (20.0 * fract) - 10.0);
    const pw_out = (-0.5 * math.pow(f32, 2.0, (-20.0 * fract) + 10.0)) + 1.0;
    return cv3(.{
        .x = if (fract < EPSILON) sv.x else if (fract > 1.0 - EPSILON) ev.x else if (fract < 0.5) sv.x + (ev.x - sv.x) * pw_in else sv.x + (ev.x - sv.x) * pw_out,
        .y = if (fract < EPSILON) sv.y else if (fract > 1.0 - EPSILON) ev.y else if (fract < 0.5) sv.y + (ev.y - sv.y) * pw_in else sv.y + (ev.y - sv.y) * pw_out,
        .z = if (fract < EPSILON) sv.z else if (fract > 1.0 - EPSILON) ev.z else if (fract < 0.5) sv.z + (ev.z - sv.z) * pw_in else sv.z + (ev.z - sv.z) * pw_out,
    });
}

// ---------------------------------------------------------------------------
// Frustum culling
// ---------------------------------------------------------------------------

fn normalize_plane(pl: [*]f32) void {
    const mag: f32 = 1.0 / @sqrt(pl[0] * pl[0] + pl[1] * pl[1] + pl[2] * pl[2]);
    pl[0] *= mag;
    pl[1] *= mag;
    pl[2] *= mag;
    pl[3] *= mag;
}

export fn frustum_point(frustum: *const [6][4]f32, x: f32, y: f32, z: f32) callconv(.c) bool {
    for (0..6) |i| {
        if (frustum[i][0] * x + frustum[i][1] * y + frustum[i][2] * z + frustum[i][3] <= 0.0)
            return false;
    }
    return true;
}

export fn frustum_aabb(
    frustum: *const [6][4]f32,
    x1: f32, y1: f32, z1: f32,
    x2: f32, y2: f32, z2: f32,
) callconv(.c) cstate {
    var res: cstate = .inside;
    for (0..6) |i| {
        if (frustum[i][0] * x1 + frustum[i][1] * y1 + frustum[i][2] * z1 + frustum[i][3] > 0.0) continue;
        res = .intersect;
        if (frustum[i][0] * x2 + frustum[i][1] * y1 + frustum[i][2] * z1 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x1 + frustum[i][1] * y2 + frustum[i][2] * z1 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x2 + frustum[i][1] * y2 + frustum[i][2] * z1 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x1 + frustum[i][1] * y1 + frustum[i][2] * z2 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x2 + frustum[i][1] * y1 + frustum[i][2] * z2 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x1 + frustum[i][1] * y2 + frustum[i][2] * z2 + frustum[i][3] > 0.0) continue;
        if (frustum[i][0] * x2 + frustum[i][1] * y2 + frustum[i][2] * z2 + frustum[i][3] > 0.0) continue;
    }
    return res;
}

export fn frustum_sphere(frustum: *const [6][4]f32, x: f32, y: f32, z: f32, radius: f32) callconv(.c) cstate {
    for (0..6) |i| {
        const dist: f32 = frustum[i][0] * x + frustum[i][1] * y + frustum[i][2] * z + frustum[i][3];
        if (dist < -radius) return .outside;
        if (@abs(dist) < radius) return .intersect;
    }
    return .inside;
}

export fn update_frustum(prjm: [*]f32, mvm: [*]f32, frustum: *[6][4]f32) callconv(.c) void {
    var mmr: [16]f32 = undefined;
    multiply_matrix(&mmr, mvm, prjm);

    frustum[0][0] = mmr[3] + mmr[0];
    frustum[0][1] = mmr[7] + mmr[4];
    frustum[0][2] = mmr[11] + mmr[8];
    frustum[0][3] = mmr[15] + mmr[12];
    normalize_plane(&frustum[0]);

    frustum[1][0] = mmr[3] - mmr[0];
    frustum[1][1] = mmr[7] - mmr[4];
    frustum[1][2] = mmr[11] - mmr[8];
    frustum[1][3] = mmr[15] - mmr[12];
    normalize_plane(&frustum[1]);

    frustum[2][0] = mmr[3] - mmr[1];
    frustum[2][1] = mmr[7] - mmr[5];
    frustum[2][2] = mmr[11] - mmr[9];
    frustum[2][3] = mmr[15] - mmr[13];
    normalize_plane(&frustum[2]);

    frustum[3][0] = mmr[3] + mmr[1];
    frustum[3][1] = mmr[7] + mmr[5];
    frustum[3][2] = mmr[11] + mmr[9];
    frustum[3][3] = mmr[15] + mmr[13];
    normalize_plane(&frustum[3]);

    frustum[4][0] = mmr[3] + mmr[2];
    frustum[4][1] = mmr[7] + mmr[6];
    frustum[4][2] = mmr[11] + mmr[10];
    frustum[4][3] = mmr[15] + mmr[14];
    normalize_plane(&frustum[4]);

    frustum[5][0] = mmr[3] - mmr[2];
    frustum[5][1] = mmr[7] - mmr[6];
    frustum[5][2] = mmr[11] - mmr[10];
    frustum[5][3] = mmr[15] - mmr[14];
    normalize_plane(&frustum[5]);
}

// ---------------------------------------------------------------------------
// Ray intersection
// ---------------------------------------------------------------------------

export fn ray_plane(
    pos: *vector,
    dir: *vector,
    plane_pos: *vector,
    plane_normal: *vector,
    intersect: *vector,
) callconv(.c) bool {
    const den = dotp_impl(v3(pos.*), v3(dir.*));
    if (den > EPSILON) {
        const diff = sub_impl(v3(pos.*), v3(plane_pos.*));
        const tt = dotp_impl(diff, v3(plane_normal.*));
        intersect.* = cv3(add_impl(mulf_impl(v3(dir.*), tt), v3(pos.*)));
        return tt >= 0;
    }
    return false;
}

export fn ray_sphere(
    ray_pos: *const vector,
    ray_dir: *const vector,
    sphere_pos: *const vector,
    sphere_rad: f32,
    d1: *f32,
    d2: *f32,
) callconv(.c) bool {
    const delta = sub_impl(v3(ray_pos.*), v3(sphere_pos.*));
    const b = -1.0 * dotp_impl(delta, v3(ray_dir.*));
    var den = b * b - dotp_impl(delta, delta) + sphere_rad * sphere_rad;
    if (den < 0)
        return false;

    den = @sqrt(den);

    d1.* = b - den;
    d2.* = b + den;

    if (d2.* < 0)
        return false;

    if (d1.* < 0)
        d1.* = 0;

    return true;
}

// ---------------------------------------------------------------------------
// Utility
// ---------------------------------------------------------------------------

export fn pinpoly(nvert: c_int, vertx: [*]f32, verty: [*]f32, testx: f32, testy: f32) callconv(.c) c_int {
    var c: c_int = 0;
    const n: usize = @intCast(nvert);
    var j: usize = n -% 1;
    for (0..n) |i| {
        if (((verty[i] > testy) != (verty[j] > testy)) and
            (testx < (vertx[j] - vertx[i]) * (testy - verty[i]) /
                (verty[j] - verty[i]) + vertx[i]))
        {
            c = if (c != 0) 0 else 1;
        }
        j = i;
    }
    return c;
}

export fn unproject_matrix(
    dev_x: f32,
    dev_y: f32,
    dev_z: f32,
    view: [*]const f32,
    proj: [*]const f32,
) callconv(.c) vector {
    var invm: [16]f32 align(16) = undefined;
    var vpm: [16]f32 align(16) = undefined;
    multiply_matrix(&vpm, proj, view);
    _ = matr_invf(&vpm, &invm);

    var wndv: [4]f32 align(16) = .{ dev_x, dev_y, dev_z, 1.0 };
    var upv: [4]f32 align(16) = undefined;
    mult_matrix_vecf(&invm, &wndv, &upv);

    upv[3] = 1.0 / upv[3];

    return cv3(.{
        .x = upv[0] * upv[3],
        .y = upv[1] * upv[3],
        .z = upv[2] * upv[3],
    });
}

export fn dev_coord(
    out_x: *f32,
    out_y: *f32,
    out_z: *f32,
    x: c_int,
    y: c_int,
    w: c_int,
    h: c_int,
    near: f32,
    far: f32,
) callconv(.c) void {
    const fx: f32 = @floatFromInt(x);
    const fy: f32 = @floatFromInt(y);
    const fw: f32 = @floatFromInt(w);
    const fh: f32 = @floatFromInt(h);

    out_x.* = (2.0 * fx) / fw - 1.0;
    out_y.* = 1.0 - (2.0 * fy) / fh;
    out_z.* = (0.0 - near) / (far - near);
}

export fn arcan_pt_to_mm(pt: usize) callconv(.c) f32 {
    return @as(f32, @floatFromInt(pt)) * MM_PER_PT;
}

export fn arcan_mm_to_pt(mm: f32) callconv(.c) usize {
    return @intFromFloat(@round(mm / MM_PER_PT));
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export fn arcan_math_init() callconv(.c) void {
    default_quat = build_quat_taitbryan(0, 0, 0);
}
