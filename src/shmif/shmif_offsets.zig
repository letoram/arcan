// Byte-offset accessors for C structs that are opaque in Zig's @cImport.
// Replaces arcan_shmif_zig_helpers.c, arcan_shmif_server_zig_helpers.c, sync_helpers.c.
//
// Offsets computed by compute_offsets.c for Linux aarch64.
// _Atomic fields use @atomicLoad/@atomicStore; bitfield bools use byte masks.

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

fn atomicLoad(comptime T: type, base: *anyopaque, off: usize) T {
    return @atomicLoad(T, fieldPtr(T, base, off), .seq_cst);
}

fn atomicStore(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    @atomicStore(T, fieldPtr(T, base, off), val, .seq_cst);
}

fn atomicFetchAnd(comptime T: type, base: *anyopaque, off: usize, mask: T) T {
    return @atomicRmw(T, fieldPtr(T, base, off), .And, mask, .release);
}

fn getBitfield(base: *anyopaque, off: usize, mask: u8) bool {
    return (ptrAdd(base, off)[0] & mask) != 0;
}

fn setBitfield(base: *anyopaque, off: usize, mask: u8, val: bool) void {
    if (val) {
        ptrAdd(base, off)[0] |= mask;
    } else {
        ptrAdd(base, off)[0] &= ~mask;
    }
}

// arcan_shmif_page

pub const Page = struct {
    pub const sizeof_page: usize = 32704;
    const o_major: usize = 0;
    const o_minor: usize = 1;
    const o_resized: usize = 2;
    const o_dms: usize = 3;
    const o_aready: usize = 4;
    const o_apending: usize = 8;
    const o_vready: usize = 12;
    const o_vpending: usize = 16;
    const o_async: usize = 24;
    const o_vsync: usize = 32;
    const o_esync: usize = 40;
    const o_abufused: usize = 44;
    const o_hints: usize = 68;
    const o_dirty: usize = 72;
    const o_segment_token: usize = 84;
    const o_cookie: usize = 88;
    const o_childevq_evqueue: usize = 96;
    const o_childevq_front: usize = 16352;
    const o_childevq_back: usize = 16353;
    const o_parentevq_evqueue: usize = 16360;
    const o_parentevq_front: usize = 32616;
    const o_parentevq_back: usize = 32617;
    const o_segment_size: usize = 32624;
    const o_w: usize = 32628;
    const o_h: usize = 32630;
    const o_rows: usize = 32632;
    const o_cols: usize = 32634;
    const o_abufsize: usize = 32636;
    const o_audiorate: usize = 32640;
    const o_vpts: usize = 32648;
    const o_parent: usize = 32656;
    const o_apad: usize = 32660;
    const o_apad_type: usize = 32664;
    const o_last_words: usize = 32668;
    const o_adata: usize = 32704;

    pub const pp_queue_sz: usize = 127;
    pub const abufc_lim: usize = 12;
    pub const sizeof_event: usize = 128;
    pub const sizeof_last_words: usize = 32;
    pub const sizeof_region: usize = 8;

    // simple fields
    pub fn getMajor(p: *anyopaque) u8 {
        return readField(u8, p, o_major);
    }
    pub fn getMinor(p: *anyopaque) u8 {
        return readField(u8, p, o_minor);
    }
    pub fn getResized(p: *anyopaque) i8 {
        return readField(i8, p, o_resized);
    }
    pub fn setResized(p: *anyopaque, v: i8) void {
        writeField(i8, p, o_resized, v);
    }
    pub fn getDms(p: *anyopaque) u8 {
        return readField(u8, p, o_dms);
    }
    pub fn setDms(p: *anyopaque, v: u8) void {
        writeField(u8, p, o_dms, v);
    }
    pub fn getDmsPtr(p: *anyopaque) *volatile u8 {
        return @ptrCast(ptrAdd(p, o_dms));
    }
    pub fn getSegmentToken(p: *anyopaque) u32 {
        return readField(u32, p, o_segment_token);
    }
    pub fn getCookie(p: *anyopaque) u64 {
        return readField(u64, p, o_cookie);
    }
    pub fn getSegmentSize(p: *anyopaque) u32 {
        return readField(u32, p, o_segment_size);
    }
    pub fn getParent(p: *anyopaque) i32 {
        return readField(i32, p, o_parent);
    }

    // atomic u32 fields (aready, apending, vready, vpending, apad, apad_type, audiorate)
    pub fn getAready(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_aready);
    }
    pub fn setAready(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_aready, v);
    }
    pub fn getApending(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_apending);
    }
    pub fn setApending(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_apending, v);
    }
    pub fn fetchAndApending(p: *anyopaque, mask: u32) u32 {
        return atomicFetchAnd(u32, p, o_apending, mask);
    }
    pub fn getVready(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_vready);
    }
    pub fn setVready(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_vready, v);
    }
    pub fn getVpending(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_vpending);
    }
    pub fn setVpending(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_vpending, v);
    }
    pub fn getVreadyPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_vready);
    }
    pub fn getAreadyPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_aready);
    }
    pub fn getVpendingPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_vpending);
    }
    pub fn getApendingPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_apending);
    }
    pub fn getAbufusedPtr(p: *anyopaque, ind: usize) *u16 {
        return fieldPtr(u16, p, o_abufused + ind * 2);
    }
    pub fn getApad(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_apad);
    }
    pub fn getApadPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_apad);
    }
    pub fn setApad(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_apad, v);
    }
    pub fn getApadType(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_apad_type);
    }
    pub fn setApadType(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_apad_type, v);
    }
    pub fn getAudiorate(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_audiorate);
    }
    pub fn setAudiorate(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_audiorate, v);
    }

    // atomic u16 fields (w, h, rows, cols, abufsize)
    pub fn getW(p: *anyopaque) u16 {
        return atomicLoad(u16, p, o_w);
    }
    pub fn setW(p: *anyopaque, v: u16) void {
        atomicStore(u16, p, o_w, v);
    }
    pub fn getH(p: *anyopaque) u16 {
        return atomicLoad(u16, p, o_h);
    }
    pub fn setH(p: *anyopaque, v: u16) void {
        atomicStore(u16, p, o_h, v);
    }
    pub fn getRows(p: *anyopaque) u16 {
        return atomicLoad(u16, p, o_rows);
    }
    pub fn setRows(p: *anyopaque, v: u16) void {
        atomicStore(u16, p, o_rows, v);
    }
    pub fn getCols(p: *anyopaque) u16 {
        return atomicLoad(u16, p, o_cols);
    }
    pub fn setCols(p: *anyopaque, v: u16) void {
        atomicStore(u16, p, o_cols, v);
    }
    pub fn getAbufsize(p: *anyopaque) u16 {
        return atomicLoad(u16, p, o_abufsize);
    }
    pub fn setAbufsize(p: *anyopaque, v: u16) void {
        atomicStore(u16, p, o_abufsize, v);
    }

    // atomic u8 hints
    pub fn getHints(p: *anyopaque) u8 {
        return atomicLoad(u8, p, o_hints);
    }
    pub fn setHints(p: *anyopaque, v: u8) void {
        atomicStore(u8, p, o_hints, v);
    }
    pub fn getHintsPtr(p: *anyopaque) *u8 {
        return fieldPtr(u8, p, o_hints);
    }

    // atomic u64 vpts
    pub fn getVpts(p: *anyopaque) u64 {
        return atomicLoad(u64, p, o_vpts);
    }

    // futex sync fields (async, vsync, esync) — u32 on Linux
    pub fn getAsync(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_async);
    }
    pub fn setAsync(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_async, v);
    }
    pub fn getAsyncPtr(p: *anyopaque) *volatile u32 {
        return @ptrCast(@alignCast(ptrAdd(p, o_async)));
    }
    pub fn getVsync(p: *anyopaque) u32 {
        return atomicLoad(u32, p, o_vsync);
    }
    pub fn setVsync(p: *anyopaque, v: u32) void {
        atomicStore(u32, p, o_vsync, v);
    }
    pub fn getVsyncPtr(p: *anyopaque) *volatile u32 {
        return @ptrCast(@alignCast(ptrAdd(p, o_vsync)));
    }
    pub fn getEsync(p: *anyopaque) u32 {
        return readField(u32, p, o_esync);
    }
    pub fn setEsync(p: *anyopaque, v: u32) void {
        writeField(u32, p, o_esync, v);
    }
    pub fn getEsyncPtr(p: *anyopaque) *u32 {
        return fieldPtr(u32, p, o_esync);
    }

    // abufused array (atomic u16[12])
    pub fn getAbufused(p: *anyopaque, ind: usize) u16 {
        return atomicLoad(u16, p, o_abufused + ind * 2);
    }
    pub fn setAbufused(p: *anyopaque, ind: usize, v: u16) void {
        atomicStore(u16, p, o_abufused + ind * 2, v);
    }

    // dirty region (atomic struct, 8 bytes = 4 x u16)
    pub fn getDirtyPtr(p: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(p, o_dirty));
    }
    // Load dirty as raw 8 bytes (u64), reinterpret as arcan_shmif_region
    pub fn getDirtyRaw(p: *anyopaque) u64 {
        return atomicLoad(u64, p, o_dirty);
    }
    pub fn setDirtyRaw(p: *anyopaque, v: u64) void {
        atomicStore(u64, p, o_dirty, v);
    }

    // event queues
    pub fn childevqEventbuf(p: *anyopaque) [*]u8 {
        return ptrAdd(p, o_childevq_evqueue);
    }
    pub fn childevqFrontPtr(p: *anyopaque) *volatile u8 {
        return @ptrCast(ptrAdd(p, o_childevq_front));
    }
    pub fn childevqBackPtr(p: *anyopaque) *volatile u8 {
        return @ptrCast(ptrAdd(p, o_childevq_back));
    }
    pub fn parentevqEventbuf(p: *anyopaque) [*]u8 {
        return ptrAdd(p, o_parentevq_evqueue);
    }
    pub fn parentevqFrontPtr(p: *anyopaque) *volatile u8 {
        return @ptrCast(ptrAdd(p, o_parentevq_front));
    }
    pub fn parentevqFrontRead(p: *anyopaque) u8 {
        return ptrAdd(p, o_parentevq_front)[0];
    }
    pub fn parentevqFrontWrite(p: *anyopaque, v: u8) void {
        ptrAdd(p, o_parentevq_front)[0] = v;
    }
    pub fn parentevqBackPtr(p: *anyopaque) *volatile u8 {
        return @ptrCast(ptrAdd(p, o_parentevq_back));
    }
    pub fn parentevqBackRead(p: *anyopaque) u8 {
        return ptrAdd(p, o_parentevq_back)[0];
    }
    /// Get pointer to event at index ind in parentevq (each event = 128 bytes)
    pub fn parentevqEvent(p: *anyopaque, ind: u8) [*]u8 {
        return ptrAdd(p, o_parentevq_evqueue + @as(usize, ind) * sizeof_event);
    }

    // last_words (volatile char[32])
    pub fn getLastWordsPtr(p: *anyopaque) [*]volatile u8 {
        return @ptrCast(ptrAdd(p, o_last_words));
    }
    pub fn getLastWordsChar(p: *anyopaque, ind: usize) u8 {
        return ptrAdd(p, o_last_words)[ind];
    }
    pub fn setLastWordsChar(p: *anyopaque, ind: usize, ch: u8) void {
        ptrAdd(p, o_last_words)[ind] = ch;
    }

    // adata (flexible array member at end of struct)
    pub fn getAdataAddr(p: *anyopaque) usize {
        return @intFromPtr(ptrAdd(p, o_adata));
    }

    // cookie computation (reproduces arcan_shmif_cookie_c)
    pub fn computeCookie() u64 {
        var base: u64 = sizeof_event + sizeof_page;
        base |= @as(u64, o_cookie) << 8;
        base |= @as(u64, o_resized) << 16;
        base |= @as(u64, o_aready) << 24;
        base |= @as(u64, o_abufused) << 32;
        base |= @as(u64, o_childevq_front) << 40;
        base |= @as(u64, o_childevq_back) << 48;
        base |= @as(u64, o_parentevq_front) << 56;
        return base;
    }

    // setters for fields used by posix/frameserver.zig
    pub fn setMajor(p: *anyopaque, v: u8) void {
        writeField(u8, p, o_major, v);
    }
    pub fn setMinor(p: *anyopaque, v: u8) void {
        writeField(u8, p, o_minor, v);
    }
    pub fn setParent(p: *anyopaque, v: i32) void {
        writeField(i32, p, o_parent, v);
    }
    pub fn setSegmentSize(p: *anyopaque, v: u32) void {
        writeField(u32, p, o_segment_size, v);
    }
    pub fn setSegmentToken(p: *anyopaque, v: u32) void {
        writeField(u32, p, o_segment_token, v);
    }
    pub fn setCookie(p: *anyopaque, v: u64) void {
        writeField(u64, p, o_cookie, v);
    }
};

// shmif_hidden

pub const Hidden = struct {
    pub const sizeof_hidden: usize = 2584;
    const o_args: usize = 0;
    const o_last_words: usize = 8;
    const o_video_hook: usize = 16;
    const o_video_hook_data: usize = 24;
    const o_support_window_hook: usize = 32;
    const o_support_window_hook_data: usize = 40;
    const o_vbuf_ind: usize = 48;
    const o_vbuf_cnt: usize = 49;
    const o_vbuf_nbuf_active: usize = 50;
    const o_vframe_id: usize = 56;
    const o_vbuf: usize = 64;
    const o_audio_hook: usize = 88;
    const o_audio_hook_data: usize = 96;
    const o_abuf_ind: usize = 104;
    const o_abuf_cnt: usize = 105;
    const o_abuf: usize = 112;
    const o_reset_hook: usize = 208;
    const o_reset_hook_tag: usize = 216;
    const o_initial: usize = 224;
    const o_log_event: usize = 656;
    const o_keystate_store: usize = 660;
    const o_bitfield: usize = 664;
    const o_alt_conn: usize = 672;
    const o_flags: usize = 680;
    const o_type: usize = 684;
    const o_atype: usize = 688;
    const o_guid: usize = 696;
    const o_inev: usize = 712;
    const o_outev: usize = 808;
    const o_lock: usize = 904;
    const o_in_lock: usize = 952;
    const o_in_signal: usize = 953;
    const o_in_migrate: usize = 954;
    const o_lock_id: usize = 960;
    const o_primary_id: usize = 968;
    const o_dh: usize = 976;
    const o_fh: usize = 1104;
    const o_ph: usize = 1232;
    const o_pev_gotev: usize = 1240;
    const o_pev_consumed: usize = 1241;
    const o_pev_handedover: usize = 1242;
    const o_pev_ev: usize = 1248;
    const o_pev_fds: usize = 1376;
    const o_pseg_epipe: usize = 1384;
    const o_pseg_memfd: usize = 1388;
    const o_multipart: usize = 1392;
    const o_multipart_ofs: usize = 2416;
    const o_flush_multipart: usize = 2424;
    const o_mstate: usize = 2428;
    const o_guard_active: usize = 2464;
    const o_guard_local_dms: usize = 2465;
    const o_guard_parent: usize = 2468;
    const o_guard_parent_fd: usize = 2472;
    const o_guard_dms: usize = 2480;
    const o_guard_synch: usize = 2488;
    const o_guard_exitf: usize = 2536;
    const o_guard_page: usize = 2544;

    // dmabuf_vidp sub-struct (compositor-allocated DMA-BUF backing for vidp)
    const o_dmabuf_vidp_fd: usize = 2552;
    const o_dmabuf_vidp_ptr: usize = 2560;
    const o_dmabuf_vidp_map_sz: usize = 2568;
    const o_dmabuf_vidp_stride: usize = 2576;

    // bitfield masks for byte at o_bitfield (664)
    const valid_initial_mask: u8 = 0x01;
    const output_mask: u8 = 0x02;
    const alive_mask: u8 = 0x04;
    const paused_mask: u8 = 0x08;
    const autoclean_mask: u8 = 0x10;

    pub const vbufc_lim: usize = 3;
    pub const abufc_lim: usize = 12;
    pub const sizeof_evctx: usize = 96;
    pub const sizeof_event: usize = 128;
    pub const sizeof_initial: usize = 432;
    pub const sizeof_multipart: usize = 1024;

    // size/zero
    pub fn sizeOf() usize {
        return sizeof_hidden;
    }
    pub fn zero(h: *anyopaque) void {
        const ptr: [*]u8 = @ptrCast(h);
        @memset(ptr[0..sizeof_hidden], 0);
    }

    // bitfield bools
    pub fn getValidInitial(h: *anyopaque) bool {
        return getBitfield(h, o_bitfield, valid_initial_mask);
    }
    pub fn setValidInitial(h: *anyopaque, v: bool) void {
        setBitfield(h, o_bitfield, valid_initial_mask, v);
    }
    pub fn getOutput(h: *anyopaque) bool {
        return getBitfield(h, o_bitfield, output_mask);
    }
    pub fn setOutput(h: *anyopaque, v: bool) void {
        setBitfield(h, o_bitfield, output_mask, v);
    }
    pub fn getAlive(h: *anyopaque) bool {
        return getBitfield(h, o_bitfield, alive_mask);
    }
    pub fn setAlive(h: *anyopaque, v: bool) void {
        setBitfield(h, o_bitfield, alive_mask, v);
    }
    pub fn getPaused(h: *anyopaque) bool {
        return getBitfield(h, o_bitfield, paused_mask);
    }
    pub fn setPaused(h: *anyopaque, v: bool) void {
        setBitfield(h, o_bitfield, paused_mask, v);
    }
    pub fn getAutoclean(h: *anyopaque) bool {
        return getBitfield(h, o_bitfield, autoclean_mask);
    }
    pub fn setAutoclean(h: *anyopaque, v: bool) void {
        setBitfield(h, o_bitfield, autoclean_mask, v);
    }

    // scalar fields
    pub fn getLogEvent(h: *anyopaque) c_int {
        return readField(c_int, h, o_log_event);
    }
    pub fn setLogEvent(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_log_event, v);
    }
    pub fn getKeystateStore(h: *anyopaque) c_int {
        return readField(c_int, h, o_keystate_store);
    }
    pub fn setKeystateStore(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_keystate_store, v);
    }
    pub fn getType(h: *anyopaque) c_int {
        return readField(c_int, h, o_type);
    }
    pub fn setType(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_type, v);
    }
    pub fn getFlags(h: *anyopaque) c_int {
        return readField(c_int, h, o_flags);
    }
    pub fn setFlags(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_flags, v);
    }
    pub fn getAtype(h: *anyopaque) c_int {
        return readField(c_int, h, o_atype);
    }
    pub fn setAtype(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_atype, v);
    }
    pub fn getPh(h: *anyopaque) c_int {
        return readField(c_int, h, o_ph);
    }
    pub fn setPh(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_ph, v);
    }

    // bool fields (non-bitfield)
    pub fn getInSignal(h: *anyopaque) bool {
        return readField(bool, h, o_in_signal);
    }
    pub fn setInSignal(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_in_signal, v);
    }
    pub fn getInMigrate(h: *anyopaque) bool {
        return readField(bool, h, o_in_migrate);
    }
    pub fn setInMigrate(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_in_migrate, v);
    }
    pub fn getInLock(h: *anyopaque) bool {
        return readField(bool, h, o_in_lock);
    }
    pub fn setInLock(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_in_lock, v);
    }
    pub fn getFlushMultipart(h: *anyopaque) bool {
        return readField(bool, h, o_flush_multipart);
    }
    pub fn setFlushMultipart(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_flush_multipart, v);
    }

    // u8 fields
    pub fn getVbufInd(h: *anyopaque) u8 {
        return readField(u8, h, o_vbuf_ind);
    }
    pub fn setVbufInd(h: *anyopaque, v: u8) void {
        writeField(u8, h, o_vbuf_ind, v);
    }
    pub fn getVbufCnt(h: *anyopaque) u8 {
        return readField(u8, h, o_vbuf_cnt);
    }
    pub fn setVbufCnt(h: *anyopaque, v: u8) void {
        writeField(u8, h, o_vbuf_cnt, v);
    }
    pub fn getVbufNbufActive(h: *anyopaque) bool {
        return readField(bool, h, o_vbuf_nbuf_active);
    }
    pub fn setVbufNbufActive(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_vbuf_nbuf_active, v);
    }
    pub fn getAbufInd(h: *anyopaque) u8 {
        return readField(u8, h, o_abuf_ind);
    }
    pub fn setAbufInd(h: *anyopaque, v: u8) void {
        writeField(u8, h, o_abuf_ind, v);
    }
    pub fn getAbufCnt(h: *anyopaque) u8 {
        return readField(u8, h, o_abuf_cnt);
    }
    pub fn setAbufCnt(h: *anyopaque, v: u8) void {
        writeField(u8, h, o_abuf_cnt, v);
    }

    // u64 fields
    pub fn getVframeId(h: *anyopaque) u64 {
        return readField(u64, h, o_vframe_id);
    }
    pub fn setVframeId(h: *anyopaque, v: u64) void {
        writeField(u64, h, o_vframe_id, v);
    }
    pub fn incVframeId(h: *anyopaque) void {
        writeField(u64, h, o_vframe_id, readField(u64, h, o_vframe_id) +% 1);
    }

    // usize fields
    pub fn getMultipartOfs(h: *anyopaque) usize {
        return readField(usize, h, o_multipart_ofs);
    }
    pub fn setMultipartOfs(h: *anyopaque, v: usize) void {
        writeField(usize, h, o_multipart_ofs, v);
    }

    // pointer fields
    pub fn getArgs(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_args);
    }
    pub fn setArgs(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_args, v);
    }
    pub fn getLastWords(h: *anyopaque) [*c]u8 {
        return readField([*c]u8, h, o_last_words);
    }
    pub fn setLastWords(h: *anyopaque, v: [*c]u8) void {
        writeField([*c]u8, h, o_last_words, v);
    }
    pub fn getAltConn(h: *anyopaque) [*c]u8 {
        return readField([*c]u8, h, o_alt_conn);
    }
    pub fn setAltConn(h: *anyopaque, v: [*c]u8) void {
        writeField([*c]u8, h, o_alt_conn, v);
    }

    // function pointer fields (stored as ?*anyopaque)
    pub fn getVideoHook(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_video_hook);
    }
    pub fn setVideoHook(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_video_hook, v);
    }
    pub fn getVideoHookData(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_video_hook_data);
    }
    pub fn setVideoHookData(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_video_hook_data, v);
    }
    pub fn getAudioHook(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_audio_hook);
    }
    pub fn setAudioHook(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_audio_hook, v);
    }
    pub fn getAudioHookData(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_audio_hook_data);
    }
    pub fn setAudioHookData(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_audio_hook_data, v);
    }
    pub fn getResetHook(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_reset_hook);
    }
    pub fn setResetHook(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_reset_hook, v);
    }
    pub fn getResetHookTag(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_reset_hook_tag);
    }
    pub fn setResetHookTag(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_reset_hook_tag, v);
    }
    pub fn getSupportWindowHook(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_support_window_hook);
    }
    pub fn setSupportWindowHook(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_support_window_hook, v);
    }
    pub fn getSupportWindowHookData(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_support_window_hook_data);
    }
    pub fn setSupportWindowHookData(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_support_window_hook_data, v);
    }

    // vbuf/abuf arrays (pointer[N])
    pub fn getVbuf(h: *anyopaque, i: usize) ?[*]u8 {
        return readField(?[*]u8, h, o_vbuf + i * @sizeOf(?[*]u8));
    }
    pub fn setVbuf(h: *anyopaque, i: usize, v: ?[*]u8) void {
        writeField(?[*]u8, h, o_vbuf + i * @sizeOf(?[*]u8), v);
    }
    pub fn getVbufArrayPtr(h: *anyopaque) [*]?[*]u8 {
        return @ptrCast(@alignCast(ptrAdd(h, o_vbuf)));
    }
    pub fn getAbuf(h: *anyopaque, i: usize) ?[*]u8 {
        return readField(?[*]u8, h, o_abuf + i * @sizeOf(?[*]u8));
    }
    pub fn setAbuf(h: *anyopaque, i: usize, v: ?[*]u8) void {
        writeField(?[*]u8, h, o_abuf + i * @sizeOf(?[*]u8), v);
    }
    pub fn getAbufArrayPtr(h: *anyopaque) [*]?[*]u8 {
        return @ptrCast(@alignCast(ptrAdd(h, o_abuf)));
    }

    // struct field pointers (initial, inev, outev, lock, dh, fh, mstate, multipart, guard_synch)
    pub fn getInitialPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_initial));
    }
    pub fn getInevPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_inev));
    }
    pub fn getOutevPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_outev));
    }
    pub fn getLockPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_lock));
    }
    pub fn getDhPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_dh));
    }
    pub fn setDh(h: *anyopaque, ev_bytes: [*]const u8) void {
        @memcpy(ptrAdd(h, o_dh)[0..sizeof_event], ev_bytes[0..sizeof_event]);
    }
    pub fn getFhPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_fh));
    }
    pub fn setFh(h: *anyopaque, ev_bytes: [*]const u8) void {
        @memcpy(ptrAdd(h, o_fh)[0..sizeof_event], ev_bytes[0..sizeof_event]);
    }
    pub fn getMultipartPtr(h: *anyopaque) [*]u8 {
        return ptrAdd(h, o_multipart);
    }
    pub fn getMstatePtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_mstate));
    }

    // pthread fields
    pub fn getLockId(h: *anyopaque) usize {
        return readField(usize, h, o_lock_id);
    }
    pub fn setLockId(h: *anyopaque, v: usize) void {
        writeField(usize, h, o_lock_id, v);
    }
    pub fn getPrimaryId(h: *anyopaque) usize {
        return readField(usize, h, o_primary_id);
    }
    pub fn setPrimaryId(h: *anyopaque, v: usize) void {
        writeField(usize, h, o_primary_id, v);
    }

    // guid
    pub fn getGuidPtr(h: *anyopaque) [*]u64 {
        return @ptrCast(@alignCast(ptrAdd(h, o_guid)));
    }
    pub fn getGuid(h: *anyopaque, i: usize) u64 {
        return readField(u64, h, o_guid + i * 8);
    }
    pub fn setGuid(h: *anyopaque, i: usize, v: u64) void {
        writeField(u64, h, o_guid + i * 8, v);
    }

    // pev sub-struct
    pub fn getPevGotev(h: *anyopaque) bool {
        return readField(bool, h, o_pev_gotev);
    }
    pub fn setPevGotev(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_pev_gotev, v);
    }
    pub fn getPevConsumed(h: *anyopaque) bool {
        return readField(bool, h, o_pev_consumed);
    }
    pub fn setPevConsumed(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_pev_consumed, v);
    }
    pub fn getPevHandedover(h: *anyopaque) bool {
        return readField(bool, h, o_pev_handedover);
    }
    pub fn setPevHandedover(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_pev_handedover, v);
    }
    pub fn getPevEvPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_pev_ev));
    }
    pub fn setPevEv(h: *anyopaque, ev_bytes: [*]const u8) void {
        @memcpy(ptrAdd(h, o_pev_ev)[0..sizeof_event], ev_bytes[0..sizeof_event]);
    }
    pub fn getPevFd(h: *anyopaque, i: usize) c_int {
        return readField(c_int, h, o_pev_fds + i * @sizeOf(c_int));
    }
    pub fn setPevFd(h: *anyopaque, i: usize, v: c_int) void {
        writeField(c_int, h, o_pev_fds + i * @sizeOf(c_int), v);
    }
    pub fn getPevFdsPtr(h: *anyopaque) [*]c_int {
        return @ptrCast(@alignCast(ptrAdd(h, o_pev_fds)));
    }

    // pseg sub-struct
    pub fn getPsegEpipe(h: *anyopaque) c_int {
        return readField(c_int, h, o_pseg_epipe);
    }
    pub fn setPsegEpipe(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_pseg_epipe, v);
    }
    pub fn getPsegMemfd(h: *anyopaque) c_int {
        return readField(c_int, h, o_pseg_memfd);
    }
    pub fn setPsegMemfd(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_pseg_memfd, v);
    }

    // guard sub-struct
    pub fn getGuardActive(h: *anyopaque) bool {
        return readField(bool, h, o_guard_active);
    }
    pub fn setGuardActive(h: *anyopaque, v: bool) void {
        writeField(bool, h, o_guard_active, v);
    }
    pub fn getGuardLocalDms(h: *anyopaque) bool {
        return atomicLoad(bool, h, o_guard_local_dms);
    }
    pub fn setGuardLocalDms(h: *anyopaque, v: bool) void {
        atomicStore(bool, h, o_guard_local_dms, v);
    }
    pub fn getGuardParent(h: *anyopaque) c_int {
        return readField(c_int, h, o_guard_parent);
    }
    pub fn setGuardParent(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_guard_parent, v);
    }
    pub fn getGuardParentFd(h: *anyopaque) c_int {
        return readField(c_int, h, o_guard_parent_fd);
    }
    pub fn setGuardParentFd(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_guard_parent_fd, v);
    }
    pub fn getGuardDms(h: *anyopaque) ?*volatile u8 {
        return readField(?*volatile u8, h, o_guard_dms);
    }
    pub fn setGuardDms(h: *anyopaque, v: ?*volatile u8) void {
        writeField(?*volatile u8, h, o_guard_dms, v);
    }
    pub fn getGuardSynchPtr(h: *anyopaque) *anyopaque {
        return @ptrCast(ptrAdd(h, o_guard_synch));
    }
    pub fn getGuardExitf(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_guard_exitf);
    }
    pub fn setGuardExitf(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_guard_exitf, v);
    }
    pub fn getGuardPage(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_guard_page);
    }
    pub fn setGuardPage(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_guard_page, v);
    }

    // dmabuf_vidp sub-struct
    pub fn getDmabufVidpFd(h: *anyopaque) c_int {
        return readField(c_int, h, o_dmabuf_vidp_fd);
    }
    pub fn setDmabufVidpFd(h: *anyopaque, v: c_int) void {
        writeField(c_int, h, o_dmabuf_vidp_fd, v);
    }
    pub fn getDmabufVidpPtr(h: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, h, o_dmabuf_vidp_ptr);
    }
    pub fn setDmabufVidpPtr(h: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, h, o_dmabuf_vidp_ptr, v);
    }
    pub fn getDmabufVidpMapSz(h: *anyopaque) usize {
        return readField(usize, h, o_dmabuf_vidp_map_sz);
    }
    pub fn setDmabufVidpMapSz(h: *anyopaque, v: usize) void {
        writeField(usize, h, o_dmabuf_vidp_map_sz, v);
    }
    pub fn getDmabufVidpStride(h: *anyopaque) u32 {
        return readField(u32, h, o_dmabuf_vidp_stride);
    }
    pub fn setDmabufVidpStride(h: *anyopaque, v: u32) void {
        writeField(u32, h, o_dmabuf_vidp_stride, v);
    }
};

// mstate

pub const Mstate = struct {
    pub const sizeof_mstate: usize = 32;
    const o_ax: usize = 0;
    const o_ay: usize = 4;
    const o_lx: usize = 8;
    const o_ly: usize = 12;
    const o_bitfield: usize = 16;
    const rel_mask: u8 = 0x01;
    const inrel_mask: u8 = 0x02;
    const noclamp_mask: u8 = 0x04;

    pub fn getAx(m: *anyopaque) i32 {
        return readField(i32, m, o_ax);
    }
    pub fn setAx(m: *anyopaque, v: i32) void {
        writeField(i32, m, o_ax, v);
    }
    pub fn getAy(m: *anyopaque) i32 {
        return readField(i32, m, o_ay);
    }
    pub fn setAy(m: *anyopaque, v: i32) void {
        writeField(i32, m, o_ay, v);
    }
    pub fn getLx(m: *anyopaque) i32 {
        return readField(i32, m, o_lx);
    }
    pub fn setLx(m: *anyopaque, v: i32) void {
        writeField(i32, m, o_lx, v);
    }
    pub fn getLy(m: *anyopaque) i32 {
        return readField(i32, m, o_ly);
    }
    pub fn setLy(m: *anyopaque, v: i32) void {
        writeField(i32, m, o_ly, v);
    }
    pub fn getRel(m: *anyopaque) u8 {
        return if (getBitfield(m, o_bitfield, rel_mask)) 1 else 0;
    }
    pub fn setRel(m: *anyopaque, v: u8) void {
        setBitfield(m, o_bitfield, rel_mask, v != 0);
    }
    pub fn getInrel(m: *anyopaque) u8 {
        return if (getBitfield(m, o_bitfield, inrel_mask)) 1 else 0;
    }
    pub fn setInrel(m: *anyopaque, v: u8) void {
        setBitfield(m, o_bitfield, inrel_mask, v != 0);
    }
    pub fn getNoclamp(m: *anyopaque) u8 {
        return if (getBitfield(m, o_bitfield, noclamp_mask)) 1 else 0;
    }
    pub fn setNoclamp(m: *anyopaque, v: u8) void {
        setBitfield(m, o_bitfield, noclamp_mask, v != 0);
    }
    pub fn zeroMstate(m: *anyopaque) void {
        const ptr: [*]u8 = @ptrCast(m);
        @memset(ptr[0..sizeof_mstate], 0);
    }
};

// shmifsrv_vbuffer

pub const VBuf = struct {
    pub const sizeof_vbuf: usize = 128;
    const o_state: usize = 0;
    const o_buffer: usize = 8;
    const o_flags: usize = 16;
    const o_fourcc: usize = 17;
    const o_buffer_sz: usize = 24;
    const o_w: usize = 32;
    const o_h: usize = 40;
    const o_pitch: usize = 48;
    const o_stride: usize = 56;
    const o_vpts: usize = 64;
    const o_region: usize = 72;
    const o_formats: usize = 80;
    const o_planes: usize = 112;

    // flag masks (byte at o_flags = 16)
    const origo_ll_mask: u8 = 0x01;
    const ignore_alpha_mask: u8 = 0x02;
    const subregion_mask: u8 = 0x04;
    const srgb_mask: u8 = 0x08;
    const hwhandles_mask: u8 = 0x10;
    const tpack_mask: u8 = 0x20;
    const compressed_mask: u8 = 0x40;

    pub fn getState(v: *anyopaque) c_int {
        return readField(c_int, v, o_state);
    }
    pub fn getBuffer(v: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, v, o_buffer);
    }
    pub fn getW(v: *anyopaque) usize {
        return readField(usize, v, o_w);
    }
    pub fn getH(v: *anyopaque) usize {
        return readField(usize, v, o_h);
    }
    pub fn getPitch(v: *anyopaque) usize {
        return readField(usize, v, o_pitch);
    }
    pub fn getStride(v: *anyopaque) usize {
        return readField(usize, v, o_stride);
    }
    pub fn getVpts(v: *anyopaque) u64 {
        return readField(u64, v, o_vpts);
    }
    pub fn getBufferSz(v: *anyopaque) usize {
        return readField(usize, v, o_buffer_sz);
    }

    // flag accessors
    pub fn getOrigoLl(v: *anyopaque) bool {
        return getBitfield(v, o_flags, origo_ll_mask);
    }
    pub fn setOrigoLl(v: *anyopaque, b: bool) void {
        setBitfield(v, o_flags, origo_ll_mask, b);
    }
    pub fn getIgnoreAlpha(v: *anyopaque) bool {
        return getBitfield(v, o_flags, ignore_alpha_mask);
    }
    pub fn getSubregion(v: *anyopaque) bool {
        return getBitfield(v, o_flags, subregion_mask);
    }
    pub fn setSubregion(v: *anyopaque, b: bool) void {
        setBitfield(v, o_flags, subregion_mask, b);
    }
    pub fn getSrgb(v: *anyopaque) bool {
        return getBitfield(v, o_flags, srgb_mask);
    }
    pub fn getHwhandles(v: *anyopaque) bool {
        return getBitfield(v, o_flags, hwhandles_mask);
    }
    pub fn getTpack(v: *anyopaque) bool {
        return getBitfield(v, o_flags, tpack_mask);
    }
    pub fn getCompressed(v: *anyopaque) bool {
        return getBitfield(v, o_flags, compressed_mask);
    }
    pub fn setCompressed(v: *anyopaque, b: bool) void {
        setBitfield(v, o_flags, compressed_mask, b);
    }

    /// Construct a minimal vbuffer (for shmifsrv_put_video_simple replacement)
    pub fn initSimple(buf: [*]u8, w: usize, h: usize, pitch: usize, stride: usize, buffer_ptr: ?*anyopaque) void {
        @memset(buf[0..sizeof_vbuf], 0);
        writeField(usize, @ptrCast(@alignCast(buf)), o_w, w);
        writeField(usize, @ptrCast(@alignCast(buf)), o_h, h);
        writeField(usize, @ptrCast(@alignCast(buf)), o_pitch, pitch);
        writeField(usize, @ptrCast(@alignCast(buf)), o_stride, stride);
        writeField(?*anyopaque, @ptrCast(@alignCast(buf)), o_buffer, buffer_ptr);
    }
};

// arcan_frameserver

pub const Fsrv = struct {
    const o_desc_width: usize = 0;
    const o_desc_height: usize = 2;
    const o_desc_hints: usize = 28;
    const o_desc_pending_hints: usize = 32;
    const o_desc_channels: usize = 240;
    const o_desc_samplerate: usize = 236;
    const o_desc_aproto: usize = 256;
    const o_desc_aext_vr: usize = 400;
    const o_desc_aext_venc: usize = 424;
    const o_dpipe: usize = 688;
    const o_segid: usize = 2000;
    const o_shm_ptr: usize = 2032;
    const o_shm_handle: usize = 2040;
    const o_vbufs: usize = 2096;
    const o_abufs: usize = 2120;
    const o_vbuf_cnt: usize = 2080;
    const o_abuf_cnt: usize = 2064;
    const o_metamask: usize = 736;
    const o_clock_left: usize = 768;
    const o_clock_start: usize = 772;
    const o_clock_id: usize = 784;
    const o_clock_present: usize = 788;
    const o_clock_last_msc: usize = 792;
    const o_clock_msc_feedback: usize = 796;
    const o_clock_frame: usize = 797;
    const o_clock_once: usize = 798;
    const o_clock_vblank: usize = 799;
    const o_desc_recovery_tick: usize = 472;
    // flags bitfield byte + masks
    const o_flags: usize = 756;
    const no_dms_free_mask: u8 = 0x80;
    const autoclock_mask: u8 = 0x20;
    const flags_locked_byte: usize = 757;
    const flags_locked_mask: u8 = 0x02;

    pub fn getDpipe(f: *anyopaque) c_int {
        return readField(c_int, f, o_dpipe);
    }
    pub fn setDpipe(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_dpipe, v);
    }
    pub fn getSegid(f: *anyopaque) c_int {
        return readField(c_int, f, o_segid);
    }
    pub fn setSegid(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_segid, v);
    }
    pub fn getShmHandle(f: *anyopaque) c_int {
        return readField(c_int, f, o_shm_handle);
    }
    pub fn getShmPtr(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_shm_ptr);
    }

    // desc fields
    pub fn getDescWidth(f: *anyopaque) u16 {
        return readField(u16, f, o_desc_width);
    }
    pub fn getDescHeight(f: *anyopaque) u16 {
        return readField(u16, f, o_desc_height);
    }
    pub fn getDescHints(f: *anyopaque) c_int {
        return readField(c_int, f, o_desc_hints);
    }
    pub fn setDescHints(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_desc_hints, v);
    }
    pub fn getDescPendingHints(f: *anyopaque) c_int {
        return readField(c_int, f, o_desc_pending_hints);
    }
    pub fn getDescChannels(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_desc_channels);
    }
    pub fn getDescSamplerate(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_desc_samplerate);
    }
    pub fn getDescAproto(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_desc_aproto);
    }
    pub fn getDescAextVr(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_desc_aext_vr);
    }
    pub fn getDescAextVenc(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_desc_aext_venc);
    }

    // buffer arrays
    pub fn getVbufs(f: *anyopaque, i: usize) ?*anyopaque {
        return readField(?*anyopaque, f, o_vbufs + i * @sizeOf(?*anyopaque));
    }
    pub fn getAbufs(f: *anyopaque, i: usize) ?*anyopaque {
        return readField(?*anyopaque, f, o_abufs + i * @sizeOf(?*anyopaque));
    }
    pub fn getVbufCnt(f: *anyopaque) usize {
        return readField(usize, f, o_vbuf_cnt);
    }
    pub fn getAbufCnt(f: *anyopaque) usize {
        return readField(usize, f, o_abuf_cnt);
    }

    // metamask
    pub fn getMetamask(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_metamask);
    }
    pub fn setMetamask(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_metamask, v);
    }

    // clock fields
    pub fn getClockLeft(f: *anyopaque) u32 {
        return readField(u32, f, o_clock_left);
    }
    pub fn setClockLeft(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_clock_left, v);
    }
    pub fn getClockStart(f: *anyopaque) u32 {
        return readField(u32, f, o_clock_start);
    }
    pub fn setClockStart(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_clock_start, v);
    }
    pub fn getClockId(f: *anyopaque) u32 {
        return readField(u32, f, o_clock_id);
    }
    pub fn setClockId(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_clock_id, v);
    }
    pub fn getClockPresent(f: *anyopaque) u32 {
        return readField(u32, f, o_clock_present);
    }
    pub fn setClockPresent(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_clock_present, v);
    }
    // clock bools (individual bytes, not bitfields)
    pub fn getClockOnce(f: *anyopaque) bool {
        return readField(bool, f, o_clock_once);
    }
    pub fn setClockOnce(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_clock_once, v);
    }
    pub fn getClockFrame(f: *anyopaque) bool {
        return readField(bool, f, o_clock_frame);
    }
    pub fn setClockFrame(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_clock_frame, v);
    }
    pub fn getClockMscFeedback(f: *anyopaque) bool {
        return readField(bool, f, o_clock_msc_feedback);
    }
    pub fn setClockMscFeedback(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_clock_msc_feedback, v);
    }
    pub fn getClockVblank(f: *anyopaque) bool {
        return readField(bool, f, o_clock_vblank);
    }
    pub fn setClockVblank(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_clock_vblank, v);
    }

    // flags bitfield
    pub fn getFlagsNoDmsFree(f: *anyopaque) bool {
        return getBitfield(f, o_flags, no_dms_free_mask);
    }
    pub fn setFlagsNoDmsFree(f: *anyopaque, v: bool) void {
        setBitfield(f, o_flags, no_dms_free_mask, v);
    }
    pub fn getFlagsAutoclock(f: *anyopaque) bool {
        return getBitfield(f, o_flags, autoclock_mask);
    }
    pub fn setDescRecoveryTick(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_desc_recovery_tick, v);
    }
    pub fn setFlagsLocked(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_locked_byte, flags_locked_mask, v);
    }

    // Extended fields for arcan_event_queuetransfer

    const o_vid: usize = 816;
    const o_tag: usize = 2024;
    const o_fused: usize = 752;
    const o_fuse_blown: usize = 753;
    const o_devicemask: usize = 740;
    const o_datamask: usize = 744;
    const o_guid: usize = 2008;
    const o_title: usize = 1936;
    const o_outqueue: usize = 576;
    const o_vstream_dead: usize = 904;
    const o_vstream_pending: usize = 912;
    const o_vstream_pending_used: usize = 1136;
    const o_vstream_incoming: usize = 1144;
    const o_vstream_incoming_used: usize = 1368;
    pub const sizeof_agp_buffer_plane: usize = 56;
    pub const sizeof_title: usize = 64;
    pub const sizeof_guid: usize = 16;

    // flags.external/networked/sandboxed bitfield masks
    const flags_external_byte: usize = 757;
    const flags_external_mask: u8 = 0x20;
    const flags_networked_byte: usize = 757;
    const flags_networked_mask: u8 = 0x40;
    const flags_sandboxed_byte: usize = 757;
    const flags_sandboxed_mask: u8 = 0x80;

    // NEW: fields for arcan_frameserver_helpers.c absorption
    const o_aid: usize = 808;
    const o_cookie: usize = 892;
    const o_cookie_fail: usize = 896;
    const o_queue_mask: usize = 672;
    const o_xfer_sat: usize = 748;
    const o_inqueue: usize = 480;
    const o_watch_const: usize = 2272;
    const o_audio_flush_pending: usize = 754;
    const o_clock_frametime: usize = 776;
    const o_desc_rows: usize = 8;
    const o_desc_cols: usize = 16;
    const o_desc_rz_flag: usize = 36;
    const o_desc_region_valid: usize = 46;
    const o_desc_callback_framestate: usize = 440;
    const o_desc_framecount: usize = 448;
    const o_desc_dropcount: usize = 456;
    const o_desc_synch_ts: usize = 232;
    const o_desc_region_x1: usize = 38;
    const o_desc_region_y1: usize = 42;
    const o_desc_region_x2: usize = 40;
    const o_desc_region_y2: usize = 44;
    const o_desc_text_group: usize = 48;
    const o_desc_text_cellw: usize = 64;
    const o_desc_text_cellh: usize = 72;
    const o_desc_text_szmm: usize = 60;
    const o_desc_hint_ppcm: usize = 224;
    const o_desc_hint_width: usize = 208;
    const o_desc_hint_height: usize = 216;
    const o_desc_aext_hdr: usize = 416;
    const o_desc_aext_gamma: usize = 392;
    const o_desc_aext_gamma_map: usize = 432;
    const o_playstate: usize = 864;
    const o_vfcount: usize = 888;
    const o_sz_audb: usize = 1384;
    const o_ofs_audb: usize = 1392;
    const o_audb: usize = 1408;
    const o_alocks: usize = 800;
    const o_n_pending: usize = 1416;
    const o_pending_queue: usize = 1424;
    const o_rz_known: usize = 2088;
    const o_shm_external: usize = 2056;
    const o_parent_vid: usize = 832;
    const o_parent_ptr: usize = 824;
    const o_sockkey: usize = 728;
    const o_amixer_n_aids: usize = 840;
    const o_amixer_inaud: usize = 856;
    pub const sizeof_pending_queue: usize = 512;
    pub const sizeof_event: usize = 128;
    // flags bitfield probes for new fields
    const flags_alive_byte: usize = 756;
    const flags_alive_mask: u8 = 0x01;
    const flags_explicit_byte: usize = 756;
    const flags_explicit_mask: u8 = 0x04;
    const flags_local_copy_byte: usize = 756;
    const flags_local_copy_mask: u8 = 0x08;
    const flags_no_alpha_copy_byte: usize = 756;
    const flags_no_alpha_copy_mask: u8 = 0x10;
    const flags_rz_ack_byte: usize = 757;
    const flags_rz_ack_mask: u8 = 0x01;
    const flags_release_pending_byte: usize = 757;
    const flags_release_pending_mask: u8 = 0x04;
    const flags_block_hdr_meta_byte: usize = 757;
    const flags_block_hdr_meta_mask: u8 = 0x10;

    // NEW accessors
    pub fn getAid(f: *anyopaque) i32 {
        return readField(i32, f, o_aid);
    }
    pub fn setAid(f: *anyopaque, v: i32) void {
        writeField(i32, f, o_aid, v);
    }
    pub fn getCookie(f: *anyopaque) u32 {
        return readField(u32, f, o_cookie);
    }
    pub fn getCookieFail(f: *anyopaque) bool {
        return readField(bool, f, o_cookie_fail);
    }
    pub fn setCookieFail(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_cookie_fail, v);
    }
    pub fn getQueueMask(f: *anyopaque) c_int {
        return readField(c_int, f, o_queue_mask);
    }
    pub fn getXferSat(f: *anyopaque) f32 {
        return readField(f32, f, o_xfer_sat);
    }
    pub fn getInqueuePtr(f: *anyopaque) *anyopaque {
        return @ptrCast(@alignCast(ptrAdd(f, o_inqueue)));
    }
    pub fn getWatchConst(f: *anyopaque) u16 {
        return readField(u16, f, o_watch_const);
    }
    pub fn getAudioFlushPending(f: *anyopaque) bool {
        return readField(bool, f, o_audio_flush_pending);
    }
    pub fn setAudioFlushPending(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_audio_flush_pending, v);
    }
    pub fn getClockFrametime(f: *anyopaque) i64 {
        return readField(i64, f, o_clock_frametime);
    }
    pub fn setClockFrametime(f: *anyopaque, v: i64) void {
        writeField(i64, f, o_clock_frametime, v);
    }
    pub fn getDescRows(f: *anyopaque) usize {
        return readField(usize, f, o_desc_rows);
    }
    pub fn getDescCols(f: *anyopaque) usize {
        return readField(usize, f, o_desc_cols);
    }
    pub fn getDescRzFlag(f: *anyopaque) bool {
        return readField(bool, f, o_desc_rz_flag);
    }
    pub fn setDescRzFlag(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_desc_rz_flag, v);
    }
    pub fn getDescRegionValid(f: *anyopaque) bool {
        return readField(bool, f, o_desc_region_valid);
    }
    pub fn setDescRegionValid(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_desc_region_valid, v);
    }
    pub fn getDescCallbackFramestate(f: *anyopaque) bool {
        return readField(bool, f, o_desc_callback_framestate);
    }
    pub fn getDescFramecount(f: *anyopaque) u64 {
        return readField(u64, f, o_desc_framecount);
    }
    pub fn setDescFramecount(f: *anyopaque, v: u64) void {
        writeField(u64, f, o_desc_framecount, v);
    }
    pub fn incDescFramecount(f: *anyopaque) void {
        const p = fieldPtr(u64, f, o_desc_framecount);
        p.* += 1;
    }
    pub fn getDescDropcount(f: *anyopaque) u64 {
        return readField(u64, f, o_desc_dropcount);
    }
    pub fn incDescDropcount(f: *anyopaque) void {
        const p = fieldPtr(u64, f, o_desc_dropcount);
        p.* += 1;
    }
    pub fn getDescSynchTs(f: *anyopaque) u32 {
        return readField(u32, f, o_desc_synch_ts);
    }
    pub fn setDescSynchTs(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_desc_synch_ts, v);
    }
    pub fn getDescRegionX1(f: *anyopaque) i16 {
        return readField(i16, f, o_desc_region_x1);
    }
    pub fn getDescRegionY1(f: *anyopaque) i16 {
        return readField(i16, f, o_desc_region_y1);
    }
    pub fn getDescRegionX2(f: *anyopaque) i16 {
        return readField(i16, f, o_desc_region_x2);
    }
    pub fn getDescRegionY2(f: *anyopaque) i16 {
        return readField(i16, f, o_desc_region_y2);
    }
    pub fn setDescRegion(f: *anyopaque, x1: i16, y1: i16, x2: i16, y2: i16) void {
        writeField(i16, f, o_desc_region_x1, x1);
        writeField(i16, f, o_desc_region_y1, y1);
        writeField(i16, f, o_desc_region_x2, x2);
        writeField(i16, f, o_desc_region_y2, y2);
    }
    pub fn getDescTextGroup(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_desc_text_group);
    }
    pub fn setDescTextGroup(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_desc_text_group, v);
    }
    pub fn getDescTextCellw(f: *anyopaque) usize {
        return readField(usize, f, o_desc_text_cellw);
    }
    pub fn setDescTextCellw(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_text_cellw, v);
    }
    pub fn getDescTextCellh(f: *anyopaque) usize {
        return readField(usize, f, o_desc_text_cellh);
    }
    pub fn setDescTextCellh(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_text_cellh, v);
    }
    pub fn getDescTextSzmm(f: *anyopaque) f32 {
        return readField(f32, f, o_desc_text_szmm);
    }
    pub fn setDescTextSzmm(f: *anyopaque, v: f32) void {
        writeField(f32, f, o_desc_text_szmm, v);
    }
    pub fn getDescHintPpcm(f: *anyopaque) f32 {
        return readField(f32, f, o_desc_hint_ppcm);
    }
    pub fn setDescHintPpcm(f: *anyopaque, v: f32) void {
        writeField(f32, f, o_desc_hint_ppcm, v);
    }
    pub fn getDescHintWidth(f: *anyopaque) usize {
        return readField(usize, f, o_desc_hint_width);
    }
    pub fn setDescHintWidth(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_hint_width, v);
    }
    pub fn getDescHintHeight(f: *anyopaque) usize {
        return readField(usize, f, o_desc_hint_height);
    }
    pub fn setDescHintHeight(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_hint_height, v);
    }
    pub fn getDescAextHdr(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_desc_aext_hdr);
    }
    pub fn getDescAextGamma(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_desc_aext_gamma);
    }
    pub fn getDescAextGammaMap(f: *anyopaque) u8 {
        return readField(u8, f, o_desc_aext_gamma_map);
    }
    pub fn setDescAextGammaMap(f: *anyopaque, v: u8) void {
        writeField(u8, f, o_desc_aext_gamma_map, v);
    }
    pub fn getPlaystate(f: *anyopaque) c_int {
        return readField(c_int, f, o_playstate);
    }
    pub fn setPlaystate(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_playstate, v);
    }
    pub fn getVfcount(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_vfcount);
    }
    pub fn incVfcount(f: *anyopaque) void {
        const p = fieldPtr(c_uint, f, o_vfcount);
        p.* += 1;
    }
    pub fn getSzAudb(f: *anyopaque) usize {
        return readField(usize, f, o_sz_audb);
    }
    pub fn setSzAudb(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_sz_audb, v);
    }
    pub fn getOfsAudb(f: *anyopaque) isize {
        return readField(isize, f, o_ofs_audb);
    }
    pub fn setOfsAudb(f: *anyopaque, v: isize) void {
        writeField(isize, f, o_ofs_audb, v);
    }
    pub fn getAudb(f: *anyopaque) ?[*]u8 {
        return readField(?[*]u8, f, o_audb);
    }
    pub fn setAudb(f: *anyopaque, v: ?[*]u8) void {
        writeField(?[*]u8, f, o_audb, v);
    }
    pub fn getAlocks(f: *anyopaque) ?[*]i32 {
        return readField(?[*]i32, f, o_alocks);
    }
    pub fn setAlocks(f: *anyopaque, v: ?[*]i32) void {
        writeField(?[*]i32, f, o_alocks, v);
    }
    pub fn getNPending(f: *anyopaque) usize {
        return readField(usize, f, o_n_pending);
    }
    pub fn setNPending(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_n_pending, v);
    }
    pub fn getPendingQueuePtr(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_pending_queue);
    }
    pub fn getRzKnown(f: *anyopaque) c_int {
        return readField(c_int, f, o_rz_known);
    }
    pub fn setRzKnown(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_rz_known, v);
    }
    pub fn getShmExternal(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_shm_external);
    }
    pub fn getParentVid(f: *anyopaque) i64 {
        return readField(i64, f, o_parent_vid);
    }
    pub fn setParentVid(f: *anyopaque, v: i64) void {
        writeField(i64, f, o_parent_vid, v);
    }
    pub fn getParentPtr(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_parent_ptr);
    }
    pub fn getSockkey(f: *anyopaque) [*c]const u8 {
        return readField([*c]const u8, f, o_sockkey);
    }
    pub fn getAmixerNAids(f: *anyopaque) c_int {
        return readField(c_int, f, o_amixer_n_aids);
    }
    pub fn setAmixerNAids(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_amixer_n_aids, v);
    }
    pub fn getAmixerInaud(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_amixer_inaud);
    }
    pub fn setAmixerInaud(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_amixer_inaud, v);
    }
    // flags bitfield accessors for new fields
    pub fn getFlagsAlive(f: *anyopaque) bool {
        return getBitfield(f, flags_alive_byte, flags_alive_mask);
    }
    pub fn getFlagsExplicit(f: *anyopaque) bool {
        return getBitfield(f, flags_explicit_byte, flags_explicit_mask);
    }
    pub fn getFlagsLocalCopy(f: *anyopaque) bool {
        return getBitfield(f, flags_local_copy_byte, flags_local_copy_mask);
    }
    pub fn getFlagsNoAlphaCopy(f: *anyopaque) bool {
        return getBitfield(f, flags_no_alpha_copy_byte, flags_no_alpha_copy_mask);
    }
    pub fn getFlagsRzAck(f: *anyopaque) bool {
        return getBitfield(f, flags_rz_ack_byte, flags_rz_ack_mask);
    }
    pub fn getFlagsReleasePending(f: *anyopaque) bool {
        return getBitfield(f, flags_release_pending_byte, flags_release_pending_mask);
    }
    pub fn setFlagsReleasePending(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_release_pending_byte, flags_release_pending_mask, v);
    }
    pub fn getFlagsBlockHdrMeta(f: *anyopaque) bool {
        return getBitfield(f, flags_block_hdr_meta_byte, flags_block_hdr_meta_mask);
    }

    pub fn getVid(f: *anyopaque) i64 {
        return readField(i64, f, o_vid);
    }
    pub fn getTag(f: *anyopaque) isize {
        return readField(isize, f, o_tag);
    }
    pub fn setTag(f: *anyopaque, v: isize) void {
        writeField(isize, f, o_tag, v);
    }
    pub fn getFused(f: *anyopaque) bool {
        return readField(bool, f, o_fused);
    }
    pub fn setFused(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_fused, v);
    }
    pub fn getFuseBlown(f: *anyopaque) bool {
        return readField(bool, f, o_fuse_blown);
    }
    pub fn getDevicemask(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_devicemask);
    }
    pub fn setDevicemask(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_devicemask, v);
    }
    pub fn getDatamask(f: *anyopaque) c_uint {
        return readField(c_uint, f, o_datamask);
    }
    pub fn setDatamask(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_datamask, v);
    }
    pub fn getGuidSlice(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_guid);
    }
    pub fn getTitleSlice(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_title);
    }
    pub fn getOutqueuePtr(f: *anyopaque) *anyopaque {
        return @ptrCast(@alignCast(ptrAdd(f, o_outqueue)));
    }
    pub fn getVstreamDead(f: *anyopaque) bool {
        return readField(bool, f, o_vstream_dead);
    }
    pub fn setVstreamDead(f: *anyopaque, v: bool) void {
        writeField(bool, f, o_vstream_dead, v);
    }
    pub fn getVstreamIncomingUsed(f: *anyopaque) usize {
        return readField(usize, f, o_vstream_incoming_used);
    }
    pub fn setVstreamIncomingUsed(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_vstream_incoming_used, v);
    }
    pub fn getVstreamPendingUsed(f: *anyopaque) usize {
        return readField(usize, f, o_vstream_pending_used);
    }
    pub fn setVstreamPendingUsed(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_vstream_pending_used, v);
    }
    /// Get pointer to vstream.incoming[i] as byte slice
    pub fn getVstreamIncomingPlane(f: *anyopaque, i: usize) [*]u8 {
        return ptrAdd(f, o_vstream_incoming + i * sizeof_agp_buffer_plane);
    }
    /// Get pointer to vstream.pending[i] as byte slice
    pub fn getVstreamPendingPlane(f: *anyopaque, i: usize) [*]u8 {
        return ptrAdd(f, o_vstream_pending + i * sizeof_agp_buffer_plane);
    }
    /// Get pointer to start of vstream.incoming array
    pub fn getVstreamIncomingBase(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_vstream_incoming);
    }
    /// Get pointer to start of vstream.pending array
    pub fn getVstreamPendingBase(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_vstream_pending);
    }

    // flags.external/networked/sandboxed accessors
    pub fn getFlagsExternal(f: *anyopaque) bool {
        return getBitfield(f, flags_external_byte, flags_external_mask);
    }
    pub fn setFlagsExternal(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_external_byte, flags_external_mask, v);
    }
    pub fn orFlagsExternal(f: *anyopaque, v: bool) void {
        if (v) ptrAdd(f, flags_external_byte)[0] |= flags_external_mask;
    }
    pub fn getFlagsNetworked(f: *anyopaque) bool {
        return getBitfield(f, flags_networked_byte, flags_networked_mask);
    }
    pub fn setFlagsNetworked(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_networked_byte, flags_networked_mask, v);
    }
    pub fn getFlagsSandboxed(f: *anyopaque) bool {
        return getBitfield(f, flags_sandboxed_byte, flags_sandboxed_mask);
    }
    pub fn orFlagsSandboxed(f: *anyopaque, v: bool) void {
        if (v) ptrAdd(f, flags_sandboxed_byte)[0] |= flags_sandboxed_mask;
    }

    // fields added for posix/frameserver.zig port
    const o_source: usize = 680;
    const o_child: usize = 692;
    const o_max_w: usize = 696;
    const o_max_h: usize = 704;
    const o_sockmode: usize = 712;
    const o_sockaddr: usize = 720;
    const o_abuf_sz: usize = 2072;
    const o_shm_shmsize: usize = 2048;
    const o_lastpts: usize = 872;
    const o_launchedtime: usize = 880;
    const o_desc_bpp: usize = 24;
    const o_desc_aofs: usize = 260;
    const o_desc_apad: usize = 248;
    const o_ofs_audp: usize = 1400;
    // flags byte 756 continued
    const flags_pbo_mask: u8 = 0x02;
    const flags_gpu_auth_mask: u8 = 0x40;
    // flags byte 758
    const flags_wrapped_byte: usize = 758;
    const flags_wrapped_mask: u8 = 0x01;
    // flags.activated is an int at offset 760
    const o_flags_activated: usize = 760;

    pub fn getSource(f: *anyopaque) [*c]u8 {
        return readField([*c]u8, f, o_source);
    }
    pub fn setSource(f: *anyopaque, v: [*c]u8) void {
        writeField([*c]u8, f, o_source, v);
    }
    pub fn getChild(f: *anyopaque) c_int {
        return readField(c_int, f, o_child);
    }
    pub fn setChild(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_child, v);
    }
    pub fn getMaxW(f: *anyopaque) usize {
        return readField(usize, f, o_max_w);
    }
    pub fn getMaxH(f: *anyopaque) usize {
        return readField(usize, f, o_max_h);
    }
    pub fn getSockmode(f: *anyopaque) u32 {
        return readField(u32, f, o_sockmode);
    }
    pub fn setSockmode(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_sockmode, v);
    }
    pub fn getSockaddr(f: *anyopaque) [*c]u8 {
        return readField([*c]u8, f, o_sockaddr);
    }
    pub fn setSockaddr(f: *anyopaque, v: [*c]u8) void {
        writeField([*c]u8, f, o_sockaddr, v);
    }
    pub fn getSockkeyMut(f: *anyopaque) [*c]u8 {
        return readField([*c]u8, f, o_sockkey);
    }
    pub fn setSockkey(f: *anyopaque, v: [*c]u8) void {
        writeField([*c]u8, f, o_sockkey, v);
    }
    pub fn getAbufSz(f: *anyopaque) usize {
        return readField(usize, f, o_abuf_sz);
    }
    pub fn setAbufSz(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_abuf_sz, v);
    }
    pub fn getShmShmsize(f: *anyopaque) usize {
        return readField(usize, f, o_shm_shmsize);
    }
    pub fn setShmShmsize(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_shm_shmsize, v);
    }
    pub fn setShmPtr(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_shm_ptr, v);
    }
    pub fn setShmHandle(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_shm_handle, v);
    }
    pub fn getLastpts(f: *anyopaque) i64 {
        return readField(i64, f, o_lastpts);
    }
    pub fn setLastpts(f: *anyopaque, v: i64) void {
        writeField(i64, f, o_lastpts, v);
    }
    pub fn getLaunchedtime(f: *anyopaque) i64 {
        return readField(i64, f, o_launchedtime);
    }
    pub fn setLaunchedtime(f: *anyopaque, v: i64) void {
        writeField(i64, f, o_launchedtime, v);
    }
    pub fn getDescBpp(f: *anyopaque) u8 {
        return readField(u8, f, o_desc_bpp);
    }
    pub fn setDescBpp(f: *anyopaque, v: u8) void {
        writeField(u8, f, o_desc_bpp, v);
    }
    pub fn setDescWidth(f: *anyopaque, v: u16) void {
        writeField(u16, f, o_desc_width, v);
    }
    pub fn setDescHeight(f: *anyopaque, v: u16) void {
        writeField(u16, f, o_desc_height, v);
    }
    pub fn setDescRows(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_rows, v);
    }
    pub fn setDescCols(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_desc_cols, v);
    }
    pub fn setDescPendingHints(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_desc_pending_hints, v);
    }
    pub fn setDescSamplerate(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_desc_samplerate, v);
    }
    pub fn setDescChannels(f: *anyopaque, v: u8) void {
        writeField(u8, f, o_desc_channels, v);
    }
    pub fn setDescAproto(f: *anyopaque, v: c_uint) void {
        writeField(c_uint, f, o_desc_aproto, v);
    }
    pub fn getDescApad(f: *anyopaque) usize {
        return readField(usize, f, o_desc_apad);
    }
    /// Write the arcan_shmif_ofstbl (128 bytes) at desc.aofs
    pub fn getDescAofsPtr(f: *anyopaque) [*]u8 {
        return ptrAdd(f, o_desc_aofs);
    }
    /// Zero the desc.aext struct (40 bytes: 5 pointers + 1 u8 + padding)
    pub fn zeroDescAext(f: *anyopaque) void {
        @memset(ptrAdd(f, o_desc_aext_gamma)[0..48], 0);
    }
    pub fn setDescAextGamma(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_desc_aext_gamma, v);
    }
    pub fn setDescAextVr(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_desc_aext_vr, v);
    }
    pub fn setDescAextHdr(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_desc_aext_hdr, v);
    }
    pub fn setDescAextVenc(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_desc_aext_venc, v);
    }
    pub fn setVid(f: *anyopaque, v: i64) void {
        writeField(i64, f, o_vid, v);
    }
    pub fn setAbufCnt(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_abuf_cnt, v);
    }
    pub fn setVbufCnt(f: *anyopaque, v: usize) void {
        writeField(usize, f, o_vbuf_cnt, v);
    }
    pub fn setQueueMask(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_queue_mask, v);
    }
    pub fn setXferSat(f: *anyopaque, v: f32) void {
        writeField(f32, f, o_xfer_sat, v);
    }
    pub fn setWatchConst(f: *anyopaque, v: u16) void {
        writeField(u16, f, o_watch_const, v);
    }

    // dmabuf_vidp accessors (compositor-allocated DMA-BUF for zero-copy vidp)
    const o_dmabuf_vidp_fd: usize = 2216;
    const o_dmabuf_vidp_bo: usize = 2224;
    const o_dmabuf_vidp_map_data: usize = 2232;
    const o_dmabuf_vidp_map_ptr: usize = 2240;
    const o_dmabuf_vidp_stride: usize = 2248;
    const o_dmabuf_vidp_modifier_lo: usize = 2252;
    const o_dmabuf_vidp_modifier_hi: usize = 2256;
    const o_dmabuf_vidp_w: usize = 2260;
    const o_dmabuf_vidp_h: usize = 2264;
    const o_dmabuf_vidp_glid: usize = 2268;

    pub fn getDmabufVidpFd(f: *anyopaque) c_int {
        return readField(c_int, f, o_dmabuf_vidp_fd);
    }
    pub fn setDmabufVidpFd(f: *anyopaque, v: c_int) void {
        writeField(c_int, f, o_dmabuf_vidp_fd, v);
    }
    pub fn getDmabufVidpBo(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_dmabuf_vidp_bo);
    }
    pub fn setDmabufVidpBo(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_dmabuf_vidp_bo, v);
    }
    pub fn getDmabufVidpMapData(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_dmabuf_vidp_map_data);
    }
    pub fn setDmabufVidpMapData(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_dmabuf_vidp_map_data, v);
    }
    pub fn getDmabufVidpMapPtr(f: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, f, o_dmabuf_vidp_map_ptr);
    }
    pub fn setDmabufVidpMapPtr(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_dmabuf_vidp_map_ptr, v);
    }
    pub fn getDmabufVidpStride(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_stride);
    }
    pub fn setDmabufVidpStride(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_stride, v);
    }
    pub fn getDmabufVidpModLo(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_modifier_lo);
    }
    pub fn setDmabufVidpModLo(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_modifier_lo, v);
    }
    pub fn getDmabufVidpModHi(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_modifier_hi);
    }
    pub fn setDmabufVidpModHi(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_modifier_hi, v);
    }
    pub fn getDmabufVidpW(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_w);
    }
    pub fn setDmabufVidpW(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_w, v);
    }
    pub fn getDmabufVidpH(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_h);
    }
    pub fn setDmabufVidpH(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_h, v);
    }
    pub fn getDmabufVidpGlid(f: *anyopaque) u32 {
        return readField(u32, f, o_dmabuf_vidp_glid);
    }
    pub fn setDmabufVidpGlid(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_dmabuf_vidp_glid, v);
    }
    pub fn setCookie(f: *anyopaque, v: u32) void {
        writeField(u32, f, o_cookie, v);
    }
    pub fn setParentPtr(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_parent_ptr, v);
    }
    pub fn setShmExternal(f: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, f, o_shm_external, v);
    }
    pub fn getOfsAudp(f: *anyopaque) isize {
        return readField(isize, f, o_ofs_audp);
    }
    pub fn setOfsAudp(f: *anyopaque, v: isize) void {
        writeField(isize, f, o_ofs_audp, v);
    }
    /// Get pointer to the vbufs array (array of pointers)
    pub fn getVbufsPtr(f: *anyopaque) [*]?*anyopaque {
        return @ptrCast(@alignCast(ptrAdd(f, o_vbufs)));
    }
    /// Get pointer to the abufs array (array of pointers)
    pub fn getAbufsPtr(f: *anyopaque) [*]?*anyopaque {
        return @ptrCast(@alignCast(ptrAdd(f, o_abufs)));
    }
    pub fn getFlagsWrapped(f: *anyopaque) bool {
        return getBitfield(f, flags_wrapped_byte, flags_wrapped_mask);
    }
    pub fn setFlagsWrapped(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_wrapped_byte, flags_wrapped_mask, v);
    }
    pub fn setFlagsAlive(f: *anyopaque, v: bool) void {
        setBitfield(f, flags_alive_byte, flags_alive_mask, v);
    }
    pub fn setFlagsAutoclock(f: *anyopaque, v: bool) void {
        setBitfield(f, o_flags, autoclock_mask, v);
    }
    pub fn getFlagsGpuAuth(f: *anyopaque) bool {
        return getBitfield(f, o_flags, flags_gpu_auth_mask);
    }
    pub fn getFlagsActivated(f: *anyopaque) c_int {
        return readField(c_int, f, o_flags_activated);
    }
};

// arcan_evctx

pub const Evctx = struct {
    const o_eventbuf_sz: usize = 24;
    const o_eventbuf: usize = 32;
    const o_front: usize = 40;
    const o_back: usize = 48;
    const o_local: usize = 56;
    const o_synch_killswitch: usize = 64;
    const o_synch_handle: usize = 72;
    const o_synch_synch: usize = 80;
    const o_synch_clearval: usize = 88;

    pub fn getEventbufSz(ctx: *anyopaque) u8 {
        return readField(u8, ctx, o_eventbuf_sz);
    }
    pub fn setEventbufSz(ctx: *anyopaque, v: u8) void {
        writeField(u8, ctx, o_eventbuf_sz, v);
    }
    pub fn getEventbuf(ctx: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ctx, o_eventbuf);
    }
    pub fn setEventbuf(ctx: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, ctx, o_eventbuf, v);
    }
    pub fn getFront(ctx: *anyopaque) ?*volatile u8 {
        return readField(?*volatile u8, ctx, o_front);
    }
    pub fn setFront(ctx: *anyopaque, v: ?*volatile u8) void {
        writeField(?*volatile u8, ctx, o_front, v);
    }
    pub fn getBack(ctx: *anyopaque) ?*volatile u8 {
        return readField(?*volatile u8, ctx, o_back);
    }
    pub fn setBack(ctx: *anyopaque, v: ?*volatile u8) void {
        writeField(?*volatile u8, ctx, o_back, v);
    }
    pub fn getLocal(ctx: *anyopaque) bool {
        return readField(bool, ctx, o_local);
    }
    pub fn setLocal(ctx: *anyopaque, v: bool) void {
        writeField(bool, ctx, o_local, v);
    }
    pub fn getSynchKillswitch(ctx: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ctx, o_synch_killswitch);
    }
    pub fn setSynchKillswitch(ctx: *anyopaque, v: ?*anyopaque) void {
        writeField(?*anyopaque, ctx, o_synch_killswitch, v);
    }
    pub fn getSynchSynch(ctx: *anyopaque) ?*anyopaque {
        return readField(?*anyopaque, ctx, o_synch_synch);
    }
};

// arcan_shmif_ramp

pub const Ramp = struct {
    const o_magic: usize = 0;
    const o_dirty_in: usize = 4;
    const o_dirty_out: usize = 5;
    const o_n_blocks: usize = 6;
    const o_ramps: usize = 8;
    pub const sizeof_ramp_block: usize = 16568;

    pub fn getMagic(r: *anyopaque) u32 {
        return readField(u32, r, o_magic);
    }
    pub fn getNBlocks(r: *anyopaque) u8 {
        return readField(u8, r, o_n_blocks);
    }
    pub fn getDirtyInPtr(r: *anyopaque) *u8 {
        return fieldPtr(u8, r, o_dirty_in);
    }
    pub fn getDirtyOutPtr(r: *anyopaque) *u8 {
        return fieldPtr(u8, r, o_dirty_out);
    }
    /// Get a byte pointer to the ramp_block at index ind
    pub fn getBlockPtr(r: *anyopaque, ind: usize) [*]u8 {
        return ptrAdd(r, o_ramps + ind * sizeof_ramp_block);
    }
};

// arcan_shmif_cont

pub const Cont = struct {
    const o_vidp: usize = 8;
    const o_w: usize = 80;
    const o_h: usize = 88;
    const o_pitch: usize = 104;
    const o_stride: usize = 96;

    pub fn getVidp(cont: *anyopaque) [*]u32 {
        const ptr = readField(?*anyopaque, cont, o_vidp) orelse unreachable;
        return @ptrCast(@alignCast(ptr));
    }
    pub fn getW(cont: *anyopaque) usize {
        return readField(usize, cont, o_w);
    }
    pub fn getH(cont: *anyopaque) usize {
        return readField(usize, cont, o_h);
    }
    pub fn getPitch(cont: *anyopaque) usize {
        return readField(usize, cont, o_pitch);
    }
};
