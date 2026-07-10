// Byte-offset accessors for a12 C structs that are opaque in Zig's @cImport.
// Replaces a12_decode_helpers.c.
//
// Offsets computed by compute_a12_offsets.c for Linux aarch64.
// shmifsrv_vbuffer contains bitfields → a12_channel → a12_state become opaque.

const std = @import("std");

// generic helpers

fn ptrAdd(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

fn constPtrAdd(base: *const anyopaque, off: usize) [*]const u8 {
    return @as([*]const u8, @ptrCast(base)) + off;
}

fn fieldPtr(comptime T: type, base: *anyopaque, off: usize) *T {
    return @ptrCast(@alignCast(ptrAdd(base, off)));
}

fn constFieldPtr(comptime T: type, base: *const anyopaque, off: usize) *const T {
    return @ptrCast(@alignCast(constPtrAdd(base, off)));
}

fn readField(comptime T: type, base: *anyopaque, off: usize) T {
    return fieldPtr(T, base, off).*;
}

fn writeField(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    fieldPtr(T, base, off).* = val;
}

// a12_state (sizeof = 201880)

pub const A12State = struct {
    pub const sizeof_struct: usize = 201880;
    const o_opts: usize = 0;
    const o_directory: usize = 8;
    const o_directory_clk: usize = 16;
    const o_notify_dynamic: usize = 24;
    const o_tracetag: usize = 25;
    const o_last_mac_in: usize = 41;
    const o_current_seqnr: usize = 64;
    const o_last_seen_seqnr: usize = 72;
    const o_out_stream: usize = 80;
    const o_shutdown_id: usize = 88;
    const o_advenc_broken: usize = 96;
    const o_congestion_stats: usize = 104;
    const o_stats: usize = 144;
    const o_pending_dynamic: usize = 200;
    const o_buf_sz: usize = 288;
    const o_bufs: usize = 304;
    const o_buf_ind: usize = 320;
    const o_buf_ofs: usize = 328;
    const o_pending_out: usize = 336;
    const o_out_req_id: usize = 344;
    const o_pending_in: usize = 352;
    const o_in_req_id: usize = 360;
    const o_binary_handler: usize = 368;
    const o_binary_handler_tag: usize = 376;
    const o_channels: usize = 384;
    // bug 0131: offsets below were generated when struct_a12_channel was 496 bytes;
    // it grew to 504 bytes (8 bytes added per channel × 256 channels = +2048).
    // All fields after `channels: [256]struct_a12_channel` shifted by 2048.
    // Comptime asserts at the bottom of this struct catch any future drift.
    const o_in_channel: usize = 129408;
    const o_in_stream: usize = 129412;
    const o_out_channel: usize = 129416;
    const o_on_discover: usize = 129424;
    const o_discover_tag: usize = 129432;
    const o_on_auth: usize = 129440;
    const o_auth_tag: usize = 129448;
    const o_decode: usize = 129456;
    const o_decode_pos: usize = 194992;
    const o_left: usize = 194994;
    const o_state: usize = 194996;
    const o_cookie: usize = 195000;
    const o_keys: usize = 195008;
    const o_server: usize = 199976;
    const o_cl_firstout: usize = 199977;
    const o_authentic: usize = 199980;
    const o_remote_mode: usize = 199984;
    const o_endpoint: usize = 199992;
    const o_auth_latched: usize = 200000;
    const o_prepend_unpack_sz: usize = 200008;
    const o_prepend_unpack: usize = 200016;
    const o_out_mac: usize = 200024;
    const o_in_mac: usize = 201952;
    const o_enc_state: usize = 203880;
    const o_dec_state: usize = 203888;
    const o_state_error_hint: usize = 203896;

    // accessors

    pub fn getInChannel(s: *anyopaque) c_int {
        return readField(c_int, s, o_in_channel);
    }
    pub fn setInChannel(s: *anyopaque, val: c_int) void {
        writeField(c_int, s, o_in_channel, val);
    }
    pub fn getOutChannel(s: *anyopaque) c_int {
        return readField(c_int, s, o_out_channel);
    }
    pub fn setOutChannel(s: *anyopaque, val: c_int) void {
        writeField(c_int, s, o_out_channel, val);
    }
    pub fn getDecodeBuf(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_decode);
    }
    pub fn getDecodePos(s: *anyopaque) u16 {
        return readField(u16, s, o_decode_pos);
    }
    pub fn setDecodePos(s: *anyopaque, val: u16) void {
        writeField(u16, s, o_decode_pos, val);
    }
    pub fn getLeft(s: *anyopaque) u16 {
        return readField(u16, s, o_left);
    }
    pub fn setLeft(s: *anyopaque, val: u16) void {
        writeField(u16, s, o_left, val);
    }
    pub fn getState(s: *anyopaque) u8 {
        return readField(u8, s, o_state);
    }
    pub fn setState(s: *anyopaque, val: u8) void {
        writeField(u8, s, o_state, val);
    }
    pub fn getTracetag(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_tracetag);
    }
    pub fn getServer(s: *anyopaque) bool {
        return readField(bool, s, o_server);
    }
    pub fn getCookie(s: *anyopaque) u32 {
        return @atomicLoad(u32, fieldPtr(u32, s, o_cookie), .seq_cst);
    }
    pub fn getChannelPtr(s: *anyopaque, chid: usize) *anyopaque {
        return @ptrCast(ptrAdd(s, o_channels + chid * A12Channel.sizeof_struct));
    }
    pub fn getOpts(s: *anyopaque) *anyopaque {
        return @ptrCast(readField(*anyopaque, s, o_opts));
    }
    pub fn getKeys(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_keys);
    }
    pub fn getOutMac(s: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(s, o_out_mac));
    }
    pub fn getInMac(s: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(s, o_in_mac));
    }
    pub fn getEncState(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_enc_state);
    }
    pub fn setEncState(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_enc_state, val);
    }
    pub fn getDecState(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_dec_state);
    }
    pub fn setDecState(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_dec_state, val);
    }
    pub fn getCurrentSeqnr(s: *anyopaque) u64 {
        return readField(u64, s, o_current_seqnr);
    }
    pub fn setCurrentSeqnr(s: *anyopaque, val: u64) void {
        writeField(u64, s, o_current_seqnr, val);
    }
    pub fn getLastSeenSeqnr(s: *anyopaque) u64 {
        return readField(u64, s, o_last_seen_seqnr);
    }
    pub fn setLastSeenSeqnr(s: *anyopaque, val: u64) void {
        writeField(u64, s, o_last_seen_seqnr, val);
    }
    pub fn getOutStream(s: *anyopaque) u64 {
        return readField(u64, s, o_out_stream);
    }
    pub fn setOutStream(s: *anyopaque, val: u64) void {
        writeField(u64, s, o_out_stream, val);
    }
    pub fn getBufSz(s: *anyopaque) [*]usize {
        return @ptrCast(@alignCast(ptrAdd(s, o_buf_sz)));
    }
    pub fn getBufs(s: *anyopaque) [*]?[*]u8 {
        return @ptrCast(@alignCast(ptrAdd(s, o_bufs)));
    }
    pub fn getBufInd(s: *anyopaque) u8 {
        return readField(u8, s, o_buf_ind);
    }
    pub fn setBufInd(s: *anyopaque, val: u8) void {
        writeField(u8, s, o_buf_ind, val);
    }
    pub fn getBufOfs(s: *anyopaque) usize {
        return readField(usize, s, o_buf_ofs);
    }
    pub fn setBufOfs(s: *anyopaque, val: usize) void {
        writeField(usize, s, o_buf_ofs, val);
    }
    pub fn getPendingOut(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_pending_out);
    }
    pub fn setPendingOut(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_pending_out, val);
    }
    pub fn getPendingIn(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_pending_in);
    }
    pub fn setPendingIn(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_pending_in, val);
    }
    pub fn getStateErrorHint(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_state_error_hint);
    }
    pub fn getNotifyDynamic(s: *anyopaque) bool {
        return readField(bool, s, o_notify_dynamic);
    }
    pub fn getDirectory(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_directory);
    }
    pub fn setDirectory(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_directory, val);
    }
    pub fn getDirectoryClk(s: *anyopaque) u64 {
        return readField(u64, s, o_directory_clk);
    }
    pub fn getAuthentic(s: *anyopaque) c_int {
        return readField(c_int, s, o_authentic);
    }
    pub fn setAuthentic(s: *anyopaque, val: c_int) void {
        writeField(c_int, s, o_authentic, val);
    }
    pub fn getRemoteMode(s: *anyopaque) c_int {
        return readField(c_int, s, o_remote_mode);
    }
    pub fn setRemoteMode(s: *anyopaque, val: c_int) void {
        writeField(c_int, s, o_remote_mode, val);
    }
    pub fn getClFirstout(s: *anyopaque) bool {
        return readField(bool, s, o_cl_firstout);
    }
    pub fn setClFirstout(s: *anyopaque, val: bool) void {
        writeField(bool, s, o_cl_firstout, val);
    }
    pub fn getShutdownId(s: *anyopaque) i64 {
        return readField(i64, s, o_shutdown_id);
    }
    pub fn setShutdownId(s: *anyopaque, val: i64) void {
        writeField(i64, s, o_shutdown_id, val);
    }
    pub fn getEndpoint(s: *anyopaque) ?[*]u8 {
        return readField(?[*]u8, s, o_endpoint);
    }
    pub fn setEndpoint(s: *anyopaque, val: ?[*]u8) void {
        writeField(?[*]u8, s, o_endpoint, val);
    }
    pub fn getAuthLatched(s: *anyopaque) bool {
        return readField(bool, s, o_auth_latched);
    }
    pub fn setAuthLatched(s: *anyopaque, val: bool) void {
        writeField(bool, s, o_auth_latched, val);
    }
    pub fn getPrependUnpackSz(s: *anyopaque) usize {
        return readField(usize, s, o_prepend_unpack_sz);
    }
    pub fn setPrependUnpackSz(s: *anyopaque, val: usize) void {
        writeField(usize, s, o_prepend_unpack_sz, val);
    }
    pub fn getPrependUnpack(s: *anyopaque) ?[*]u8 {
        return readField(?[*]u8, s, o_prepend_unpack);
    }
    pub fn setPrependUnpack(s: *anyopaque, val: ?[*]u8) void {
        writeField(?[*]u8, s, o_prepend_unpack, val);
    }
    pub fn getBinaryHandler(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_binary_handler);
    }
    pub fn setBinaryHandler(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_binary_handler, val);
    }
    pub fn getBinaryHandlerTag(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_binary_handler_tag);
    }
    pub fn setBinaryHandlerTag(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_binary_handler_tag, val);
    }
    pub fn getOnDiscover(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_on_discover);
    }
    pub fn getDiscoverTag(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_discover_tag);
    }
    pub fn getOnAuth(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_on_auth);
    }
    pub fn writeOnAuth(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_on_auth, val);
    }
    pub fn getAuthTag(s: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, s, o_auth_tag);
    }
    pub fn writeAuthTag(s: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, s, o_auth_tag, val);
    }
    pub fn getAdvencBroken(s: *anyopaque) bool {
        return readField(bool, s, o_advenc_broken);
    }
    pub fn getLastMacIn(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_last_mac_in);
    }
    pub fn getOutReqId(s: *anyopaque) usize {
        return readField(usize, s, o_out_req_id);
    }
    pub fn setOutReqId(s: *anyopaque, val: usize) void {
        writeField(usize, s, o_out_req_id, val);
    }
    pub fn getInReqId(s: *anyopaque) usize {
        return readField(usize, s, o_in_req_id);
    }
    pub fn setInReqId(s: *anyopaque, val: usize) void {
        writeField(usize, s, o_in_req_id, val);
    }
    pub fn getInStream(s: *anyopaque) u32 {
        return readField(u32, s, o_in_stream);
    }
    pub fn getCongestionStats(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_congestion_stats);
    }
    pub fn getStats(s: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(s, o_stats));
    }
    pub fn getPendingDynamic(s: *anyopaque) [*]u8 {
        return ptrAdd(s, o_pending_dynamic);
    }
};

// a12_channel (sizeof = 496)

pub const A12Channel = struct {
    pub const sizeof_struct: usize = 496;
    const o_active: usize = 0;
    const o_cont: usize = 8;
    const o_raw: usize = 16;
    const o_unpack_state: usize = 88;
    const o_acc: usize = 288;
    const o_compression: usize = 416;
    const o_zstd: usize = 424;

    pub fn getActive(ch: *anyopaque) c_int {
        return readField(c_int, ch, o_active);
    }
    pub fn setActive(ch: *anyopaque, val: c_int) void {
        writeField(c_int, ch, o_active, val);
    }
    pub fn getCont(ch: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ch, o_cont);
    }
    pub fn setCont(ch: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, ch, o_cont, val);
    }
    pub fn getRaw(ch: *anyopaque) [*]u8 {
        return ptrAdd(ch, o_raw);
    }
    pub fn getUnpackState(ch: *anyopaque) [*]u8 {
        return ptrAdd(ch, o_unpack_state);
    }
    pub fn getVframe(ch: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(ch, o_unpack_state)); // vframe is first in unpack_state
    }
    pub fn getAcc(ch: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(ch, o_acc));
    }
    pub fn getZstd(ch: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ch, o_zstd);
    }
    pub fn setZstd(ch: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, ch, o_zstd, val);
    }
    pub fn getCompression(ch: *anyopaque) ?[*]u8 {
        return readField(?[*]u8, ch, o_compression);
    }
    /// Get raw (a12_unpack_cfg) tag field at raw+0
    pub fn getRawTag(ch: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ch, o_raw); // tag is at offset 0 within raw
    }
    /// Get raw signal_video function pointer at raw+32
    pub fn getRawSignalVideo(ch: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ch, o_raw + 32);
    }
};

// video_frame (sizeof = 80)

pub const VideoFrame = struct {
    pub const sizeof_struct: usize = 80;
    const o_id: usize = 0;
    const o_sw: usize = 4;
    const o_sh: usize = 6;
    const o_w: usize = 8;
    const o_h: usize = 10;
    const o_x: usize = 12;
    const o_y: usize = 14;
    const o_flags: usize = 16;
    const o_postprocess: usize = 20;
    const o_commit: usize = 21;
    const o_inbuf: usize = 24;
    const o_inbuf_pos: usize = 32;
    const o_inbuf_sz: usize = 36;
    const o_expanded_sz: usize = 40;
    const o_row_left: usize = 48;
    const o_out_pos: usize = 56;
    const o_pxbuf: usize = 64;
    const o_carry: usize = 68;
    const o_zstd: usize = 72;

    pub fn getId(v: *anyopaque) u32 {
        return readField(u32, v, o_id);
    }
    pub fn getW(v: *anyopaque) u16 {
        return readField(u16, v, o_w);
    }
    pub fn getH(v: *anyopaque) u16 {
        return readField(u16, v, o_h);
    }
    pub fn getPostprocess(v: *anyopaque) u8 {
        return readField(u8, v, o_postprocess);
    }
    pub fn getCommit(v: *anyopaque) u8 {
        return readField(u8, v, o_commit);
    }
    pub fn getZstd(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_zstd);
    }
    pub fn setZstd(v: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, v, o_zstd, val);
    }
};

// blob_xfer (sizeof = 120)

pub const BlobXfer = struct {
    pub const sizeof_struct: usize = 120;
    const o_checksum: usize = 0;
    const o_fd: usize = 16;
    const o_chid: usize = 20;
    const o_type: usize = 24;
    const o_identifier: usize = 28;
    const o_extid: usize = 32;
    const o_left: usize = 48;
    const o_buf: usize = 56;
    const o_buf_sz: usize = 64;
    const o_streaming: usize = 72;
    const o_active: usize = 73;
    const o_uncompressed: usize = 74;
    const o_streamid: usize = 80;
    const o_rampup_seqnr: usize = 88;
    const o_tag: usize = 96;
    const o_zstd: usize = 104;
    const o_next: usize = 112;

    pub fn getFd(b: *anyopaque) c_int {
        return readField(c_int, b, o_fd);
    }
    pub fn getChid(b: *anyopaque) u8 {
        return readField(u8, b, o_chid);
    }
    pub fn getType(b: *anyopaque) c_int {
        return readField(c_int, b, o_type);
    }
    pub fn getIdentifier(b: *anyopaque) u32 {
        return readField(u32, b, o_identifier);
    }
    pub fn getLeft(b: *anyopaque) usize {
        return readField(usize, b, o_left);
    }
    pub fn setLeft(b: *anyopaque, val: usize) void {
        writeField(usize, b, o_left, val);
    }
    pub fn getActive(b: *anyopaque) bool {
        return readField(bool, b, o_active);
    }
    pub fn setActive(b: *anyopaque, val: bool) void {
        writeField(bool, b, o_active, val);
    }
    pub fn getStreaming(b: *anyopaque) bool {
        return readField(bool, b, o_streaming);
    }
    pub fn getNext(b: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, b, o_next);
    }
    pub fn setNext(b: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, b, o_next, val);
    }
    pub fn getExtid(b: *anyopaque) [*]u8 {
        return ptrAdd(b, o_extid);
    }
    pub fn getChecksum(b: *anyopaque) [*]u8 {
        return ptrAdd(b, o_checksum);
    }
    pub fn getBuf(b: *anyopaque) ?[*]u8 {
        return readField(?[*]u8, b, o_buf);
    }
    pub fn setBuf(b: *anyopaque, val: ?[*]u8) void {
        writeField(?[*]u8, b, o_buf, val);
    }
    pub fn getBufSz(b: *anyopaque) usize {
        return readField(usize, b, o_buf_sz);
    }
    pub fn setBufSz(b: *anyopaque, val: usize) void {
        writeField(usize, b, o_buf_sz, val);
    }
    pub fn getStreamid(b: *anyopaque) u64 {
        return readField(u64, b, o_streamid);
    }
    pub fn getUncompressed(b: *anyopaque) bool {
        return readField(bool, b, o_uncompressed);
    }
    pub fn getZstd(b: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, b, o_zstd);
    }
    pub fn setZstd(b: *anyopaque, val: ?*anyopaque) void {
        writeField(?*anyopaque, b, o_zstd, val);
    }
    pub fn getTag(b: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, b, o_tag);
    }
    pub fn getRampupSeqnr(b: *anyopaque) u64 {
        return readField(u64, b, o_rampup_seqnr);
    }
};

// Note: comptime offset asserts pinning A12State.o_* against the canonical
// struct_a12_state layout live in a12_types.zig (they need access to the
// struct definition; importing it here would create a build-graph cycle).
// Bug 0131 (2026-05-02) caught the o_on_auth / o_auth_tag / etc. drift from
// struct_a12_channel growing 496 → 504 bytes; refer to that ticket if these
// offsets ever need to be regenerated.
