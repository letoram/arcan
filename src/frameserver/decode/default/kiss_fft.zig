// Kiss FFT — Pure Zig port
// Original: Copyright (c) 2003-2010, Mark Borgerding. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
// https://github.com/mborgerding/kissfft
//
// Floating-point complex FFT + real-optimized FFT (kiss_fftr).
// No SIMD, no fixed-point — just the float path used by arcan's decode_av.

const std = @import("std");

pub const Scalar = f32;

pub const Cpx = extern struct {
    r: Scalar = 0,
    i: Scalar = 0,
};

const MAXFACTORS = 32;

/// Opaque FFT state. Allocated as a single contiguous block:
/// [FftState header] [twiddles: nfft × Cpx]
pub const FftState = struct {
    nfft: i32,
    inverse: bool,
    factors: [2 * MAXFACTORS]i32 = [_]i32{0} ** (2 * MAXFACTORS),
    twiddles: [*]Cpx, // points right after this struct in the allocation

    fn memneeded(nfft: usize) usize {
        return @sizeOf(FftState) + @sizeOf(Cpx) * nfft;
    }
};

/// Opaque real-FFT state. Single contiguous block:
/// [FftrState header] [FftState for nfft/2] [tmpbuf: nfft/2 × Cpx] [super_twiddles: nfft/4 × Cpx]
pub const FftrState = struct {
    substate: *FftState,
    tmpbuf: [*]Cpx,
    super_twiddles: [*]Cpx,
};

// Allocation helpers (match original C: malloc/free)

fn cmalloc(size: usize) ?[*]u8 {
    const ptr = std.c.malloc(size) orelse return null;
    return @ptrCast(ptr);
}

fn cfree(ptr: anytype) void {
    std.c.free(@ptrCast(ptr));
}

// Complex arithmetic

inline fn cMul(a: Cpx, b: Cpx) Cpx {
    return .{ .r = a.r * b.r - a.i * b.i, .i = a.r * b.i + a.i * b.r };
}

inline fn cAdd(a: Cpx, b: Cpx) Cpx {
    return .{ .r = a.r + b.r, .i = a.i + b.i };
}

inline fn cSub(a: Cpx, b: Cpx) Cpx {
    return .{ .r = a.r - b.r, .i = a.i - b.i };
}

inline fn cMulScalar(c: Cpx, s: Scalar) Cpx {
    return .{ .r = c.r * s, .i = c.i * s };
}

inline fn cExp(phase: f64) Cpx {
    return .{
        .r = @floatCast(@cos(phase)),
        .i = @floatCast(@sin(phase)),
    };
}

// Butterfly stages

fn bfly2(fout: [*]Cpx, fstride: usize, st: *const FftState, m: usize) void {
    var f = fout;
    var f2 = fout + m;
    var tw: [*]Cpx = st.twiddles;
    var j: usize = m;
    while (j > 0) : (j -= 1) {
        const t = cMul(f2[0], tw[0]);
        f2[0] = cSub(f[0], t);
        f[0] = cAdd(f[0], t);
        tw += fstride;
        f += 1;
        f2 += 1;
    }
}

fn bfly4(fout: [*]Cpx, fstride: usize, st: *const FftState, m: usize) void {
    var tw1: [*]Cpx = st.twiddles;
    var tw2: [*]Cpx = st.twiddles;
    var tw3: [*]Cpx = st.twiddles;
    var f = fout;
    var k: usize = m;
    while (k > 0) : (k -= 1) {
        var scratch: [6]Cpx = undefined;
        scratch[0] = cMul(f[m], tw1[0]);
        scratch[1] = cMul(f[2 * m], tw2[0]);
        scratch[2] = cMul(f[3 * m], tw3[0]);

        scratch[5] = cSub(f[0], scratch[1]);
        f[0] = cAdd(f[0], scratch[1]);
        scratch[3] = cAdd(scratch[0], scratch[2]);
        scratch[4] = cSub(scratch[0], scratch[2]);
        f[2 * m] = cSub(f[0], scratch[3]);
        tw1 += fstride;
        tw2 += fstride * 2;
        tw3 += fstride * 3;
        f[0] = cAdd(f[0], scratch[3]);

        if (st.inverse) {
            f[m] = .{ .r = scratch[5].r - scratch[4].i, .i = scratch[5].i + scratch[4].r };
            f[3 * m] = .{ .r = scratch[5].r + scratch[4].i, .i = scratch[5].i - scratch[4].r };
        } else {
            f[m] = .{ .r = scratch[5].r + scratch[4].i, .i = scratch[5].i - scratch[4].r };
            f[3 * m] = .{ .r = scratch[5].r - scratch[4].i, .i = scratch[5].i + scratch[4].r };
        }
        f += 1;
    }
}

fn bfly3(fout: [*]Cpx, fstride: usize, st: *const FftState, m: usize) void {
    var tw1: [*]Cpx = st.twiddles;
    var tw2: [*]Cpx = st.twiddles;
    const epi3 = st.twiddles[fstride * m];
    var f = fout;
    var k: usize = m;
    while (k > 0) : (k -= 1) {
        var scratch: [5]Cpx = undefined;
        scratch[1] = cMul(f[m], tw1[0]);
        scratch[2] = cMul(f[2 * m], tw2[0]);
        scratch[3] = cAdd(scratch[1], scratch[2]);
        scratch[0] = cSub(scratch[1], scratch[2]);
        tw1 += fstride;
        tw2 += fstride * 2;

        f[m].r = f[0].r - scratch[3].r * 0.5;
        f[m].i = f[0].i - scratch[3].i * 0.5;

        scratch[0] = cMulScalar(scratch[0], epi3.i);

        f[0] = cAdd(f[0], scratch[3]);

        f[2 * m].r = f[m].r + scratch[0].i;
        f[2 * m].i = f[m].i - scratch[0].r;

        f[m].r -= scratch[0].i;
        f[m].i += scratch[0].r;

        f += 1;
    }
}

fn bfly5(fout: [*]Cpx, fstride: usize, st: *const FftState, m: usize) void {
    const tw = st.twiddles;
    const ya = tw[fstride * m];
    const yb = tw[fstride * 2 * m];

    var f0 = fout;
    var f1 = fout + m;
    var f2 = fout + 2 * m;
    var f3 = fout + 3 * m;
    var f4 = fout + 4 * m;

    var u: usize = 0;
    while (u < m) : (u += 1) {
        var scratch: [13]Cpx = undefined;
        scratch[0] = f0[0];

        scratch[1] = cMul(f1[0], tw[u * fstride]);
        scratch[2] = cMul(f2[0], tw[2 * u * fstride]);
        scratch[3] = cMul(f3[0], tw[3 * u * fstride]);
        scratch[4] = cMul(f4[0], tw[4 * u * fstride]);

        scratch[7] = cAdd(scratch[1], scratch[4]);
        scratch[10] = cSub(scratch[1], scratch[4]);
        scratch[8] = cAdd(scratch[2], scratch[3]);
        scratch[9] = cSub(scratch[2], scratch[3]);

        f0[0].r += scratch[7].r + scratch[8].r;
        f0[0].i += scratch[7].i + scratch[8].i;

        scratch[5].r = scratch[0].r + scratch[7].r * ya.r + scratch[8].r * yb.r;
        scratch[5].i = scratch[0].i + scratch[7].i * ya.r + scratch[8].i * yb.r;

        scratch[6].r = scratch[10].i * ya.i + scratch[9].i * yb.i;
        scratch[6].i = -scratch[10].r * ya.i - scratch[9].r * yb.i;

        f1[0] = cSub(scratch[5], scratch[6]);
        f4[0] = cAdd(scratch[5], scratch[6]);

        scratch[11].r = scratch[0].r + scratch[7].r * yb.r + scratch[8].r * ya.r;
        scratch[11].i = scratch[0].i + scratch[7].i * yb.r + scratch[8].i * ya.r;
        scratch[12].r = -scratch[10].i * yb.i + scratch[9].i * ya.i;
        scratch[12].i = scratch[10].r * yb.i - scratch[9].r * ya.i;

        f2[0] = cAdd(scratch[11], scratch[12]);
        f3[0] = cSub(scratch[11], scratch[12]);

        f0 += 1;
        f1 += 1;
        f2 += 1;
        f3 += 1;
        f4 += 1;
    }
}

fn bflyGeneric(fout: [*]Cpx, fstride: usize, st: *const FftState, m: usize, p: usize) void {
    const tw = st.twiddles;
    const norig: usize = @intCast(st.nfft);

    const scratch_ptr = cmalloc(@sizeOf(Cpx) * p) orelse return;
    defer cfree(scratch_ptr);
    const scratch: [*]Cpx = @ptrCast(@alignCast(scratch_ptr));

    var u: usize = 0;
    while (u < m) : (u += 1) {
        var k = u;
        for (0..p) |q1| {
            scratch[q1] = fout[k];
            k += m;
        }

        k = u;
        for (0..p) |_| {
            var twidx: usize = 0;
            fout[k] = scratch[0];
            for (1..p) |q| {
                twidx += fstride * k;
                if (twidx >= norig) twidx -= norig;
                const t = cMul(scratch[q], tw[twidx]);
                fout[k] = cAdd(fout[k], t);
            }
            k += m;
        }
    }
}

fn kfWork(fout: [*]Cpx, f: [*]const Cpx, fstride: usize, in_stride: usize, factors: [*]i32, st: *const FftState) void {
    const p: usize = @intCast(factors[0]);
    const m: usize = @intCast(factors[1]);
    const fout_end = fout + p * m;

    if (m == 1) {
        var fo = fout;
        var fi = f;
        while (fo != fout_end) {
            fo[0] = fi[0];
            fi += fstride * in_stride;
            fo += 1;
        }
    } else {
        var fo = fout;
        var fi = f;
        while (fo != fout_end) {
            kfWork(fo, fi, fstride * p, in_stride, factors + 2, st);
            fi += fstride * in_stride;
            fo += m;
        }
    }

    switch (p) {
        2 => bfly2(fout, fstride, st, m),
        3 => bfly3(fout, fstride, st, m),
        4 => bfly4(fout, fstride, st, m),
        5 => bfly5(fout, fstride, st, m),
        else => bflyGeneric(fout, fstride, st, m, p),
    }
}

fn kfFactor(n_in: i32, facbuf: [*]i32) void {
    var n = n_in;
    var p: i32 = 4;
    const floor_sqrt: f64 = @floor(@sqrt(@as(f64, @floatFromInt(n))));
    var fb = facbuf;

    while (true) {
        while (@rem(n, p) != 0) {
            switch (p) {
                4 => p = 2,
                2 => p = 3,
                else => p += 2,
            }
            if (@as(f64, @floatFromInt(p)) > floor_sqrt)
                p = n;
        }
        n = @divTrunc(n, p);
        fb[0] = p;
        fb[1] = n;
        fb += 2;
        if (n <= 1) break;
    }
}

// Public API

/// Allocate and initialize an FFT config for the given size.
/// If `mem` is non-null and `lenmem.*` is large enough, uses that buffer.
/// If `lenmem` is non-null and buffer is too small, returns null and sets `lenmem.*`.
/// Otherwise allocates with malloc. Result can be freed with free().
pub fn alloc(nfft: i32, inverse_fft: bool, mem: ?*anyopaque, lenmem: ?*usize) ?*FftState {
    const n: usize = @intCast(nfft);
    const memneeded = FftState.memneeded(n);

    var st: ?*FftState = null;
    if (lenmem == null) {
        const raw = cmalloc(memneeded) orelse return null;
        st = @ptrCast(@alignCast(raw));
    } else {
        if (mem != null and lenmem.?.* >= memneeded)
            st = @ptrCast(@alignCast(@as([*]u8, @ptrCast(mem.?))));
        lenmem.?.* = memneeded;
    }

    const s = st orelse return null;
    s.nfft = nfft;
    s.inverse = inverse_fft;

    // Twiddles start right after the struct
    s.twiddles = @ptrCast(@alignCast(@as([*]u8, @ptrCast(s)) + @sizeOf(FftState)));

    const pi = std.math.pi;
    for (0..n) |i| {
        var phase: f64 = -2.0 * pi * @as(f64, @floatFromInt(i)) / @as(f64, @floatFromInt(nfft));
        if (inverse_fft) phase = -phase;
        s.twiddles[i] = cExp(phase);
    }

    kfFactor(nfft, &s.factors);
    return s;
}

/// Perform a complex FFT with stride.
pub fn fftStride(st: *FftState, fin: [*]const Cpx, fout: [*]Cpx, in_stride: usize) void {
    if (fin == fout) {
        const n: usize = @intCast(st.nfft);
        const raw = cmalloc(@sizeOf(Cpx) * n) orelse return;
        defer cfree(raw);
        const tmpbuf: [*]Cpx = @ptrCast(@alignCast(raw));
        kfWork(tmpbuf, fin, 1, in_stride, &st.factors, st);
        @memcpy(fout[0..n], tmpbuf[0..n]);
    } else {
        kfWork(fout, fin, 1, in_stride, &st.factors, st);
    }
}

/// Perform a complex FFT.
pub fn fft(cfg: *FftState, fin: [*]const Cpx, fout: [*]Cpx) void {
    fftStride(cfg, fin, fout, 1);
}

/// No-op for compatibility (original freed cached state).
pub fn cleanup() void {}

/// Returns the smallest integer k >= n such that k is factorable by 2, 3, and 5 only.
pub fn nextFastSize(n_in: i32) i32 {
    var n = n_in;
    while (true) {
        var m = n;
        while (@rem(m, 2) == 0) m = @divTrunc(m, 2);
        while (@rem(m, 3) == 0) m = @divTrunc(m, 3);
        while (@rem(m, 5) == 0) m = @divTrunc(m, 5);
        if (m <= 1) break;
        n += 1;
    }
    return n;
}

// Real FFT

/// Allocate a real-FFT config. nfft must be even.
pub fn fftrAlloc(nfft: i32, inverse_fft: bool, mem: ?*anyopaque, lenmem: ?*usize) ?*FftrState {
    if (@rem(nfft, 2) != 0) return null;

    const half_n = @divTrunc(nfft, 2);
    const half_u: usize = @intCast(half_n);

    var subsize: usize = 0;
    _ = alloc(half_n, inverse_fft, null, &subsize);

    const memneeded = @sizeOf(FftrState) + subsize + @sizeOf(Cpx) * (half_u * 3 / 2);

    var st: ?*FftrState = null;
    if (lenmem == null) {
        const raw = cmalloc(memneeded) orelse return null;
        st = @ptrCast(@alignCast(raw));
    } else {
        if (mem != null and lenmem.?.* >= memneeded)
            st = @ptrCast(@alignCast(@as([*]u8, @ptrCast(mem.?))));
        lenmem.?.* = memneeded;
    }

    const s = st orelse return null;
    const base: [*]u8 = @ptrCast(s);

    // Substate lives right after the FftrState header
    s.substate = @ptrCast(@alignCast(base + @sizeOf(FftrState)));
    _ = alloc(half_n, inverse_fft, @ptrCast(base + @sizeOf(FftrState)), &subsize);

    // tmpbuf lives after substate
    s.tmpbuf = @ptrCast(@alignCast(base + @sizeOf(FftrState) + subsize));

    // super_twiddles live after tmpbuf
    s.super_twiddles = s.tmpbuf + half_u;

    const pi = std.math.pi;
    for (0..half_u / 2) |i| {
        var phase: f64 = -pi * (@as(f64, @floatFromInt(i + 1)) / @as(f64, @floatFromInt(half_n)) + 0.5);
        if (inverse_fft) phase = -phase;
        s.super_twiddles[i] = cExp(phase);
    }
    return s;
}

/// Forward real FFT: nfft real samples → nfft/2+1 complex bins.
pub fn fftr(st: *FftrState, timedata: [*]const Scalar, freqdata: [*]Cpx) void {
    const sub = st.substate;
    if (sub.inverse) return; // usage error

    const ncfft: usize = @intCast(sub.nfft);

    // Perform complex FFT on interleaved real/imag pairs
    fft(sub, @ptrCast(timedata), st.tmpbuf);

    const tdc_r = st.tmpbuf[0].r;
    const tdc_i = st.tmpbuf[0].i;
    freqdata[0].r = tdc_r + tdc_i;
    freqdata[ncfft].r = tdc_r - tdc_i;
    freqdata[ncfft].i = 0;
    freqdata[0].i = 0;

    var k: usize = 1;
    while (k <= ncfft / 2) : (k += 1) {
        const fpk = st.tmpbuf[k];
        const fpnk = Cpx{ .r = st.tmpbuf[ncfft - k].r, .i = -st.tmpbuf[ncfft - k].i };

        const f1k = cAdd(fpk, fpnk);
        const f2k = cSub(fpk, fpnk);
        const tw = cMul(f2k, st.super_twiddles[k - 1]);

        freqdata[k].r = (f1k.r + tw.r) * 0.5;
        freqdata[k].i = (f1k.i + tw.i) * 0.5;
        freqdata[ncfft - k].r = (f1k.r - tw.r) * 0.5;
        freqdata[ncfft - k].i = (tw.i - f1k.i) * 0.5;
    }
}

/// Inverse real FFT: nfft/2+1 complex bins → nfft real samples.
pub fn fftri(st: *FftrState, freqdata: [*]const Cpx, timedata: [*]Scalar) void {
    const sub = st.substate;
    if (!sub.inverse) return; // usage error

    const ncfft: usize = @intCast(sub.nfft);

    st.tmpbuf[0].r = freqdata[0].r + freqdata[ncfft].r;
    st.tmpbuf[0].i = freqdata[0].r - freqdata[ncfft].r;

    var k: usize = 1;
    while (k <= ncfft / 2) : (k += 1) {
        const fk = freqdata[k];
        const fnkc = Cpx{ .r = freqdata[ncfft - k].r, .i = -freqdata[ncfft - k].i };

        const fek = cAdd(fk, fnkc);
        const tmp = cSub(fk, fnkc);
        const fok = cMul(tmp, st.super_twiddles[k - 1]);
        st.tmpbuf[k] = cAdd(fek, fok);
        st.tmpbuf[ncfft - k] = cSub(fek, fok);
        st.tmpbuf[ncfft - k].i *= -1;
    }
    fft(sub, st.tmpbuf, @ptrCast(timedata));
}

// C ABI exports (drop-in replacement for kiss_fft.h / kiss_fftr.h)

export fn kiss_fft_alloc(nfft: c_int, inverse_fft: c_int, mem: ?*anyopaque, lenmem: ?*usize) ?*FftState {
    return alloc(@intCast(nfft), inverse_fft != 0, mem, lenmem);
}

export fn kiss_fft(cfg: *FftState, fin: [*]const Cpx, fout: [*]Cpx) void {
    fft(cfg, fin, fout);
}

export fn kiss_fft_stride(cfg: *FftState, fin: [*]const Cpx, fout: [*]Cpx, fin_stride: c_int) void {
    fftStride(cfg, fin, fout, @intCast(fin_stride));
}

export fn kiss_fft_cleanup() void {
    cleanup();
}

export fn kiss_fft_next_fast_size(n: c_int) c_int {
    return nextFastSize(@intCast(n));
}

export fn kiss_fftr_alloc(nfft: c_int, inverse_fft: c_int, mem: ?*anyopaque, lenmem: ?*usize) ?*FftrState {
    return fftrAlloc(@intCast(nfft), inverse_fft != 0, mem, lenmem);
}

export fn kiss_fftr(st: *FftrState, timedata: [*]const Scalar, freqdata: [*]Cpx) void {
    fftr(st, timedata, freqdata);
}

export fn kiss_fftri(st: *FftrState, freqdata: [*]const Cpx, timedata: [*]Scalar) void {
    fftri(st, freqdata, timedata);
}

// Tests

test "alloc and basic forward FFT" {
    const N = 8;
    const cfg = alloc(N, false, null, null) orelse return error.AllocFailed;
    defer cfree(cfg);

    var input: [N]Cpx = undefined;
    var output: [N]Cpx = undefined;

    // DC signal: all ones → energy at bin 0
    for (&input) |*cpx| cpx.* = .{ .r = 1.0, .i = 0.0 };
    fft(cfg, &input, &output);

    try std.testing.expectApproxEqAbs(output[0].r, @as(f32, N), 1e-5);
    try std.testing.expectApproxEqAbs(output[0].i, @as(f32, 0), 1e-5);
    for (output[1..]) |cpx| {
        try std.testing.expectApproxEqAbs(cpx.r, 0.0, 1e-5);
        try std.testing.expectApproxEqAbs(cpx.i, 0.0, 1e-5);
    }
}

test "forward then inverse recovers original" {
    const N = 16;
    const fwd = alloc(N, false, null, null) orelse return error.AllocFailed;
    const inv = alloc(N, true, null, null) orelse return error.AllocFailed;
    defer cfree(fwd);
    defer cfree(inv);

    var input: [N]Cpx = undefined;
    var freq: [N]Cpx = undefined;
    var recovered: [N]Cpx = undefined;

    for (&input, 0..) |*cpx, i| {
        cpx.* = .{ .r = @floatFromInt(i), .i = 0 };
    }

    fft(fwd, &input, &freq);
    fft(inv, &freq, &recovered);

    // IFFT result is scaled by N
    for (0..N) |i| {
        try std.testing.expectApproxEqAbs(recovered[i].r / @as(f32, N), input[i].r, 1e-4);
        try std.testing.expectApproxEqAbs(recovered[i].i / @as(f32, N), input[i].i, 1e-4);
    }
}

test "real FFT forward (impulse → flat spectrum)" {
    const N = 16;
    const cfg = fftrAlloc(N, false, null, null) orelse return error.AllocFailed;
    defer cfree(cfg);

    var timedata = [_]Scalar{0} ** N;
    var freqdata: [N / 2 + 1]Cpx = undefined;

    timedata[0] = 1.0;
    fftr(cfg, &timedata, &freqdata);

    for (&freqdata) |cpx| {
        try std.testing.expectApproxEqAbs(cpx.r, 1.0, 1e-5);
        try std.testing.expectApproxEqAbs(cpx.i, 0.0, 1e-5);
    }
}

test "real FFT round-trip (forward + inverse)" {
    const N = 32;
    const fwd_cfg = fftrAlloc(N, false, null, null) orelse return error.AllocFailed;
    const inv_cfg = fftrAlloc(N, true, null, null) orelse return error.AllocFailed;
    defer cfree(fwd_cfg);
    defer cfree(inv_cfg);

    var timedata: [N]Scalar = undefined;
    for (&timedata, 0..) |*v, i| v.* = @sin(@as(f32, @floatFromInt(i)) * 0.3);

    var freqdata: [N / 2 + 1]Cpx = undefined;
    fftr(fwd_cfg, &timedata, &freqdata);

    var recovered: [N]Scalar = undefined;
    fftri(inv_cfg, &freqdata, &recovered);

    // kiss_fftr round-trip scales by N (forward = N/2 complex FFT, inverse = N/2 complex FFT)
    const scale: f32 = @as(f32, N);
    for (0..N) |i| {
        try std.testing.expectApproxEqAbs(recovered[i] / scale, timedata[i], 1e-4);
    }
}

test "next fast size" {
    try std.testing.expectEqual(nextFastSize(1), 1);
    try std.testing.expectEqual(nextFastSize(2), 2);
    try std.testing.expectEqual(nextFastSize(7), 8);
    try std.testing.expectEqual(nextFastSize(13), 15);
    try std.testing.expectEqual(nextFastSize(1000), 1000);
}
