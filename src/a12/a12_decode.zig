// Zig port of a12_decode.c — A12 protocol state machine, substream decoding routines
// Copyright: 2017-2018, Bjorn Stahl
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
    pub const CHANNEL_RAW = a12.CHANNEL_RAW;
    pub const free = libc.free;
    pub const malloc = libc.malloc;
    pub const POSTPROCESS_VIDEO_DZSTD = a12.POSTPROCESS_VIDEO_DZSTD;
    pub const POSTPROCESS_VIDEO_H264 = a12.POSTPROCESS_VIDEO_H264;
    pub const POSTPROCESS_VIDEO_RGB = a12.POSTPROCESS_VIDEO_RGB;
    pub const POSTPROCESS_VIDEO_RGB565 = a12.POSTPROCESS_VIDEO_RGB565;
    pub const POSTPROCESS_VIDEO_RGBA = a12.POSTPROCESS_VIDEO_RGBA;
    pub const POSTPROCESS_VIDEO_TZSTD = a12.POSTPROCESS_VIDEO_TZSTD;
    pub const POSTPROCESS_VIDEO_ZSTD = a12.POSTPROCESS_VIDEO_ZSTD;
    pub const shmif_pixel = shmif.shmif_pixel;
    pub const SHMIF_SIGVID = shmif.SHMIF_SIGVID;
    pub const STREAM_CANCEL_DECODE_ERROR = a12.STREAM_CANCEL_DECODE_ERROR;
    pub const struct_a12_channel = a12.struct_a12_channel;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_video_frame = a12.struct_video_frame;
    pub const write = libc.write;
    pub const open = libc.open;
    pub const close = libc.close;
    pub const O_WRONLY = libc.O_WRONLY;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_TRUNC = libc.O_TRUNC;
};

// ZSTD extern declarations

const ZSTD_DCtx = opaque {};

extern "c" fn ZSTD_getFrameContentSize(src: *const anyopaque, src_size: usize) c_ulonglong;
extern "c" fn ZSTD_createDCtx() ?*ZSTD_DCtx;
extern "c" fn ZSTD_freeDCtx(dctx: *ZSTD_DCtx) usize;
extern "c" fn ZSTD_decompressDCtx(
    dctx: *ZSTD_DCtx,
    dst: *anyopaque,
    dst_capacity: usize,
    src: *const anyopaque,
    src_size: usize,
) usize;

// Offset-based accessors for opaque structs (a12_state, a12_channel)
// struct a12_state and a12_channel are opaque in Zig's @cImport because
// shmifsrv_vbuffer contains bitfields. Access via byte offsets instead.
const ofs = @import("a12_offsets");
const A12State = ofs.A12State;
const A12Channel = ofs.A12Channel;
const A12VideoFrame = ofs.VideoFrame;

const SignalVideoFn = *const fn (usize, usize, usize, usize, ?*anyopaque) callconv(.c) void;

fn a12dec_get_in_channel(S: *c.struct_a12_state) c_int {
    return A12State.getInChannel(@ptrCast(S));
}
fn a12dec_get_decode_buf(S: *c.struct_a12_state) [*]u8 {
    return A12State.getDecodeBuf(@ptrCast(S));
}
fn a12dec_get_decode_pos(S: *c.struct_a12_state) u16 {
    return A12State.getDecodePos(@ptrCast(S));
}
fn a12dec_get_channel(S: *c.struct_a12_state, chid: c_int) *anyopaque {
    return A12State.getChannelPtr(@ptrCast(S), @intCast(chid));
}
fn a12dec_ch_get_active(ch: *anyopaque) c_int {
    return A12Channel.getActive(ch);
}
fn a12dec_ch_get_cont(ch: *anyopaque) ?*c.struct_arcan_shmif_cont {
    return @ptrCast(@alignCast(A12Channel.getCont(ch)));
}
fn a12dec_ch_get_vframe(ch: *anyopaque) *anyopaque {
    return A12Channel.getVframe(ch);
}
fn a12dec_ch_get_raw_tag(ch: *anyopaque) ?*anyopaque {
    return A12Channel.getRawTag(ch);
}
fn a12dec_ch_get_raw_signal_video(ch: *anyopaque) ?SignalVideoFn {
    const ptr = A12Channel.getRawSignalVideo(ch) orelse return null;
    return @ptrCast(@alignCast(ptr));
}
fn a12dec_ch_vframe_get_zstd(ch: *anyopaque) ?*ZSTD_DCtx {
    return @ptrCast(@alignCast(A12VideoFrame.getZstd(A12Channel.getVframe(ch))));
}
fn a12dec_ch_vframe_set_zstd(ch: *anyopaque, ctx: ?*ZSTD_DCtx) void {
    A12VideoFrame.setZstd(A12Channel.getVframe(ch), @ptrCast(@alignCast(ctx)));
}
fn a12dec_ch_set_zstd_null(ch: *anyopaque) void {
    A12Channel.setZstd(ch, null);
}

// Other extern C functions used by this module

extern "c" fn arcan_timemillis() c_ulonglong;
extern "c" fn arcan_shmif_signal(cont: ?*c.struct_arcan_shmif_cont, mask: c_int) c_uint;
extern "c" fn a12_vstream_cancel(S: *c.struct_a12_state, chid: u8, reason: c_int) void;
extern "c" fn a12int_stream_ack(S: *c.struct_a12_state, ch: u8, id: u32) void;

// Trace support
// a12int_trace is a varargs fprintf macro in C that also accesses S->tracetag,
// which is inaccessible on the opaque struct. Trace calls are commented out;
// the C callers of these exported functions already perform their own tracing.

// Constants
// Re-declare as typed constants to avoid c_uint/c_int coercion issues with
// cImport enum values.

const POSTPROCESS_VIDEO_RGBA: u8 = c.POSTPROCESS_VIDEO_RGBA;
const POSTPROCESS_VIDEO_RGB: u8 = c.POSTPROCESS_VIDEO_RGB;
const POSTPROCESS_VIDEO_RGB565: u8 = c.POSTPROCESS_VIDEO_RGB565;
const POSTPROCESS_VIDEO_H264: c_int = c.POSTPROCESS_VIDEO_H264;
const POSTPROCESS_VIDEO_TZSTD: u8 = c.POSTPROCESS_VIDEO_TZSTD;
const POSTPROCESS_VIDEO_DZSTD: u8 = c.POSTPROCESS_VIDEO_DZSTD;
const POSTPROCESS_VIDEO_ZSTD: u8 = c.POSTPROCESS_VIDEO_ZSTD;

const CHANNEL_RAW: c_int = c.CHANNEL_RAW;
const SHMIF_SIGVID: c_int = @intCast(c.SHMIF_SIGVID);

const STREAM_CANCEL_DECODE_ERROR: c_int = c.STREAM_CANCEL_DECODE_ERROR;

// SHMIF_RGBA / SHMIF_RGBA_DECOMP (inline from arcan_shmif_defs.h)

const shmif_pixel = c.shmif_pixel;

inline fn SHMIF_RGBA(r: u8, g: u8, b: u8, a: u8) shmif_pixel {
    return (@as(u32, a) << 24) |
        (@as(u32, r) << 16) |
        (@as(u32, g) << 8) |
        @as(u32, b);
}

const RgbaComponents = struct { r: u8, g: u8, b: u8, a: u8 };

inline fn SHMIF_RGBA_DECOMP(val: shmif_pixel) RgbaComponents {
    return .{
        .b = @truncate(val & 0x000000ff),
        .g = @truncate((val & 0x0000ff00) >> 8),
        .r = @truncate((val & 0x00ff0000) >> 16),
        .a = @truncate((val & 0xff000000) >> 24),
    };
}

// unpack_u16 (from pack.h)

inline fn unpack_u16(inbuf: [*]const u8) u16 {
    return @as(u16, inbuf[0]) | (@as(u16, inbuf[1]) << 8);
}

// drain_video (static)

fn drain_video(
    _: *c.struct_a12_state,
    ch: *c.struct_a12_channel,
    cvf: *c.struct_video_frame,
) void {
    {
        const smon = @import("shmif_monitor");
        const snprintf_ex = @extern(*const fn ([*c]u8, usize, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "snprintf" });
        var buf: [96]u8 = undefined;
        const dc_opt = a12dec_ch_get_cont(ch);
        var cont_w: c_int = -1;
        var cont_h: c_int = -1;
        if (dc_opt) |dc| {
            cont_w = @intCast(dc.w);
            cont_h = @intCast(dc.h);
        }
        _ = snprintf_ex(&buf, 96, "a12:drain_video:cvf=%dx%d:cont=%dx%d:active=%d",
            @as(c_int, cvf.w), @as(c_int, cvf.h),
            cont_w, cont_h,
            @as(c_int, a12dec_ch_get_active(ch)));
        smon.emitLuaTag(@ptrCast(&buf));
    }
    cvf.commit = 0;

    if (a12dec_ch_get_active(ch) == CHANNEL_RAW) {
        if (a12dec_ch_get_raw_signal_video(ch)) |signal_fn| {
            signal_fn(
                @as(usize, cvf.x),
                @as(usize, cvf.y),
                @as(usize, cvf.x) + @as(usize, cvf.w),
                @as(usize, cvf.y) + @as(usize, cvf.h),
                a12dec_ch_get_raw_tag(ch),
            );
        }
        return;
    }

    {
        const tmsg = "[bug133-vdec] raw: SIGVID raised\n";
        _ = c.write(2, tmsg.ptr, tmsg.len);
    }
    // Dump the listener-side rendered frame buffer to a PPM file so we have
    // a verifiable image of what's actually being delivered to durian_test
    // (which is headless on this host so the user can't see it directly).
    // Writes /tmp/arcan_bridge_frame.ppm — overwritten each frame, so the
    // file always has the latest frame.
    if (a12dec_ch_get_cont(ch)) |cont_dump| {
        const w: u32 = @intCast(cont_dump.w);
        const h: u32 = @intCast(cont_dump.h);
        if (w > 0 and h > 0 and w < 8192 and h < 8192 and cont_dump.unnamed_0.vidp != null) {
            const path = "/tmp/arcan_bridge_frame.ppm";
            const path_z: [*:0]const u8 = path;
            const fd_dump = c.open(path_z, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_int, 0o644));
            if (fd_dump >= 0) {
                var hdr_buf: [64]u8 = undefined;
                const hdr = std.fmt.bufPrint(&hdr_buf, "P6\n{d} {d}\n255\n", .{ w, h }) catch unreachable;
                _ = c.write(fd_dump, hdr.ptr, hdr.len);
                const vidp_pix: [*]const u32 = @ptrCast(@alignCast(cont_dump.unnamed_0.vidp));
                const total: usize = @as(usize, w) * @as(usize, h);
                var rgbbuf: [4096 * 3]u8 = undefined;
                var i: usize = 0;
                while (i < total) {
                    var cap = total - i;
                    if (cap > 4096) cap = 4096;
                    var j: usize = 0;
                    while (j < cap) : (j += 1) {
                        const px: u32 = vidp_pix[i + j];
                        // shmif pixel format ARGB (alpha hi byte).
                        rgbbuf[j * 3 + 0] = @truncate((px >> 16) & 0xff);
                        rgbbuf[j * 3 + 1] = @truncate((px >> 8) & 0xff);
                        rgbbuf[j * 3 + 2] = @truncate(px & 0xff);
                    }
                    _ = c.write(fd_dump, &rgbbuf, cap * 3);
                    i += cap;
                }
                _ = c.close(fd_dump);
            }
        }
    }
    _ = arcan_shmif_signal(a12dec_ch_get_cont(ch), SHMIF_SIGVID);
}

// a12int_buffer_format (exported)

export fn a12int_buffer_format(method: c_int) callconv(.c) bool {
    return method == POSTPROCESS_VIDEO_H264 or
        method == @as(c_int, POSTPROCESS_VIDEO_TZSTD) or
        method == @as(c_int, POSTPROCESS_VIDEO_ZSTD) or
        method == @as(c_int, POSTPROCESS_VIDEO_DZSTD);
}

// video_miniz (internal — zstd decompression output handler)
// Called from a12int_decode_vbuffer after decompressing a ZSTD frame.
// Unpacks RGB/tpack pixel data into the shmif video buffer, handling
// per-pixel row wrapping and carry state for partial pixel spans.

fn video_miniz(
    S: *c.struct_a12_state,
    inbuf_initial: [*]const u8,
    initial_len: usize,
) c_int {
    const in_ch = a12dec_get_in_channel(S);
    const ch = a12dec_get_channel(S, in_ch);
    const cvf: *c.struct_video_frame = @ptrCast(@alignCast(a12dec_ch_get_vframe(ch)));
    const cont = a12dec_ch_get_cont(ch) orelse return 0;

    var len = initial_len;

    if (len > cvf.expanded_sz) {
        return 0;
    }

    var inbuf = inbuf_initial;

    const vidp: [*]shmif_pixel = @ptrCast(@alignCast(cont.unnamed_0.vidp));

    // Handle carry (1..3 byte spill from a previous call — need 1px buffer)
    if (cvf.carry != 0) {
        while (cvf.carry < 3) {
            cvf.pxbuf[cvf.carry] = inbuf[0];
            cvf.carry += 1;
            inbuf = inbuf + 1;
            len -= 1;

            if (len == 0)
                return 1;
        }

        // Commit the spilled pixel
        if (cvf.postprocess == POSTPROCESS_VIDEO_DZSTD) {
            const prev = SHMIF_RGBA_DECOMP(vidp[cvf.out_pos]);
            vidp[cvf.out_pos] = SHMIF_RGBA(
                cvf.pxbuf[0] ^ prev.r,
                cvf.pxbuf[1] ^ prev.g,
                cvf.pxbuf[2] ^ prev.b,
                0xff,
            );
        } else {
            vidp[cvf.out_pos] = SHMIF_RGBA(cvf.pxbuf[0], cvf.pxbuf[1], cvf.pxbuf[2], 0xff);
        }
        cvf.out_pos += 1;

        // Row boundary check
        cvf.row_left -= 1;
        if (cvf.row_left == 0) {
            cvf.out_pos -= @as(usize, cvf.w);
            cvf.out_pos += cont.pitch;
            cvf.row_left = @as(usize, cvf.w);
        }
        cvf.carry = 0;
    }

    // tpack: write into vidb directly
    if (cvf.postprocess == POSTPROCESS_VIDEO_TZSTD) {
        const vidb: [*]u8 = @ptrCast(cont.unnamed_0.vidb);
        @memcpy(vidb[cvf.out_pos..][0..len], inbuf[0..len]);
        cvf.out_pos += len;
        cvf.expanded_sz -= @as(u32, @intCast(len));
        return 1;
    }

    // Pixel-aligned fill/unpack (3 bytes per pixel)
    const npx = (len / 3) * 3;
    var i: usize = 0;
    while (i < npx) : (i += 3) {
        if (cvf.postprocess == POSTPROCESS_VIDEO_DZSTD) {
            const prev = SHMIF_RGBA_DECOMP(vidp[cvf.out_pos]);
            vidp[cvf.out_pos] = SHMIF_RGBA(
                inbuf[i + 0] ^ prev.r,
                inbuf[i + 1] ^ prev.g,
                inbuf[i + 2] ^ prev.b,
                0xff,
            );
        } else {
            vidp[cvf.out_pos] = SHMIF_RGBA(inbuf[i], inbuf[i + 1], inbuf[i + 2], 0xff);
        }
        cvf.out_pos += 1;

        cvf.row_left -= 1;
        if (cvf.row_left == 0) {
            cvf.out_pos -= @as(usize, cvf.w);
            cvf.out_pos += cont.pitch;
            cvf.row_left = @as(usize, cvf.w);
        }
    }

    // Account for trailing bytes that don't align to 3
    if (len - npx > 0) {
        cvf.carry = 0;
        var j: usize = 0;
        while (j < len - npx) : (j += 1) {
            cvf.pxbuf[cvf.carry] = inbuf[npx + j];
            cvf.carry += 1;
        }
    }

    cvf.expanded_sz -= @as(u32, @intCast(len));
    return 1;
}

// a12int_decode_drop (exported)

export fn a12int_decode_drop(
    S: *c.struct_a12_state,
    chid: c_int,
    failed: bool,
) callconv(.c) void {
    _ = failed;

    const ch = a12dec_get_channel(S, chid);
    if (a12dec_ch_vframe_get_zstd(ch)) |dctx| {
        _ = ZSTD_freeDCtx(dctx);
        // C code sets channel-level anonymous struct zstd (compression ctx) to NULL,
        // NOT the vframe's zstd — preserving original behavior faithfully.
        a12dec_ch_set_zstd_null(ch);
    }

    a12_h264_free(@intCast(chid));
}

// a12int_vframe_setup (exported)

// H264 sidecar — symbols resolve at link time to either h264_decode.zig
// (real libavcodec) or h264_decode_stub.zig (always returns false). The
// build picks one based on -Dwith_ffmpeg.
extern "c" fn a12_h264_setup(chid: u8) bool;
extern "c" fn a12_h264_decode(
    chid: u8,
    data: [*]const u8,
    data_sz: usize,
    out_bgra: [*]u8,
    out_pitch: c_int,
    out_w: c_int,
    out_h: c_int,
) c_int;
extern "c" fn a12_h264_free(chid: u8) void;

export fn a12int_vframe_setup(
    S: *c.struct_a12_state,
    ch: *c.struct_a12_channel,
    dst: *c.struct_video_frame,
    method: c_int,
) callconv(.c) bool {
    _ = ch;

    // Zero-initialize the destination frame (*dst = (struct video_frame){})
    dst.* = std.mem.zeroes(c.struct_video_frame);

    if (method == POSTPROCESS_VIDEO_H264) {
        const in_ch = a12dec_get_in_channel(S);
        return a12_h264_setup(@intCast(in_ch));
    }
    return true;
}

// a12int_decode_vbuffer (exported)

export fn a12int_decode_vbuffer(
    S: *c.struct_a12_state,
    ch: *c.struct_a12_channel,
    cvf: *c.struct_video_frame,
    cont: ?*c.struct_arcan_shmif_cont,
) callconv(.c) void {
    _ = cont;

    if (cvf.postprocess == POSTPROCESS_VIDEO_DZSTD or
        cvf.postprocess == POSTPROCESS_VIDEO_ZSTD or
        cvf.postprocess == POSTPROCESS_VIDEO_TZSTD)
    {
        const inbuf_ptr: [*]const u8 = @ptrCast(cvf.inbuf orelse {
            return;
        });

        const content_sz: c_ulonglong =
            ZSTD_getFrameContentSize(@ptrCast(inbuf_ptr), @as(usize, cvf.inbuf_pos));

        // Repeat and compare, don't le/gt.
        // content_sz may be ZSTD_CONTENTSIZE_UNKNOWN/ERROR (very large u64 values),
        // which naturally won't match expanded_sz (u32).
        if (content_sz == @as(c_ulonglong, cvf.expanded_sz)) {
            if (a12dec_ch_vframe_get_zstd(ch) == null) {
                if (ZSTD_createDCtx()) |ctx| {
                    a12dec_ch_vframe_set_zstd(ch, ctx);
                }
            }

            if (a12dec_ch_vframe_get_zstd(ch)) |dctx| {
                const csz: usize = @intCast(content_sz);
                const buffer: ?*anyopaque = std.c.malloc(csz);
                if (buffer) |buf| {
                    _ = ZSTD_decompressDCtx(
                        dctx,
                        buf,
                        csz,
                        @ptrCast(inbuf_ptr),
                        @as(usize, cvf.inbuf_pos),
                    );
                    const buf_ptr: [*]u8 = @ptrCast(buf);
                    _ = video_miniz(S, buf_ptr, csz);
                    std.c.free(buf);
                }
            }
        }

        std.c.free(@ptrCast(cvf.inbuf));
        cvf.inbuf = null;
        cvf.carry = 0;

        // Drain if commit is set and not 255 (cancel marker)
        if (cvf.commit != 0 and cvf.commit != 255) {
            drain_video(S, ch, cvf);
        }
        return;
    }

    if (cvf.postprocess == POSTPROCESS_VIDEO_H264) {
        const cont264_opt = a12dec_ch_get_cont(ch);
        const cont264 = cont264_opt orelse {
            if (cvf.inbuf) |p| std.c.free(@ptrCast(p));
            cvf.inbuf = null;
            return;
        };
        const inbuf_ptr: [*]const u8 = @ptrCast(cvf.inbuf orelse return);
        const chid: u8 = @intCast(a12dec_get_in_channel(S));

        const vidb: [*]u8 = @ptrCast(cont264.unnamed_0.vidb);
        const rv = a12_h264_decode(
            chid,
            inbuf_ptr,
            @intCast(cvf.inbuf_pos),
            vidb,
            @intCast(cont264.stride),
            @intCast(cont264.w),
            @intCast(cont264.h),
        );

        std.c.free(@ptrCast(cvf.inbuf));
        cvf.inbuf = null;

        if (rv == 1 and cvf.commit != 0 and cvf.commit != 255) {
            drain_video(S, ch, cvf);
        }
        return;
    }
}

// a12int_unpack_vbuffer (exported)

export fn a12int_unpack_vbuffer(
    S: *c.struct_a12_state,
    cvf: *c.struct_video_frame,
    cont: *c.struct_arcan_shmif_cont,
) callconv(.c) void {
    const decode_pos: usize = @as(usize, a12dec_get_decode_pos(S));
    const decode_buf = a12dec_get_decode_buf(S);
    const in_channel = a12dec_get_in_channel(S);

    // Access vidp through the anonymous union
    const vidp: [*]shmif_pixel = @ptrCast(@alignCast(cont.unnamed_0.vidp));

    if (cvf.postprocess == POSTPROCESS_VIDEO_RGBA) {
        var i: usize = 0;
        while (i < decode_pos) : (i += 4) {
            vidp[cvf.out_pos] = SHMIF_RGBA(
                decode_buf[i + 0],
                decode_buf[i + 1],
                decode_buf[i + 2],
                decode_buf[i + 3],
            );
            cvf.out_pos += 1;
            cvf.row_left -= 1;
            if (cvf.row_left == 0) {
                cvf.out_pos -= @as(usize, cvf.w);
                cvf.out_pos += cont.pitch;
                cvf.row_left = @as(usize, cvf.w);
            }
        }
    } else if (cvf.postprocess == POSTPROCESS_VIDEO_RGB) {
        var i: usize = 0;
        while (i < decode_pos) : (i += 3) {
            vidp[cvf.out_pos] = SHMIF_RGBA(
                decode_buf[i + 0],
                decode_buf[i + 1],
                decode_buf[i + 2],
                0xff,
            );
            cvf.out_pos += 1;
            cvf.row_left -= 1;
            if (cvf.row_left == 0) {
                cvf.out_pos -= @as(usize, cvf.w);
                cvf.out_pos += cont.pitch;
                cvf.row_left = @as(usize, cvf.w);
            }
        }
    } else if (cvf.postprocess == POSTPROCESS_VIDEO_RGB565) {
        const rgb565_lut5 = [32]u8{
            0,   8,  16, 25, 33, 41, 49, 58, 66,  74,  82,  90,  99, 107,
            115, 123, 132, 140, 148, 156, 165, 173, 181, 189, 197, 206, 214, 222,
            230, 239, 247, 255,
        };

        const rgb565_lut6 = [64]u8{
            0,   4,   8,  12,  16,  20,  24,  28,  32,  36,  40,  45,  49,  53,  57,
            61,  65,  69,  73,  77,  81,  85,  89,  93,  97, 101, 105, 109, 113, 117,
            121, 125, 130, 134, 138, 142, 146, 150, 154, 158, 162, 166, 170, 174,
            178, 182, 186, 190, 194, 198, 202, 206, 210, 215, 219, 223, 227, 231,
            235, 239, 243, 247, 251, 255,
        };

        var i: usize = 0;
        while (i < decode_pos) : (i += 2) {
            const px = unpack_u16(decode_buf + i);
            vidp[cvf.out_pos] = SHMIF_RGBA(
                rgb565_lut5[(px & 0xf800) >> 11],
                rgb565_lut6[(px & 0x07e0) >> 5],
                rgb565_lut5[(px & 0x001f)],
                0xff,
            );
            cvf.out_pos += 1;
            cvf.row_left -= 1;
            if (cvf.row_left == 0) {
                cvf.out_pos -= @as(usize, cvf.w);
                cvf.out_pos += cont.pitch;
                cvf.row_left = @as(usize, cvf.w);
            }
        }
    }

    cvf.inbuf_sz -= @as(u32, @intCast(decode_pos));
    if (cvf.inbuf_sz == 0) {
        a12int_stream_ack(S, @intCast(in_channel), cvf.id);
        if (cvf.commit != 0) {
            const tmsg = "[bug133-vdec] zstd: SIGVID raised\n";
            _ = c.write(2, tmsg.ptr, tmsg.len);
            _ = arcan_shmif_signal(cont, SHMIF_SIGVID);
        }
    }
}
