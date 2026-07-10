// Byte-offset accessors for engine-only opaque structs:
//   tui_font, agp_vstore, stream_meta, agp_buffer_plane
//
// Offsets computed by compute_offsets.c for Linux aarch64.

const std = @import("std");

// generic helpers (same as shmif_offsets.zig)

fn ptrAdd(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

fn readField(comptime T: type, base: *anyopaque, off: usize) T {
    const p: *align(1) const T = @ptrCast(ptrAdd(base, off));
    return p.*;
}

fn writeField(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    const p: *align(1) T = @ptrCast(ptrAdd(base, off));
    p.* = val;
}

// tui_font

pub const TuiFont = struct {
    pub const sizeof_font: usize = 24;
    const o_bitmap_or_truetype: usize = 0; // union at offset 0
    const o_vector: usize = 8;

    pub fn isVector(f: *anyopaque) bool {
        return readField(bool, f, o_vector);
    }
    pub fn getBitmap(f: *anyopaque) *anyopaque {
        return readField(*anyopaque, f, o_bitmap_or_truetype);
    }
    pub fn getTruetype(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_bitmap_or_truetype);
    }
};

// agp_vstore

pub const AgpVstore = struct {
    const o_vinf_text_glid: usize = 16; // unsigned glid (union vinf.text.glid)
    const o_vinf_text_raw: usize = 48;
    const o_vinf_text_s_raw: usize = 40;
    const o_vinf_text_vpts: usize = 80;
    const o_vinf_text_d_fmt: usize = 64;
    const o_vinf_text_tpack_group: usize = 120; // void* (struct arcan_renderfun_fontgroup*)
    const o_vinf_text_tpack_tui: usize = 128; // void* (struct tui_context*)
    const o_w: usize = 176;
    const o_h: usize = 184;
    const o_update_ts: usize = 8;
    const o_dst_copy: usize = 168;
    const o_hdr_model: usize = 200;
    const o_hdr_drm_eotf: usize = 204;
    const o_hdr_drm_rx: usize = 208;
    const o_hdr_drm_ry: usize = 212;
    const o_hdr_drm_gx: usize = 216;
    const o_hdr_drm_gy: usize = 220;
    const o_hdr_drm_bx: usize = 224;
    const o_hdr_drm_by: usize = 228;
    const o_hdr_drm_wpx: usize = 232;
    const o_hdr_drm_wpy: usize = 236;
    const o_hdr_drm_cll: usize = 248;
    const o_hdr_drm_fll: usize = 252;

    pub fn getGlid(v: *anyopaque) u32 {
        return readField(u32, v, o_vinf_text_glid);
    }
    pub fn getVinfTextRaw(v: *anyopaque) [*]u32 {
        const ptr = readField(?*anyopaque, v, o_vinf_text_raw) orelse unreachable;
        return @ptrCast(@alignCast(ptr));
    }
    pub fn getVinfTextRawPtr(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_vinf_text_raw);
    }
    pub fn getVinfTextSRaw(v: *anyopaque) usize {
        return readField(usize, v, o_vinf_text_s_raw);
    }
    pub fn getVinfTextVpts(v: *anyopaque) i64 {
        return readField(i64, v, o_vinf_text_vpts);
    }
    pub fn setVinfTextVpts(v: *anyopaque, val: i64) void {
        writeField(i64, v, o_vinf_text_vpts, val);
    }
    pub fn getVinfTextDFmt(v: *anyopaque) c_uint {
        return readField(c_uint, v, o_vinf_text_d_fmt);
    }
    pub fn setVinfTextDFmt(v: *anyopaque, val: c_uint) void {
        writeField(c_uint, v, o_vinf_text_d_fmt, val);
    }
    pub fn getTpackGroup(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_vinf_text_tpack_group);
    }
    pub fn getTpackTui(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_vinf_text_tpack_tui);
    }
    pub fn getW(v: *anyopaque) usize {
        return readField(usize, v, o_w);
    }
    pub fn getH(v: *anyopaque) usize {
        return readField(usize, v, o_h);
    }
    pub fn getUpdateTs(v: *anyopaque) u32 {
        return readField(u32, v, o_update_ts);
    }
    pub fn getDstCopy(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_dst_copy);
    }
    pub fn setHdrModel(v: *anyopaque, val: c_int) void {
        writeField(c_int, v, o_hdr_model, val);
    }
    pub fn setHdrDrm(v: *anyopaque, eotf: u32, rx: u16, ry: u16, gx: u16, gy: u16, bx: u16, by: u16, wpx: u16, wpy: u16, cll: u16, fll: u16) void {
        writeField(u32, v, o_hdr_drm_eotf, eotf);
        writeField(u16, v, o_hdr_drm_rx, rx);
        writeField(u16, v, o_hdr_drm_ry, ry);
        writeField(u16, v, o_hdr_drm_gx, gx);
        writeField(u16, v, o_hdr_drm_gy, gy);
        writeField(u16, v, o_hdr_drm_bx, bx);
        writeField(u16, v, o_hdr_drm_by, by);
        writeField(u16, v, o_hdr_drm_wpx, wpx);
        writeField(u16, v, o_hdr_drm_wpy, wpy);
        writeField(u16, v, o_hdr_drm_cll, cll);
        writeField(u16, v, o_hdr_drm_fll, fll);
    }
};

// stream_meta

pub const StreamMeta = struct {
    pub const sizeof_stream_meta: usize = 240;
    const o_buf: usize = 0;
    const o_dirty: usize = 8;
    const o_x1: usize = 12;
    const o_y1: usize = 16;
    const o_w: usize = 20;
    const o_h: usize = 24;

    pub fn zero(out: *anyopaque) void {
        @memset(@as([*]u8, @ptrCast(out))[0..sizeof_stream_meta], 0);
    }
    pub fn setBuf(out: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, out, o_buf, v);
    }
    pub fn setDirty(out: *anyopaque, v: bool) void {
        writeField(bool, out, o_dirty, v);
    }
    pub fn setX1(out: *anyopaque, v: u32) void {
        writeField(u32, out, o_x1, v);
    }
    pub fn setY1(out: *anyopaque, v: u32) void {
        writeField(u32, out, o_y1, v);
    }
    pub fn setW(out: *anyopaque, v: u32) void {
        writeField(u32, out, o_w, v);
    }
    pub fn setH(out: *anyopaque, v: u32) void {
        writeField(u32, out, o_h, v);
    }
};

// agp_buffer_plane

pub const AgpBufferPlane = struct {
    pub const sizeof_plane: usize = 56;
    const o_fd: usize = 0;
    const o_fence: usize = 4;
    const o_w: usize = 8;
    const o_h: usize = 16;
    const o_gbm_format: usize = 24;
    const o_gbm_stride: usize = 32;
    const o_gbm_offset: usize = 40;
    const o_gbm_mod_hi: usize = 48;
    const o_gbm_mod_lo: usize = 52;

    pub fn setFd(p: [*]u8, v: c_int) void {
        const ptr: *align(1) c_int = @ptrCast(p + o_fd);
        ptr.* = v;
    }
    pub fn setFence(p: [*]u8, v: c_int) void {
        const ptr: *align(1) c_int = @ptrCast(p + o_fence);
        ptr.* = v;
    }
    pub fn setGbmStride(p: [*]u8, v: u64) void {
        const ptr: *align(1) u64 = @ptrCast(p + o_gbm_stride);
        ptr.* = v;
    }
    pub fn setGbmOffset(p: [*]u8, v: u64) void {
        const ptr: *align(1) u64 = @ptrCast(p + o_gbm_offset);
        ptr.* = v;
    }
    pub fn setGbmModHi(p: [*]u8, v: u32) void {
        const ptr: *align(1) u32 = @ptrCast(p + o_gbm_mod_hi);
        ptr.* = v;
    }
    pub fn setGbmModLo(p: [*]u8, v: u32) void {
        const ptr: *align(1) u32 = @ptrCast(p + o_gbm_mod_lo);
        ptr.* = v;
    }
    pub fn setGbmFormat(p: [*]u8, v: u32) void {
        const ptr: *align(1) u32 = @ptrCast(p + o_gbm_format);
        ptr.* = v;
    }
    pub fn setW(p: [*]u8, v: usize) void {
        const ptr: *align(1) usize = @ptrCast(p + o_w);
        ptr.* = v;
    }
    pub fn setH(p: [*]u8, v: usize) void {
        const ptr: *align(1) usize = @ptrCast(p + o_h);
        ptr.* = v;
    }
};

// vr_limb (from arcan_shmif_sub.h)
// Contains _Atomic fields (timestamp, data.checksum), accessed via byte offsets.

pub const VrLimb = struct {
    pub const sizeof_vr_limb: usize = 72;
    const o_haptic_id: usize = 0;
    const o_haptic_capabilities: usize = 1;
    const o_ignored: usize = 2;
    const o_limb_type: usize = 3;
    const o_timestamp: usize = 4; // _Atomic uint32_t
    const o_data: usize = 8; // union vr_data (64 bytes)
    const o_data_position_x: usize = 8;
    const o_data_position_y: usize = 12;
    const o_data_position_z: usize = 16;
    const o_data_orientation_x: usize = 32;
    const o_data_orientation_y: usize = 36;
    const o_data_orientation_z: usize = 40;
    const o_data_orientation_w: usize = 44;
    const o_data_checksum: usize = 48; // _Atomic uint16_t

    pub fn getTimestamp(base: [*]u8) u32 {
        const p: *const u32 = @ptrCast(@alignCast(base + o_timestamp));
        return @atomicLoad(u32, p, .seq_cst);
    }

    pub fn getDataChecksum(base: [*]u8) u16 {
        const p: *const u16 = @ptrCast(@alignCast(base + o_data_checksum));
        return @atomicLoad(u16, p, .seq_cst);
    }

    pub fn setIgnored(base: [*]u8, val: bool) void {
        base[o_ignored] = if (val) 1 else 0;
    }

    pub fn getOrientationX(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_orientation_x);
        return p.*;
    }
    pub fn getOrientationY(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_orientation_y);
        return p.*;
    }
    pub fn getOrientationZ(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_orientation_z);
        return p.*;
    }
    pub fn getOrientationW(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_orientation_w);
        return p.*;
    }

    pub fn getPositionX(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_position_x);
        return p.*;
    }
    pub fn getPositionY(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_position_y);
        return p.*;
    }
    pub fn getPositionZ(base: [*]const u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_data_position_z);
        return p.*;
    }
};

// arcan_shmif_vr
// Contains _Atomic fields (limb_mask, ready). limbs[] is a flexible array member.

pub const ShmifVr = struct {
    pub const sizeof_header: usize = 240; // without FAM
    pub const sizeof_vr_meta: usize = 216;
    const o_version: usize = 0;
    const o_limb_lim: usize = 1;
    const o_limb_mask: usize = 8; // _Atomic uint64_t
    const o_ready: usize = 16; // _Atomic uint8_t
    const o_meta: usize = 20;
    const o_limbs: usize = 236; // start of flexible array

    pub fn getLimbMask(base: [*]u8) u64 {
        const p: *const u64 = @ptrCast(@alignCast(base + o_limb_mask));
        return @atomicLoad(u64, p, .seq_cst);
    }

    pub fn getLimbPtr(base: [*]u8, i: usize) [*]u8 {
        return base + o_limbs + i * VrLimb.sizeof_vr_limb;
    }

    pub fn getMetaPtr(base: [*]u8) [*]u8 {
        return base + o_meta;
    }
};

// arcan_vobject (subset of fields for VR)
// The full struct is opaque in Zig; we access specific fields by offset.

pub const Vobj = struct {
    const o_vstore: usize = 24; // struct agp_vstore*
    const o_current_position_x: usize = 104;
    const o_current_position_y: usize = 108;
    const o_current_position_z: usize = 112;
    const o_current_rotation_yaw: usize = 132;
    const o_current_rotation_pitch: usize = 136;
    const o_current_rotation_roll: usize = 140;
    const o_current_rotation_quat_x: usize = 144;
    const o_current_rotation_quat_y: usize = 148;
    const o_current_rotation_quat_z: usize = 152;
    const o_current_rotation_quat_w: usize = 156;
    const o_owner: usize = 368; // struct rendertarget*

    pub fn getVstore(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_vstore);
    }

    pub fn setPositionX(v: *anyopaque, val: f32) void {
        writeField(f32, v, o_current_position_x, val);
    }
    pub fn setPositionY(v: *anyopaque, val: f32) void {
        writeField(f32, v, o_current_position_y, val);
    }
    pub fn setPositionZ(v: *anyopaque, val: f32) void {
        writeField(f32, v, o_current_position_z, val);
    }
    pub fn setRotation(v: *anyopaque, roll: f32, pitch: f32, yaw: f32, qx: f32, qy: f32, qz: f32, qw: f32) void {
        writeField(f32, v, o_current_rotation_roll, roll);
        writeField(f32, v, o_current_rotation_pitch, pitch);
        writeField(f32, v, o_current_rotation_yaw, yaw);
        writeField(f32, v, o_current_rotation_quat_x, qx);
        writeField(f32, v, o_current_rotation_quat_y, qy);
        writeField(f32, v, o_current_rotation_quat_z, qz);
        writeField(f32, v, o_current_rotation_quat_w, qw);
    }
    pub fn getOwner(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_owner);
    }
};

// struct rendertarget (for FLAG_DIRTY)

pub const RenderTarget = struct {
    const o_msc: usize = 144;
    const o_transfc: usize = 224;

    pub fn getMsc(rt: *anyopaque) u64 {
        return readField(u64, rt, o_msc);
    }

    pub fn incrementTransfc(rt: *anyopaque) void {
        const p: *usize = @ptrCast(@alignCast(ptrAdd(rt, o_transfc)));
        p.* += 1;
    }
};

// arcan_video_display (for FLAG_DIRTY)

pub const VideoDisplay = struct {
    pub const o_dirty: usize = 16;

    pub fn incrementDirty(disp: *anyopaque) void {
        const p: *c_uint = @ptrCast(@alignCast(ptrAdd(disp, o_dirty)));
        p.* += 1;
    }
};

// surface_properties (for resolve_and_get_pos)

pub const SurfaceProperties = struct {
    pub const sizeof_surface_properties: usize = 56;
    const o_position_x: usize = 0;
    const o_position_y: usize = 4;
    const o_position_z: usize = 8;

    pub fn getPositionX(base: [*]u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_position_x);
        return p.*;
    }
    pub fn getPositionY(base: [*]u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_position_y);
        return p.*;
    }
    pub fn getPositionZ(base: [*]u8) f32 {
        const p: *align(1) const f32 = @ptrCast(base + o_position_z);
        return p.*;
    }
};

// frameserver_audsrc

pub const Audsrc = struct {
    pub const sizeof_audsrc: usize = 16408;
    const o_inbuf: usize = 0;
    const o_inofs: usize = 16384;
    const o_src_aid: usize = 16392;
    const o_l_gain: usize = 16396;
    const o_r_gain: usize = 16400;
    pub const sizeof_inbuf: usize = 16384;
    pub const inbuf_count: usize = 16384 / @sizeOf(f32); // 4096

    pub fn getSrcAid(base: *anyopaque) i32 {
        return readField(i32, base, o_src_aid);
    }
    pub fn getInofs(base: *anyopaque) isize {
        return readField(isize, base, o_inofs);
    }
    pub fn setInofs(base: *anyopaque, v: isize) void {
        writeField(isize, base, o_inofs, v);
    }
    pub fn getLGain(base: *anyopaque) f32 {
        return readField(f32, base, o_l_gain);
    }
    pub fn setLGain(base: *anyopaque, v: f32) void {
        writeField(f32, base, o_l_gain, v);
    }
    pub fn getRGain(base: *anyopaque) f32 {
        return readField(f32, base, o_r_gain);
    }
    pub fn setRGain(base: *anyopaque, v: f32) void {
        writeField(f32, base, o_r_gain, v);
    }
    pub fn getInbufPtr(base: *anyopaque) [*]f32 {
        return @ptrCast(@alignCast(ptrAdd(base, o_inbuf)));
    }
};

// ramp_block

pub const RampBlock = struct {
    pub const sizeof_ramp_block: usize = 16568;
    const o_format: usize = 0;
    const o_checksum: usize = 2;
    const o_plane_sizes: usize = 8;
    const o_edid: usize = 40;
    const o_planes: usize = 188;
    pub const sizeof_edid: usize = 128;
    pub const cmramp_plim: usize = 4;
    pub const cmramp_uplim: usize = 4095;

    pub fn getChecksum(base: [*]u8) u16 {
        const p: *align(1) const u16 = @ptrCast(base + o_checksum);
        return p.*;
    }
    pub fn setChecksum(base: [*]u8, v: u16) void {
        const p: *align(1) u16 = @ptrCast(base + o_checksum);
        p.* = v;
    }
    pub fn getEdidPtr(base: [*]u8) [*]u8 {
        return base + o_edid;
    }
    pub fn getPlaneSizesPtr(base: [*]u8) [*]u8 {
        return base + o_plane_sizes;
    }
    pub fn getPlanesPtr(base: [*]u8) [*]u8 {
        return base + o_planes;
    }
};

// ShmifHdr (arcan_shmif_hdr for HDR metadata)

pub const ShmifHdr = struct {
    pub const sizeof_hdr: usize = 32;
    const o_drm_eotf: usize = 4;
    const o_drm_rx: usize = 8;
    const o_drm_ry: usize = 10;
    const o_drm_gx: usize = 12;
    const o_drm_gy: usize = 14;
    const o_drm_bx: usize = 16;
    const o_drm_by: usize = 18;
    const o_drm_wpx: usize = 20;
    const o_drm_wpy: usize = 22;
    const o_drm_cll_max: usize = 28;
    const o_drm_fll_max: usize = 30;

    pub fn getDrmEotf(base: *anyopaque) u32 {
        return readField(u32, base, o_drm_eotf);
    }
    pub fn getDrmRx(base: *anyopaque) u16 { return readField(u16, base, o_drm_rx); }
    pub fn getDrmRy(base: *anyopaque) u16 { return readField(u16, base, o_drm_ry); }
    pub fn getDrmGx(base: *anyopaque) u16 { return readField(u16, base, o_drm_gx); }
    pub fn getDrmGy(base: *anyopaque) u16 { return readField(u16, base, o_drm_gy); }
    pub fn getDrmBx(base: *anyopaque) u16 { return readField(u16, base, o_drm_bx); }
    pub fn getDrmBy(base: *anyopaque) u16 { return readField(u16, base, o_drm_by); }
    pub fn getDrmWpx(base: *anyopaque) u16 { return readField(u16, base, o_drm_wpx); }
    pub fn getDrmWpy(base: *anyopaque) u16 { return readField(u16, base, o_drm_wpy); }
    pub fn getDrmCllMax(base: *anyopaque) u16 { return readField(u16, base, o_drm_cll_max); }
    pub fn getDrmFllMax(base: *anyopaque) u16 { return readField(u16, base, o_drm_fll_max); }
};

// VobjFrameset

pub const VobjFrameset = struct {
    const o_index: usize = 16;
    const o_frames: usize = 0;
    pub const sizeof_frame_entry: usize = 40;
    const o_frame_entry_frame: usize = 0;

    pub fn getIndex(fs: *anyopaque) usize {
        return readField(usize, fs, o_index);
    }
    pub fn getFrameVstore(fs: *anyopaque, idx: usize) ?*anyopaque {
        const frames: [*]const u8 = @ptrCast(readField(?*anyopaque, fs, o_frames) orelse return null);
        const entry_base = frames + idx * sizeof_frame_entry;
        const p: *align(1) const ?*anyopaque = @ptrCast(entry_base + o_frame_entry_frame);
        return p.*;
    }
};

// jmp_buf

pub const JmpBuf = struct {
    pub const sizeof_jmp_buf: usize = 312;
};
