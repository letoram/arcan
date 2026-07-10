// a12_encode.zig — Zig port of a12_encode.c
//
// A12 protocol video/audio frame encoding.
// Handles packing of raw pixel data (RGB, RGBA, RGB565), ZSTD compression
// (I-frame and delta P-frame), TPACK text encoding, H264 passthrough, and
// raw audio frames. All functions produce control headers + chunked data
// packets for the A12 wire protocol.
//
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Keeps the `c.X` spellings used below. Each alias routes to the
// appropriate hand-written replacement module (zero `@cImport` left).
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const libc = @import("posix");
const c = struct {
    pub const FILE = libc.FILE;
    pub const fprintf = libc.fprintf;
    pub const free = libc.free;
    pub const malloc = libc.malloc;
    pub const shmif_asample = shmif.shmif_asample;
    pub const shmif_pixel = shmif.shmif_pixel;
    pub const struct_a12_aframe_cfg = a12.struct_a12_aframe_cfg;
    pub const struct_a12_aframe_opts = a12.struct_a12_aframe_opts;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_vframe_opts = a12.struct_a12_vframe_opts;
    pub const struct_shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;
};

// Raster constants from raster_const.h

const raster_cell_sz: usize = 12;
const raster_hdr_sz: usize = 16;
const raster_line_sz: usize = 9;

// Protocol constants

const CONTROL_PACKET_SIZE: usize = 128;
const COMMAND_VIDEOFRAME: u8 = 4;
const COMMAND_AUDIOFRAME: u8 = 5;
const ZSTD_VIDEO_LEVEL: c_int = 2;

const STATE_CONTROL_PACKET: c_int = 1;
const STATE_AUDIO_PACKET: c_int = 3;
const STATE_VIDEO_PACKET: c_int = 4;

const POSTPROCESS_VIDEO_RGBA: c_int = 0;
const POSTPROCESS_VIDEO_RGB: c_int = 1;
const POSTPROCESS_VIDEO_RGB565: c_int = 2;
const POSTPROCESS_VIDEO_H264: c_int = 5;
const POSTPROCESS_VIDEO_TZSTD: c_int = 7;
const POSTPROCESS_VIDEO_DZSTD: c_int = 8;
const POSTPROCESS_VIDEO_ZSTD: c_int = 9;

// ZSTD compression parameter for number of worker threads
const ZSTD_c_nbWorkers: c_int = 400;

// Trace group constants

const A12_TRACE_VIDEO: c_int = 1;
const A12_TRACE_SYSTEM: c_int = 4;
const A12_TRACE_ALLOC: c_int = 128;
const A12_TRACE_VDETAIL: c_int = 512;

// Opaque type aliases

const a12_state = c.struct_a12_state;
const shmifsrv_vbuffer = c.struct_shmifsrv_vbuffer;
const shmif_pixel = c.shmif_pixel; // u32
const shmif_asample = c.shmif_asample; // i16
const a12_vframe_opts = c.struct_a12_vframe_opts;
const a12_aframe_cfg = c.struct_a12_aframe_cfg;
const a12_aframe_opts = c.struct_a12_aframe_opts;

// ZSTD extern declarations

const ZSTD_CCtx = opaque {};

extern "c" fn ZSTD_createCCtx() ?*ZSTD_CCtx;
extern "c" fn ZSTD_freeCCtx(cctx: ?*ZSTD_CCtx) usize;
extern "c" fn ZSTD_CCtx_setParameter(cctx: *ZSTD_CCtx, param: c_int, value: c_int) usize;
extern "c" fn ZSTD_compressBound(srcSize: usize) usize;
extern "c" fn ZSTD_compressCCtx(
    cctx: *ZSTD_CCtx,
    dst: [*]u8,
    dstCapacity: usize,
    src: [*]const u8,
    srcSize: usize,
    compressionLevel: c_int,
) usize;
extern "c" fn ZSTD_isError(code: usize) c_uint;
extern "c" fn ZSTD_getErrorName(code: usize) [*:0]const u8;

// Extern C functions from a12

extern "c" fn a12int_header_size(kind: c_int) usize;
extern "c" fn a12int_append_out(
    S: *a12_state,
    @"type": u8,
    out: [*]const u8,
    out_sz: usize,
    prepend: ?[*]u8,
    prepend_sz: usize,
) void;
extern "c" fn a12int_step_vstream(S: *a12_state, id: u32) void;
extern "c" fn arcan_random(dst: [*]u8, ntc: usize) void;

// Trace is a C macro — we extern the globals and reimplement
extern "c" var a12_trace_targets: c_int;
extern "c" var a12_trace_dst: ?*c.FILE;
extern "c" fn a12int_group_tostr(group: c_int) [*:0]const u8;
extern "c" fn arcan_timemillis() c_ulonglong;

// Byte-offset accessors for opaque structs
// Offsets computed for Linux aarch64 (see compute_offsets output).
// a12_state, a12_channel, and shmifsrv_vbuffer are opaque due to bitfields.

const A12State = struct {
    const o_last_seen_seqnr: usize = 72;
    const o_channels: usize = 384;
    const o_opts: usize = 0;

    const sizeof_channel: usize = 496;
};

const A12Channel = struct {
    const o_acc: usize = 288;
    const o_compression: usize = 416;
    const o_zstd: usize = 424;
};

// Layout matches the Zig `ShmifsrvVbuffer` extern struct in
// src/shmif/arcan_shmif_server.zig, where VbufFlags is a 7-byte
// extern struct (one u8 per former-bitfield bool — see the comment
// on VbufFlags there for why). Offsets below must update in lockstep
// if that layout changes; a drift silently reads the wrong field and
// a12int_encode_tz/etc. send sw/sh of zero (verified: swapped 0/640
// across the wire, decoder rejects frame with EINVAL).
const VBuffer = struct {
    const o_buffer: usize = 8;
    const o_flags: usize = 16;
    const o_buffer_sz: usize = 32;
    const o_w: usize = 40;
    const o_h: usize = 48;
    const o_pitch: usize = 56;
    const o_stride: usize = 64;
    const sizeof_vbuffer: usize = 136;

    // flags bitfield masks (byte 0 of flags struct)
    const FLAG_ORIGO_LL: u8 = 0x01;
};

const CtxOpts = struct {
    const o_enc_sink: usize = 128;
    const o_enc_sink_tag: usize = 136;
};

// Generic offset helpers

fn ptrAdd(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

fn readField(comptime T: type, base: *anyopaque, off: usize) T {
    return @as(*align(1) const T, @ptrCast(ptrAdd(base, off))).*;
}

fn writeField(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    @as(*align(1) T, @ptrCast(ptrAdd(base, off))).* = val;
}

fn getBitfield(base: *anyopaque, off: usize, mask: u8) bool {
    return (ptrAdd(base, off)[0] & mask) != 0;
}

// a12_state field accessors

fn state_last_seen_seqnr(S: *a12_state) u64 {
    return readField(u64, @ptrCast(S), A12State.o_last_seen_seqnr);
}

fn state_channel_ptr(S: *a12_state, ch: usize) *anyopaque {
    const base = ptrAdd(@ptrCast(S), A12State.o_channels);
    return @ptrCast(base + ch * A12State.sizeof_channel);
}

fn state_opts_ptr(S: *a12_state) *anyopaque {
    const opts_p = readField(?*anyopaque, @ptrCast(S), A12State.o_opts);
    return opts_p.?;
}

// a12_channel field accessors

fn channel_zstd(ch_ptr: *anyopaque) ?*ZSTD_CCtx {
    return readField(?*ZSTD_CCtx, ch_ptr, A12Channel.o_zstd);
}

fn channel_set_zstd(ch_ptr: *anyopaque, val: ?*ZSTD_CCtx) void {
    writeField(?*ZSTD_CCtx, ch_ptr, A12Channel.o_zstd, val);
}

fn channel_compression(ch_ptr: *anyopaque) ?[*]u8 {
    return readField(?[*]u8, ch_ptr, A12Channel.o_compression);
}

fn channel_set_compression(ch_ptr: *anyopaque, val: ?[*]u8) void {
    writeField(?[*]u8, ch_ptr, A12Channel.o_compression, val);
}

fn channel_acc_ptr(ch_ptr: *anyopaque) *anyopaque {
    return @ptrCast(ptrAdd(ch_ptr, A12Channel.o_acc));
}

// shmifsrv_vbuffer field accessors

fn vb_buffer(vb: *anyopaque) ?[*]shmif_pixel {
    return readField(?[*]shmif_pixel, vb, VBuffer.o_buffer);
}

fn vb_buffer_bytes(vb: *anyopaque) ?[*]u8 {
    return readField(?[*]u8, vb, VBuffer.o_buffer);
}

fn vb_set_buffer(vb: *anyopaque, val: ?[*]shmif_pixel) void {
    writeField(?[*]shmif_pixel, vb, VBuffer.o_buffer, val);
}

fn vb_buffer_sz(vb: *anyopaque) usize {
    return readField(usize, vb, VBuffer.o_buffer_sz);
}

fn vb_w(vb: *anyopaque) usize {
    return readField(usize, vb, VBuffer.o_w);
}

fn vb_h(vb: *anyopaque) usize {
    return readField(usize, vb, VBuffer.o_h);
}

fn vb_pitch(vb: *anyopaque) usize {
    return readField(usize, vb, VBuffer.o_pitch);
}

fn vb_stride(vb: *anyopaque) usize {
    return readField(usize, vb, VBuffer.o_stride);
}

fn vb_flags_origo_ll(vb: *anyopaque) bool {
    return getBitfield(vb, VBuffer.o_flags, VBuffer.FLAG_ORIGO_LL);
}

// opts field accessors

const EncSinkFn = *const fn (
    buf: [*]u8,
    buf_sz: usize,
    method: c_int,
    flags: c_int,
    tag: ?*anyopaque,
) callconv(.c) void;

fn opts_enc_sink(opts_ptr: *anyopaque) ?EncSinkFn {
    return readField(?EncSinkFn, opts_ptr, CtxOpts.o_enc_sink);
}

fn opts_enc_sink_tag(opts_ptr: *anyopaque) ?*anyopaque {
    return readField(?*anyopaque, opts_ptr, CtxOpts.o_enc_sink_tag);
}

// Native Zig helpers (replacing C static inline / macros)

fn pack_u64(src: u64, outb: [*]u8) void {
    outb[0] = @truncate(src >> 0);
    outb[1] = @truncate(src >> 8);
    outb[2] = @truncate(src >> 16);
    outb[3] = @truncate(src >> 24);
    outb[4] = @truncate(src >> 32);
    outb[5] = @truncate(src >> 40);
    outb[6] = @truncate(src >> 48);
    outb[7] = @truncate(src >> 56);
}

fn pack_u32(src: u32, outb: [*]u8) void {
    outb[0] = @truncate(src >> 0);
    outb[1] = @truncate(src >> 8);
    outb[2] = @truncate(src >> 16);
    outb[3] = @truncate(src >> 24);
}

fn pack_u16(src: u16, outb: [*]u8) void {
    outb[0] = @truncate(src >> 0);
    outb[1] = @truncate(src >> 8);
}

fn pack_s16(src: i16, outb: [*]u8) void {
    const u: u16 = @bitCast(src);
    outb[0] = @truncate(u >> 0);
    outb[1] = @truncate(u >> 8);
}

fn unpack_u32(dst: *u32, inbuf: [*]const u8) void {
    dst.* = @as(u32, inbuf[0]) << 0 |
        @as(u32, inbuf[1]) << 8 |
        @as(u32, inbuf[2]) << 16 |
        @as(u32, inbuf[3]) << 24;
}

fn unpack_u16(dst: *u16, inbuf: [*]const u8) void {
    dst.* = @as(u16, inbuf[0]) << 0 |
        @as(u16, inbuf[1]) << 8;
}

/// SHMIF_RGBA_DECOMP — decompose a shmif_pixel (BGRA u32) into r, g, b, a
fn shmif_rgba_decomp(val: shmif_pixel, r: *u8, g: *u8, b: *u8, a: *u8) void {
    b.* = @truncate(val & 0x000000ff);
    g.* = @truncate((val & 0x0000ff00) >> 8);
    r.* = @truncate((val & 0x00ff0000) >> 16);
    a.* = @truncate((val & 0xff000000) >> 24);
}

// Trace helper (replaces the a12int_trace C macro)
// The C macro uses varargs printf; Zig reimplements with comptime format.
// a12_state.tracetag is at byte offset 25 (char[16]).

const A12State_o_tracetag: usize = 25;

fn trace(S: *a12_state, group: c_int, comptime fmt: []const u8, args: anytype) void {
    const dst = a12_trace_dst orelse return;
    if ((a12_trace_targets & group) == 0) return;

    const tag: [*:0]const u8 = @ptrCast(ptrAdd(@ptrCast(S), A12State_o_tracetag));

    var buf: [512]u8 = undefined;
    const msg = std.fmt.bufPrint(&buf, fmt, args) catch return;

    // Reproduce the C trace format: tag=...:ts=...:group=...:function=...:...
    _ = c.fprintf(dst, "tag=%s:ts=%lld:group=%s:function=a12_encode:%.*s\n",
        tag,
        arcan_timemillis(),
        a12int_group_tostr(group),
        @as(c_int, @intCast(msg.len)),
        msg.ptr,
    );
}

// Copy shmifsrv_vbuffer contents (memcpy the raw struct bytes)

fn copy_vbuffer(dst: *anyopaque, src: *const anyopaque) void {
    const d: [*]u8 = @ptrCast(dst);
    const s: [*]const u8 = @ptrCast(src);
    @memcpy(d[0..VBuffer.sizeof_vbuffer], s[0..VBuffer.sizeof_vbuffer]);
}

// Core encoding functions

/// Build the control packet header for a video frame
fn a12int_vframehdr_build(
    S: *a12_state,
    buf: [*]u8,
    last_seen: u64,
    chid: u8,
    vtype: c_int,
    sid: u32,
    sw: u16,
    sh: u16,
    w: u16,
    h: u16,
    x: u16,
    y: u16,
    len: u32,
    exp_len: u32,
    commit: bool,
    flags: u8,
) void {
    trace(S, A12_TRACE_VDETAIL,
        "kind=header:ch={d}:type={d}:stream={d}:sw={d}:sh={d}:w={d}:h={d}:x={d}:y={d}:len={d}:exp_len={d}",
        .{
            chid, vtype, sid, sw, sh, w, h, x, y, len, exp_len,
        });

    @memset(buf[0..CONTROL_PACKET_SIZE], 0);
    pack_u64(last_seen, @ptrCast(&buf[0]));
    arcan_random(buf + 8, 8); // 0..8 entropy

    buf[16] = chid; // [16] : channel-id
    buf[17] = COMMAND_VIDEOFRAME; // [17] : command
    pack_u32(sid, buf + 18); // [18..21] : stream-id
    buf[22] = @intCast(vtype); // [22] : type
    pack_u16(sw, buf + 23); // [23..24] : surfacew
    pack_u16(sh, buf + 25); // [25..26] : surfaceh
    pack_u16(x, buf + 27); // [27..28] : startx
    pack_u16(y, buf + 29); // [29..30] : starty
    pack_u16(w, buf + 31); // [31..32] : framew
    pack_u16(h, buf + 33); // [33..34] : frameh
    pack_u32(len, buf + 36); // [36..39] : length
    pack_u32(exp_len, buf + 40); // [40..43] : exp-length

    buf[35] = flags; // [35] : dataflags: uint8

    // [44] : commit on completion
    buf[44] = if (commit) 1 else 0;
}

/// Split a binary stream into chunks with per-chunk headers
fn chunk_pack(
    S: *a12_state,
    ptype: c_int,
    chid: u8,
    buf: [*]u8,
    buf_sz: usize,
    chunk_sz: usize,
) void {
    const n_chunks = buf_sz / chunk_sz;

    const hdr_sz = a12int_header_size(ptype);
    // Use stack buffer for the small header (max 7 bytes for video/audio/blob)
    var outb: [7]u8 = undefined;
    std.debug.assert(hdr_sz <= outb.len);

    outb[0] = chid; // [0] : channel id
    pack_u32(0xbacabaca, @ptrCast(&outb[1])); // [1..4] : stream
    pack_u16(@intCast(chunk_sz), @ptrCast(&outb[5])); // [5..6] : length

    for (0..n_chunks) |i| {
        a12int_append_out(S, @intCast(ptype), buf + i * chunk_sz, chunk_sz, &outb, hdr_sz);
    }

    const left = buf_sz - n_chunks * chunk_sz;
    pack_u16(@intCast(left), @ptrCast(&outb[5])); // [5..6] : length
    if (left > 0)
        a12int_append_out(S, @intCast(ptype), buf + n_chunks * chunk_sz, left, &outb, hdr_sz);
}

// Exported encode functions

export fn a12int_encode_araw(
    S: *a12_state,
    chid: u8,
    buf: [*]shmif_asample,
    n_samples: u16,
    cfg: a12_aframe_cfg,
    opts: a12_aframe_opts,
    chunk_sz: usize,
) callconv(.c) void {
    _ = opts;

    // repack the audio into a temporary buffer for format reasons
    const hdr_sz = a12int_header_size(STATE_AUDIO_PACKET);
    const buf_sz = hdr_sz + @as(usize, n_samples) * @sizeOf(u16) * @as(usize, cfg.channels);
    const outb: ?[*]u8 = @ptrCast(c.malloc(hdr_sz + buf_sz));
    if (outb == null) {
        trace(S, A12_TRACE_ALLOC, "failed to alloc {d} for s16aud", .{buf_sz});
        return;
    }
    const out = outb.?;

    // audio control message header
    out[16] = chid;
    out[17] = COMMAND_AUDIOFRAME;
    pack_u32(0, out + 18); // stream-id
    out[22] = cfg.channels; // channels
    out[23] = 0; // encoding, u16
    pack_u16(n_samples, out + 24);

    // repack into the right format
    var pos: usize = hdr_sz;
    for (0..@as(usize, n_samples)) |i| {
        pack_s16(buf[i], out + pos);
        pos += 2;
    }

    // send control packet then split audio data into chunks
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), out, CONTROL_PACKET_SIZE, null, 0);
    chunk_pack(S, STATE_AUDIO_PACKET, chid, out + hdr_sz, pos - hdr_sz, chunk_sz);
    c.free(@ptrCast(out));
}

export fn a12int_encode_rgb565(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    const px_sz: usize = 2;
    const vb_ptr: *anyopaque = @ptrCast(vb);

    // calculate chunk sizes
    const hdr_sz = a12int_header_size(STATE_VIDEO_PACKET);
    const ppb = (chunk_sz - hdr_sz) / px_sz;
    const bpb = ppb * px_sz;
    const blocks = w * h / ppb;

    const inbuf = vb_buffer(vb_ptr) orelse return;
    const pitch = vb_pitch(vb_ptr);
    var pos: usize = y * pitch + x;

    // allocate packing buffer
    const outb_opt: ?[*]u8 = @ptrCast(c.malloc(hdr_sz + bpb));
    if (outb_opt == null) {
        trace(S, A12_TRACE_ALLOC, "failed to alloc {d} for rgb565", .{hdr_sz + bpb});
        return;
    }
    const outb = outb_opt.?;

    // control frame header
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        POSTPROCESS_VIDEO_RGB565,
        sid,
        vb_ww,
        vb_hh,
        @intCast(w),
        @intCast(h),
        @intCast(x),
        @intCast(y),
        @intCast(w * h * px_sz),
        @intCast(w * h * px_sz),
        true,
        origo,
    );
    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);

    outb[0] = @intCast(chid); // [0] : channel id
    pack_u32(0xbacabaca, outb + 1); // [1..4] : stream
    pack_u16(@intCast(bpb), outb + 5); // [5..6] : length

    // sweep the incoming frame, pack maximum block size
    var row_len: usize = w;
    for (0..blocks) |_| {
        var j: usize = 0;
        while (j < bpb) : (j += px_sz) {
            var r: u8 = undefined;
            var g: u8 = undefined;
            var b: u8 = undefined;
            var ign: u8 = undefined;
            shmif_rgba_decomp(inbuf[pos], &r, &g, &b, &ign);
            pos += 1;
            const px: u16 =
                (@as(u16, b >> 3) & 0x1f) << 0 |
                (@as(u16, g >> 2) & 0x3f) << 5 |
                (@as(u16, r >> 3) & 0x1f) << 11;
            pack_u16(px, outb + hdr_sz + j);
            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }
        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, hdr_sz + bpb, null, 0);
    }

    // last chunk
    const left = ((w * h) - (blocks * ppb)) * px_sz;
    if (left > 0) {
        pack_u16(@intCast(left), outb + 5);
        trace(S, A12_TRACE_VDETAIL, "small block of {d} bytes", .{left});
        var i: usize = 0;
        while (i < left) : (i += px_sz) {
            var r: u8 = undefined;
            var g: u8 = undefined;
            var b: u8 = undefined;
            var ign: u8 = undefined;
            shmif_rgba_decomp(inbuf[pos], &r, &g, &b, &ign);
            pos += 1;
            const px: u16 =
                (@as(u16, b >> 3) & 0x1f) << 0 |
                (@as(u16, g >> 2) & 0x3f) << 5 |
                (@as(u16, r >> 3) & 0x1f) << 11;
            pack_u16(px, outb + hdr_sz + i);
            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }
        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, left + hdr_sz, null, 0);
    }

    c.free(@ptrCast(outb));
}

export fn a12int_encode_passthrough(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    const vb_ptr: *anyopaque = @ptrCast(vb);
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const bsz = vb_buffer_sz(vb_ptr);
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);

    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        POSTPROCESS_VIDEO_H264,
        sid,
        vb_ww,
        vb_hh,
        @intCast(w),
        @intCast(h),
        @intCast(x),
        @intCast(y),
        @intCast(bsz),
        @intCast(@as(usize, vb_ww) * @as(usize, vb_hh) * @sizeOf(shmif_pixel)),
        true,
        origo,
    );
    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);

    chunk_pack(S, STATE_VIDEO_PACKET, @intCast(chid), vb_buffer_bytes(vb_ptr).?, bsz, chunk_sz);
}

export fn a12int_encode_rgba(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    const px_sz: usize = 4;
    const vb_ptr: *anyopaque = @ptrCast(vb);
    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=rgba", .{});

    const hdr_sz = a12int_header_size(STATE_VIDEO_PACKET);
    const ppb = (chunk_sz - hdr_sz) / px_sz;
    const bpb = ppb * px_sz;
    const blocks = w * h / ppb;

    const inbuf = vb_buffer(vb_ptr) orelse return;
    const pitch = vb_pitch(vb_ptr);
    var pos: usize = y * pitch + x;

    const outb_opt: ?[*]u8 = @ptrCast(c.malloc(hdr_sz + bpb));
    if (outb_opt == null) return;
    const outb = outb_opt.?;

    // control frame
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        POSTPROCESS_VIDEO_RGBA,
        sid,
        vb_ww,
        vb_hh,
        @intCast(w),
        @intCast(h),
        @intCast(x),
        @intCast(y),
        @intCast(w * h * px_sz),
        @intCast(w * h * px_sz),
        true,
        origo,
    );
    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);

    outb[0] = @intCast(chid);
    pack_u32(0xbacabaca, outb + 1);
    pack_u16(@intCast(bpb), outb + 5);

    var row_len: usize = w;
    for (0..blocks) |_| {
        var j: usize = 0;
        while (j < bpb) : (j += px_sz) {
            const dst = outb + hdr_sz + j;
            shmif_rgba_decomp(inbuf[pos], &dst[0], &dst[1], &dst[2], &dst[3]);
            pos += 1;
            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }
        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, hdr_sz + bpb, null, 0);
    }

    // last chunk
    const left = ((w * h) - (blocks * ppb)) * px_sz;
    if (left > 0) {
        pack_u16(@intCast(left), outb + 5);
        trace(S, A12_TRACE_VDETAIL, "kind=status:message=padblock:size={d}", .{left});
        var i: usize = 0;
        while (i < left) : (i += px_sz) {
            const dst = outb + hdr_sz + i;
            shmif_rgba_decomp(inbuf[pos], &dst[0], &dst[1], &dst[2], &dst[3]);
            pos += 1;
            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }
        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, hdr_sz + left, null, 0);
    }

    c.free(@ptrCast(outb));
}

export fn a12int_encode_rgb(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    const px_sz: usize = 3;
    const vb_ptr: *anyopaque = @ptrCast(vb);
    trace(S, A12_TRACE_VDETAIL, "kind=status:ch={d}:codec=rgb", .{@as(u8, @intCast(chid))});

    const hdr_sz = a12int_header_size(STATE_VIDEO_PACKET);
    const ppb = (chunk_sz - hdr_sz) / px_sz;
    const bpb = ppb * px_sz;
    const blocks = w * h / ppb;

    const inbuf = vb_buffer(vb_ptr) orelse return;
    const pitch = vb_pitch(vb_ptr);
    var pos: usize = y * pitch + x;

    const outb_opt: ?[*]u8 = @ptrCast(c.malloc(hdr_sz + bpb));
    if (outb_opt == null) return;
    const outb = outb_opt.?;

    // control frame
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        POSTPROCESS_VIDEO_RGB,
        sid,
        vb_ww,
        vb_hh,
        @intCast(w),
        @intCast(h),
        @intCast(x),
        @intCast(y),
        @intCast(w * h * px_sz),
        @intCast(w * h * px_sz),
        true,
        origo,
    );
    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);

    outb[0] = @intCast(chid);
    pack_u32(0xbacabaca, outb + 1);
    pack_u16(@intCast(bpb), outb + 5);

    var row_len: usize = w;
    for (0..blocks) |_| {
        var j: usize = 0;
        while (j < bpb) : (j += px_sz) {
            var ign: u8 = undefined;
            const dst = outb + hdr_sz + j;
            shmif_rgba_decomp(inbuf[pos], &dst[0], &dst[1], &dst[2], &ign);
            pos += 1;
            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }
        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, hdr_sz + bpb, null, 0);
    }

    // last chunk
    const bytes_left = ((w * h) - (blocks * ppb)) * px_sz;
    if (bytes_left > 0) {
        var ofs: usize = 0;
        pack_u16(@intCast(bytes_left), outb + 5);

        while (bytes_left - ofs > 0) {
            var ign: u8 = undefined;
            const dst = outb + hdr_sz + ofs;
            shmif_rgba_decomp(inbuf[pos], &dst[0], &dst[1], &dst[2], &ign);
            pos += 1;
            ofs += px_sz;

            row_len -= 1;
            if (row_len == 0) {
                pos += pitch - w;
                row_len = w;
            }
        }

        a12int_append_out(S, @intCast(STATE_VIDEO_PACKET), outb, hdr_sz + bytes_left, null, 0);
    }

    c.free(@ptrCast(outb));
}

fn setup_zstd(S: *a12_state, ch: u8) bool {
    const ch_ptr = state_channel_ptr(S, ch);
    if (channel_zstd(ch_ptr) == null) {
        const ctx = ZSTD_createCCtx() orelse return false;
        channel_set_zstd(ch_ptr, ctx);
        _ = ZSTD_CCtx_setParameter(ctx, ZSTD_c_nbWorkers, 0);
    }
    return true;
}

const CompressRes = struct {
    ok: bool = false,
    @"type": u8 = 0,
    in_sz: usize = 0,
    out_sz: usize = 0,
    out_buf: ?[*]u8 = null,
};

fn compress_tzstd(
    S: *a12_state,
    ch: u8,
    vb: *shmifsrv_vbuffer,
    sid: u32,
    w: c_int,
    h: c_int,
    chunk_sz: usize,
) void {
    if (!setup_zstd(S, ch)) return;

    const vb_ptr: *anyopaque = @ptrCast(vb);
    const vtype = POSTPROCESS_VIDEO_TZSTD;

    // full header-size: 4 + 2 + 2 + 1 + 2 + 4 + 1 = 16 bytes
    // first 4 bytes is length
    const bb = vb_buffer_bytes(vb_ptr) orelse return;
    var compress_in_sz: u32 = undefined;
    unpack_u32(&compress_in_sz, bb);

    // second 2 bytes is number of lines
    var n_lines: u16 = undefined;
    unpack_u16(&n_lines, bb + 4);

    // third 2 bytes is number of cells
    var n_cells: u16 = undefined;
    unpack_u16(&n_cells, bb + 6);

    // cursor state — extended header?
    const extcursor: bool = (bb[15] & 8) == 8;

    const hdr_ver_sz: usize = @as(usize, n_lines) * raster_line_sz +
        @as(usize, n_cells) * raster_cell_sz + raster_hdr_sz +
        @as(usize, if (extcursor) 3 else 0);

    if (@as(usize, compress_in_sz) != hdr_ver_sz) {
        trace(S, A12_TRACE_SYSTEM, "kind=error:message=corrupt TPACK buffer", .{});
        return;
    }

    var out_sz = ZSTD_compressBound(@as(usize, compress_in_sz));
    const buf_opt: ?[*]u8 = @ptrCast(c.malloc(out_sz));
    if (buf_opt == null) {
        trace(S, A12_TRACE_ALLOC, "failed to build compressed TPACK output", .{});
        return;
    }
    const buf = buf_opt.?;

    const ch_ptr = state_channel_ptr(S, ch);
    out_sz = ZSTD_compressCCtx(
        channel_zstd(ch_ptr).?,
        buf,
        out_sz,
        bb,
        @as(usize, compress_in_sz),
        ZSTD_VIDEO_LEVEL,
    );

    if (ZSTD_isError(out_sz) != 0) {
        trace(S, A12_TRACE_ALLOC, "kind=zstd_fail", .{});
        c.free(@ptrCast(buf));
        return;
    }

    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=dzstd:b_in={d}:b_out={d}", .{
        @as(usize, compress_in_sz),
        out_sz,
    });

    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        ch,
        vtype,
        sid,
        vb_ww,
        vb_hh,
        @intCast(w),
        @intCast(h),
        0,
        0,
        @intCast(out_sz),
        compress_in_sz,
        true,
        origo,
    );

    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=tpack:b_in={d}:b_out={d}", .{
        @as(usize, compress_in_sz),
        out_sz,
    });

    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);

    chunk_pack(S, STATE_VIDEO_PACKET, ch, buf, out_sz, chunk_sz);
    c.free(@ptrCast(buf));
}

export fn a12int_encode_ztz(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    _ = x;
    _ = y;
    compress_tzstd(S, @intCast(chid), vb, sid, @intCast(w), @intCast(h), chunk_sz);
}

fn compress_deltaz(
    S: *a12_state,
    ch: u8,
    vb: *shmifsrv_vbuffer,
    px: *usize,
    py: *usize,
    pw: *usize,
    ph: *usize,
    zstd_mode: bool,
) CompressRes {
    _ = zstd_mode;

    const vb_ptr: *anyopaque = @ptrCast(vb);
    var result_type: u8 = undefined;
    var compress_in: [*]u8 = undefined;
    var compress_in_sz: usize = 0;
    const ch_ptr = state_channel_ptr(S, ch);
    const ab = channel_acc_ptr(ch_ptr);

    const vb_wval = vb_w(vb_ptr);
    const vb_hval = vb_h(vb_ptr);

    // reset the accumulation buffer if size changed
    if (vb_w(ab) != vb_wval or vb_h(ab) != vb_hval) {
        trace(S, A12_TRACE_VIDEO,
            "kind=resize:ch={d}:prev_w={d}:prev_h={d}:new_w={d}:new_h={d}",
            .{ ch, vb_w(ab), vb_h(ab), vb_wval, vb_hval });
        if (vb_buffer(ab)) |old_buf| {
            c.free(@ptrCast(old_buf));
        }
        vb_set_buffer(ab, null);
        if (channel_compression(ch_ptr)) |comp| {
            c.free(@ptrCast(comp));
        }
        channel_set_compression(ch_ptr, null);
    }

    if (!setup_zstd(S, ch)) return CompressRes{};

    // first frame or after reset — I-frame mode
    if (vb_buffer(ab) == null) {
        result_type = @intCast(POSTPROCESS_VIDEO_ZSTD);
        copy_vbuffer(ab, @ptrCast(vb));
        const nb = vb_wval * vb_hval * 3;
        const new_buf_opt: ?[*]shmif_pixel = @ptrCast(@alignCast(c.malloc(nb)));
        pw.* = vb_wval;
        ph.* = vb_hval;
        px.* = 0;
        py.* = 0;
        trace(S, A12_TRACE_VIDEO, "kind=status:ch={d}:compress=dpng:message=I", .{ch});

        if (new_buf_opt == null) return CompressRes{};
        vb_set_buffer(ab, new_buf_opt);

        // allocate compression buffer for delta XOR storage
        const comp_opt: ?[*]u8 = @ptrCast(c.malloc(nb));
        compress_in_sz = nb;

        if (comp_opt == null) {
            c.free(@ptrCast(new_buf_opt));
            vb_set_buffer(ab, null);
            return CompressRes{};
        }
        channel_set_compression(ch_ptr, comp_opt);

        // pack RGB from input into accumulation buffer
        compress_in = @as([*]u8, @ptrCast(@alignCast(new_buf_opt.?)));
        const acc = compress_in;
        var ofs: usize = 0;
        const src_buf = vb_buffer(vb_ptr) orelse return CompressRes{};
        const src_pitch = vb_pitch(vb_ptr);
        for (0..vb_hval) |row_y| {
            for (0..vb_wval) |row_x| {
                var ign: u8 = undefined;
                const pixel = src_buf[row_y * src_pitch + row_x];
                shmif_rgba_decomp(pixel, &acc[ofs], &acc[ofs + 1], &acc[ofs + 2], &ign);
                ofs += 3;
            }
        }
    } else {
        // delta frame: compute XOR with accumulation buffer
        trace(S, A12_TRACE_VDETAIL, "kind=status:ch={d}:dw={d}:dh={d}:x={d}:y={d}", .{
            ch, pw.*, ph.*, px.*, py.*,
        });
        compress_in = channel_compression(ch_ptr) orelse return CompressRes{};
        const acc = @as([*]u8, @ptrCast(@alignCast(vb_buffer(ab).?)));
        const ab_w = vb_w(ab);
        const src_buf = vb_buffer(vb_ptr) orelse return CompressRes{};
        const src_pitch = vb_pitch(vb_ptr);

        var cy = py.*;
        while (cy < py.* + ph.*) : (cy += 1) {
            var rs: usize = (cy * ab_w + px.*) * 3;
            var cx = px.*;
            while (cx < px.* + pw.*) : (cx += 1) {
                var r: u8 = undefined;
                var g: u8 = undefined;
                var b: u8 = undefined;
                var ign: u8 = undefined;
                const pixel = src_buf[cy * src_pitch + cx];
                shmif_rgba_decomp(pixel, &r, &g, &b, &ign);
                compress_in[compress_in_sz] = acc[rs + 0] ^ r;
                compress_in_sz += 1;
                compress_in[compress_in_sz] = acc[rs + 1] ^ g;
                compress_in_sz += 1;
                compress_in[compress_in_sz] = acc[rs + 2] ^ b;
                compress_in_sz += 1;
                acc[rs + 0] = r;
                acc[rs + 1] = g;
                acc[rs + 2] = b;
                rs += 3;
            }
        }
        result_type = @intCast(POSTPROCESS_VIDEO_DZSTD);
    }

    var out_sz = ZSTD_compressBound(compress_in_sz);
    const buf_opt: ?[*]u8 = @ptrCast(c.malloc(out_sz));
    if (buf_opt == null) return CompressRes{};
    const buf = buf_opt.?;

    out_sz = ZSTD_compressCCtx(
        channel_zstd(ch_ptr).?,
        buf,
        out_sz,
        compress_in,
        compress_in_sz,
        1,
    );

    if (ZSTD_isError(out_sz) != 0) {
        trace(S, A12_TRACE_ALLOC, "kind=zstd_fail", .{});
        c.free(@ptrCast(buf));
        return CompressRes{};
    }

    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=dzstd:b_in={d}:b_out={d}", .{
        compress_in_sz,
        out_sz,
    });

    return CompressRes{
        .@"type" = result_type,
        .ok = true,
        .out_buf = buf,
        .out_sz = out_sz,
        .in_sz = compress_in_sz,
    };
}

export fn a12int_encode_dzstd(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    var mx = x;
    var my = y;
    var mw = w;
    var mh = h;
    const cres = compress_deltaz(S, @intCast(chid), vb, &mx, &my, &mw, &mh, true);
    if (!cres.ok) return;

    const vb_ptr: *anyopaque = @ptrCast(vb);
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        @intCast(cres.@"type"),
        sid,
        vb_ww,
        vb_hh,
        @intCast(mw),
        @intCast(mh),
        @intCast(mx),
        @intCast(my),
        @intCast(cres.out_sz),
        @intCast(cres.in_sz),
        true,
        origo,
    );

    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=dzstd:b_in={d}:b_out={d}", .{
        mw * mh * 3,
        cres.out_sz,
    });

    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);
    chunk_pack(S, STATE_VIDEO_PACKET, @intCast(chid), cres.out_buf.?, cres.out_sz, chunk_sz);

    c.free(@ptrCast(cres.out_buf.?));
}

export fn a12int_encode_dpng(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    _ = opts;
    var mx = x;
    var my = y;
    var mw = w;
    var mh = h;
    const cres = compress_deltaz(S, @intCast(chid), vb, &mx, &my, &mw, &mh, false);
    if (!cres.ok) return;

    const vb_ptr: *anyopaque = @ptrCast(vb);
    const vb_ww: u16 = @intCast(vb_w(vb_ptr));
    const vb_hh: u16 = @intCast(vb_h(vb_ptr));
    const origo = if (vb_flags_origo_ll(vb_ptr)) @as(u8, 1) else @as(u8, 0);
    var hdr_buf: [CONTROL_PACKET_SIZE]u8 = undefined;
    a12int_vframehdr_build(
        S,
        &hdr_buf,
        state_last_seen_seqnr(S),
        @intCast(chid),
        @intCast(cres.@"type"),
        sid,
        vb_ww,
        vb_hh,
        @intCast(mw),
        @intCast(mh),
        @intCast(mx),
        @intCast(my),
        @intCast(cres.out_sz),
        @intCast(cres.in_sz),
        true,
        origo,
    );

    trace(S, A12_TRACE_VDETAIL, "kind=status:codec=dpng:b_in={d}:b_out={d}", .{
        mw * mh * 3,
        cres.out_sz,
    });

    a12int_step_vstream(S, sid);
    a12int_append_out(S, @intCast(STATE_CONTROL_PACKET), &hdr_buf, CONTROL_PACKET_SIZE, null, 0);
    chunk_pack(S, STATE_VIDEO_PACKET, @intCast(chid), cres.out_buf.?, cres.out_sz, chunk_sz);

    c.free(@ptrCast(cres.out_buf.?));
}

export fn a12int_encode_drop(
    S: *a12_state,
    chid: c_int,
    failed: bool,
) callconv(.c) void {
    _ = failed;
    const ch_ptr = state_channel_ptr(S, @intCast(chid));
    if (channel_zstd(ch_ptr)) |ctx| {
        _ = ZSTD_freeCCtx(ctx);
        trace(S, A12_TRACE_VIDEO, "dropping zstd context", .{});
        channel_set_zstd(ch_ptr, null);
    }

    // H264 encoder cleanup is only relevant with WANT_H264_ENC/WANT_H264_DEC
    // which requires FFmpeg. Not ported (would need FFmpeg Zig bindings).
    // The C code conditionally compiles this block with #ifdef.
}

/// a12int_encode_tz — declared in header but never defined in original C code.
/// Stub implementation forwards to ztz.
export fn a12int_encode_tz(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    a12int_encode_ztz(S, vb, opts, sid, x, y, w, h, chunk_sz, chid);
}

/// H264 encoding — without WANT_H264_ENC, falls back to dpng.
/// The full FFmpeg encoder path is not ported (requires libavcodec/libswscale).
export fn a12int_encode_h264(
    S: *a12_state,
    vb: *shmifsrv_vbuffer,
    opts: a12_vframe_opts,
    sid: u32,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
    chunk_sz: usize,
    chid: c_int,
) callconv(.c) void {
    // Without WANT_H264_ENC, always fall back to dpng
    a12int_encode_dpng(S, vb, opts, sid, x, y, w, h, chunk_sz, chid);
    trace(S, A12_TRACE_VIDEO, "switching to fallback (PNG) on videnc fail", .{});
}
