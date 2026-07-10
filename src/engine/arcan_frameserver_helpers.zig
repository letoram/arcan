// Pure Zig port of engine/arcan_frameserver_helpers.c — preamble chunk.
//
// Byte-offset accessors for arcan_frameserver and related opaque structs.
// Replaces the C accessor helpers with direct byte-offset arithmetic,
// following the same pattern as shmif_offsets.zig.
//
// Offsets from OFFSETS.md, computed for Linux aarch64 (Asahi/Fedora).
// _Atomic fields use @atomicLoad/@atomicStore; bitfield bools use byte masks.

const std = @import("std");

// arcan_frameserver offsets
const sz_arcan_frameserver: usize = 2280;
const o_desc: usize = 0; // arcan_frameserver_meta, 480 bytes
const o_inqueue: usize = 480; // arcan_evctx, 96 bytes
const o_outqueue: usize = 576; // arcan_evctx, 96 bytes
const o_queue_mask: usize = 672; // c_int
const o_source: usize = 680; // *u8
const o_dpipe: usize = 688; // c_int
const o_child: usize = 692; // pid_t (4 bytes)
const o_max_w: usize = 696; // usize
const o_max_h: usize = 704; // usize
const o_sockmode: usize = 712; // mode_t (4 bytes)
const o_sockaddr: usize = 720; // *u8
const o_sockkey: usize = 728; // *u8
const o_metamask: usize = 736; // c_uint
const o_devicemask: usize = 740; // c_uint
const o_datamask: usize = 744; // c_uint
const o_xfer_sat: usize = 748; // f32
const o_fused: usize = 752; // bool
const o_fuse_blown: usize = 753; // bool
const o_audio_flush_pending: usize = 754; // bool
const o_flags: usize = 756; // bitfield struct, 8 bytes
const o_clock: usize = 768; // clock struct, 32 bytes
const o_alocks: usize = 800; // *arcan_aobj_id
const o_aid: usize = 808; // arcan_aobj_id (i32)
const o_vid: usize = 816; // arcan_vobj_id (i64)
const o_parent: usize = 824; // parent struct, 16 bytes
const o_amixer: usize = 840; // amixer struct, 24 bytes
const o_playstate: usize = 864; // c_uint (enum)
const o_lastpts: usize = 872; // i64
const o_launchedtime: usize = 880; // i64
const o_vfcount: usize = 888; // c_uint
const o_cookie: usize = 892; // u32
const o_cookie_fail: usize = 896; // bool
const o_vstream: usize = 904; // vstream struct, 480 bytes
const o_sz_audb: usize = 1384; // usize
const o_ofs_audb: usize = 1392; // off_t (i64)
const o_ofs_audp: usize = 1400; // off_t (i64)
const o_audb: usize = 1408; // *u8
const o_n_pending: usize = 1416; // usize
const o_pending_queue: usize = 1424; // [4]arcan_event, 512 bytes
const o_title: usize = 1936; // [64]u8
const o_segid: usize = 2000; // c_uint (enum)
const o_guid: usize = 2008; // [2]u64
const o_tag: usize = 2024; // isize (intptr_t)
const o_shm: usize = 2032; // shm_handle struct, 24 bytes
const o_shm_external: usize = 2056; // ?*anyopaque
const o_abuf_cnt: usize = 2064; // usize
const o_abuf_sz: usize = 2072; // usize
const o_vbuf_cnt: usize = 2080; // usize
const o_rz_known: usize = 2088; // c_int
const o_vbufs: usize = 2096; // [3]*shmif_pixel, 24 bytes
const o_abufs: usize = 2120; // [12]*shmif_asample, 96 bytes
// dmabuf_vidp struct offsets (compositor-allocated DMA-BUF for zero-copy vidp)
const o_dmabuf_vidp_fd: usize = 2216; // c_int
const o_dmabuf_vidp_bo: usize = 2224; // *anyopaque
const o_dmabuf_vidp_map_data: usize = 2232; // *anyopaque
const o_dmabuf_vidp_map_ptr: usize = 2240; // *anyopaque
const o_dmabuf_vidp_stride: usize = 2248; // u32
const o_dmabuf_vidp_modifier_lo: usize = 2252; // u32
const o_dmabuf_vidp_modifier_hi: usize = 2256; // u32
const o_dmabuf_vidp_w: usize = 2260; // u32
const o_dmabuf_vidp_h: usize = 2264; // u32
const o_dmabuf_vidp_glid: usize = 2268; // u32
const o_watch_const: usize = 2272; // u16

// desc (arcan_frameserver_meta) offsets
// All relative to start of arcan_frameserver (desc is at offset 0).
const d_width: usize = 0; // u16
const d_height: usize = 2; // u16
const d_rows: usize = 8; // usize
const d_cols: usize = 16; // usize
const d_bpp: usize = 24; // i8
const d_hints: usize = 28; // c_int
const d_pending_hints: usize = 32; // c_int
const d_rz_flag: usize = 36; // bool
const d_region_x1: usize = 38; // i16
const d_region_x2: usize = 40; // i16
const d_region_y1: usize = 42; // i16
const d_region_y2: usize = 44; // i16
const d_region_valid: usize = 46; // bool
const d_text_group: usize = 48; // ?*anyopaque
const d_text_hint: usize = 56; // c_int
const d_text_szmm: usize = 60; // f32
const d_text_cellw: usize = 64; // usize
const d_text_cellh: usize = 72; // usize
const d_hint_last: usize = 80; // arcan_event, 128 bytes
const d_hint_width: usize = 208; // usize
const d_hint_height: usize = 216; // usize
const d_hint_ppcm: usize = 224; // f32
const d_synch_ts: usize = 232; // u32
const d_samplerate: usize = 236; // c_uint
const d_channels: usize = 240; // u8
const d_vfthresh: usize = 242; // u16
const d_apad: usize = 248; // usize
const d_aproto: usize = 256; // c_uint
const d_aofs: usize = 260; // arcan_shmif_ofstbl, 128 bytes
const d_aext_gamma: usize = 392; // ?*anyopaque
const d_aext_vr: usize = 400; // ?*anyopaque
const d_aext_vector: usize = 408; // ?*anyopaque
const d_aext_hdr: usize = 416; // ?*anyopaque
const d_aext_venc: usize = 424; // ?*anyopaque
const d_aext_gamma_map: usize = 432; // u8
const d_callback_framestate: usize = 440; // bool
const d_framecount: usize = 448; // u64
const d_dropcount: usize = 456; // u64
const d_lastpts_desc: usize = 464; // u64 (not the same as fsrv.lastpts)
const d_recovery_tick: usize = 472; // c_uint

// flags bitfield (8 bytes at offset 756)

// Byte 0 (offset 756)
const fl_byte_alive: usize = 756;
const fl_mask_alive: u8 = 0x01;
const fl_byte_pbo: usize = 756;
const fl_mask_pbo: u8 = 0x02;
const fl_byte_explicit: usize = 756;
const fl_mask_explicit: u8 = 0x04;
const fl_byte_local_copy: usize = 756;
const fl_mask_local_copy: u8 = 0x08;
const fl_byte_no_alpha_copy: usize = 756;
const fl_mask_no_alpha_copy: u8 = 0x10;
const fl_byte_autoclock: usize = 756;
const fl_mask_autoclock: u8 = 0x20;
const fl_byte_gpu_auth: usize = 756;
const fl_mask_gpu_auth: u8 = 0x40;
const fl_byte_no_dms_free: usize = 756;
const fl_mask_no_dms_free: u8 = 0x80;

// Byte 1 (offset 757)
const fl_byte_rz_ack: usize = 757;
const fl_mask_rz_ack: u8 = 0x01;
const fl_byte_locked: usize = 757;
const fl_mask_locked: u8 = 0x02;
const fl_byte_release_pending: usize = 757;
const fl_mask_release_pending: u8 = 0x04;
const fl_byte_no_adopt: usize = 757;
const fl_mask_no_adopt: u8 = 0x08;
const fl_byte_block_hdr_meta: usize = 757;
const fl_mask_block_hdr_meta: u8 = 0x10;
const fl_byte_external: usize = 757;
const fl_mask_external: u8 = 0x20;
const fl_byte_networked: usize = 757;
const fl_mask_networked: u8 = 0x40;
const fl_byte_sandboxed: usize = 757;
const fl_mask_sandboxed: u8 = 0x80;

// Byte 2 (offset 758)
const fl_byte_wrapped: usize = 758;
const fl_mask_wrapped: u8 = 0x01;

// Bytes 4-7 (offset 760) — activated (i32)
const fl_activated: usize = 760;

// clock sub-struct offsets (absolute)
const clk_left: usize = 768; // u32
const clk_start: usize = 772; // u32
const clk_frametime: usize = 776; // i64
const clk_id: usize = 784; // u32
const clk_present: usize = 788; // u32
const clk_last_msc: usize = 792; // u32
const clk_msc_feedback: usize = 796; // bool
const clk_frame: usize = 797; // bool
const clk_once: usize = 798; // bool
const clk_vblank: usize = 799; // bool

// parent sub-struct offsets (absolute)
const par_ptr: usize = 824; // ?*anyopaque
const par_vid: usize = 832; // arcan_vobj_id (i64)

// amixer sub-struct offsets (absolute)
const amx_n_aids: usize = 840; // c_uint
const amx_max_bufsz: usize = 848; // usize
const amx_inaud: usize = 856; // ?*frameserver_audsrc

// shm_handle sub-struct offsets (absolute)
const shm_ptr: usize = 2032; // ?*arcan_shmif_page
const shm_handle: usize = 2040; // c_int
const shm_shmsize: usize = 2048; // usize

// arcan_shmif_page offsets
const pg_resized: usize = 2; // i8 (volatile)
const pg_dms: usize = 3; // u8 (volatile)
const pg_aready: usize = 4; // u32 (atomic)
const pg_apending: usize = 8; // u32 (atomic)
const pg_vready: usize = 12; // u32 (atomic)
const pg_vpending: usize = 16; // u32 (atomic)
const pg_async: usize = 24; // u32 (atomic, FUTEX)
const pg_vsync: usize = 32; // u32 (atomic, FUTEX)
const pg_esync: usize = 40; // u32 (FUTEX)
const pg_abufused: usize = 44; // [12]u16 (atomic)
const pg_hints: usize = 68; // u8 (atomic)
const pg_dirty: usize = 72; // arcan_shmif_region (atomic, 8 bytes)
const pg_segment_token: usize = 84; // u32
const pg_cookie: usize = 88; // u64
const pg_w: usize = 32628; // u16 (atomic)
const pg_h: usize = 32630; // u16 (atomic)
const pg_vpts: usize = 32648; // u64 (atomic)

// arcan_vobject offsets
const vo_frameset: usize = 16; // ?*anyopaque
const vo_vstore: usize = 24; // ?*agp_vstore
const vo_origw: usize = 36; // u16
const vo_origh: usize = 38; // u16
const vo_feed_ffunc: usize = 56; // c_int (enum)
const vo_feed_state_tag: usize = 64; // c_int (volatile)
const vo_feed_state_ptr: usize = 72; // ?*anyopaque
const vo_current: usize = 104; // surface_properties
const vo_owner: usize = 368; // ?*rendertarget

// agp_vstore offsets
const vs_refcount: usize = 0; // c_int
const vs_update_ts: usize = 8; // usize
const vs_vinf_text_s_raw: usize = 40; // usize
const vs_vinf_text_raw: usize = 48; // ?*u8
const vs_vinf_text_d_fmt: usize = 64; // c_int
const vs_vinf_text_vpts: usize = 80; // i64
const vs_vinf_text_tpack_tui: usize = 128; // ?*anyopaque
const vs_dst_copy: usize = 168; // ?*anyopaque
const vs_w: usize = 176; // usize
const vs_h: usize = 184; // usize
const vs_txmapped: usize = 193; // u8 (enum)
const vs_filtermode: usize = 198; // u8 (enum)
const vs_hdr_model: usize = 200; // c_int
const vs_hdr_drm: usize = 204; // c_int

// rendertarget offsets
const rt_msc: usize = 144; // u32
const rt_color: usize = 160; // ?*arcan_vobject
const rt_art: usize = 184; // ?*anyopaque (agp_rendertarget*)
const rt_hwreadback: usize = 212; // bool

// arcan_event offsets
const ev_category: usize = 120; // u8
const ev_fsrv_kind: usize = 0; // u32
const ev_fsrv_audio: usize = 8; // i32
const ev_fsrv_width: usize = 16; // usize
const ev_fsrv_height: usize = 24; // usize
const ev_fsrv_xofs: usize = 32; // usize
const ev_fsrv_yofs: usize = 40; // usize
const ev_fsrv_fmt_fl: usize = 48; // i8
const ev_fsrv_pts: usize = 56; // u64
const ev_fsrv_counter: usize = 64; // u64
const ev_fsrv_message: usize = 72; // [32]u8
const ev_fsrv_video: usize = 104; // i64
const ev_fsrv_otag: usize = 112; // isize
const ev_tgt_kind: usize = 0; // u32
const ev_tgt_ioevs0_iv: usize = 4; // i32
const ev_tgt_ioevs1_uiv: usize = 8; // u32
const ev_tgt_code: usize = 36; // c_int
const ev_tgt_message: usize = 40; // [78]u8

// frameserver_audsrc offsets
const fas_inbuf: usize = 0; // [4096]f32 (16384 bytes)
const fas_inofs: usize = 16384; // off_t (i64)
const fas_src_aid: usize = 16392; // arcan_aobj_id (i32)
const fas_l_gain: usize = 16396; // f32
const fas_r_gain: usize = 16400; // f32

// agp_buffer_plane offsets
const bp_fd: usize = 0; // c_int
const bp_fence: usize = 4; // c_int
const bp_w: usize = 8; // usize
const bp_h: usize = 16; // usize
const bp_gbm_format: usize = 24; // usize
const bp_gbm_stride: usize = 32; // usize
const bp_gbm_offset: usize = 40; // usize
const bp_gbm_mod_hi: usize = 48; // u32
const bp_gbm_mod_lo: usize = 52; // u32

// vstream sub-struct offsets (absolute)
const vst_dead: usize = 904; // bool
const vst_pending: usize = 912; // [4]agp_buffer_plane, 224 bytes
const vst_pending_used: usize = 1136; // usize
const vst_incoming: usize = 1144; // [4]agp_buffer_plane, 224 bytes
const vst_incoming_used: usize = 1368; // usize
const vst_skip: usize = 1376; // usize

// sizeof reference
const sz_arcan_frameserver_meta: usize = 480;
const sz_arcan_evctx: usize = 96;
const sz_arcan_event: usize = 128;
const sz_arcan_vobject: usize = 416;
const sz_agp_vstore: usize = 256;
const sz_rendertarget: usize = 288;
const sz_arcan_shmif_page: usize = 32704;
const sz_arcan_shmif_cont: usize = 192;
const sz_arcan_shmif_region: usize = 8;
const sz_arcan_shmif_ofstbl: usize = 128;
const sz_agp_buffer_plane: usize = 56;
const sz_frameserver_audsrc: usize = 16408;
const sz_vfunc_state: usize = 16;
const sz_jmp_buf: usize = 312;

// Name aliases (chunks 2-7 use different names for chunk 1 offsets)
const o_clock_left: usize = clk_left;
const o_clock_start: usize = clk_start;
const o_clock_frametime: usize = clk_frametime;
const o_clock_id: usize = clk_id;
const o_clock_present: usize = clk_present;
const o_clock_last_msc: usize = clk_last_msc;
const o_clock_msc_feedback: usize = clk_msc_feedback;
const o_clock_frame: usize = clk_frame;
const o_clock_once: usize = clk_once;
const o_clock_vblank: usize = clk_vblank;
const o_parent_ptr: usize = par_ptr;
const o_parent_vid: usize = par_vid;
const o_amixer_n_aids: usize = amx_n_aids;
const o_amixer_inaud: usize = amx_inaud;
const o_amixer_max_bufsz: usize = amx_max_bufsz;
const o_shm_ptr: usize = shm_ptr;
const o_vstream_dead: usize = vst_dead;
const o_vstream_pending: usize = vst_pending;
const o_vstream_pending_used: usize = vst_pending_used;
const o_vstream_incoming: usize = vst_incoming;
const o_vstream_incoming_used: usize = vst_incoming_used;
const o_vstream_skip: usize = vst_skip;
// activated flag at offset 760 (within flags struct)
const fl_off_activated: usize = fl_activated - o_flags;

// Constants

// Event kinds
const EVENT_FSRV: u8 = 32;
const EVENT_TARGET: u8 = 16;
const EVENT_FSRV_EXTCONN: u32 = 0;
const EVENT_FSRV_RESIZED: u32 = 1;
const EVENT_FSRV_TERMINATED: u32 = 2;
const EVENT_FSRV_DROPPEDFRAME: u32 = 3;
const EVENT_FSRV_DELIVEREDFRAME: u32 = 4;
const EVENT_FSRV_APROTO: u32 = 6;
const EVENT_FSRV_GAMMARAMP: u32 = 7;
const TARGET_COMMAND_EXIT: u32 = 1;
const TARGET_COMMAND_STEPFRAME: u32 = 3;
const TARGET_COMMAND_RESET: u32 = 9;
const TARGET_COMMAND_BUFFER_FAIL: u32 = 21;
const TARGET_COMMAND_DEVICE_NODE: u32 = 22;

// Error codes
const ARCAN_OK: c_int = 0;
const ARCAN_ERRC_UNACCEPTED_STATE: c_int = -4;
const ARCAN_ERRC_OUT_OF_SPACE: c_int = -6;
const ARCAN_ERRC_NO_SUCH_OBJECT: c_int = -7;
const ARCAN_ERRC_BAD_RESOURCE: c_int = -8;
const ARCAN_ERRC_NOTREADY: c_int = -10;

// Play states
const ARCAN_PASSIVE: c_int = 0;
const ARCAN_BUFFERING: c_int = 1;
const ARCAN_PLAYING: c_int = 2;
const ARCAN_PAUSED: c_int = 3;

// FFuncs (enum arcan_ffunc)
const FFUNC_FATAL: c_int = 0;
const FFUNC_NULL: c_int = 1;
const FFUNC_AVFEED: c_int = 2;
const FFUNC_NULLFEED: c_int = 3;
const FFUNC_FEEDCOPY: c_int = 4;
const FFUNC_VFRAME_ENUM: c_int = 5;
const FFUNC_NULLFRAME: c_int = 6;
const FFUNC_WRAPPED: c_int = 7;
const FFUNC_LUA_PROC: c_int = 8;
const FFUNC_3DOBJ: c_int = 9;
const FFUNC_LWA: c_int = 10;
const FFUNC_VR: c_int = 11;
const FFUNC_SOCKVER: c_int = 12;
const FFUNC_SOCKPOLL: c_int = 13;

// FFfunc commands
const arcan_ffunc_rv = c_int;
const FRV_NOFRAME: arcan_ffunc_rv = 0;
const FRV_GOTFRAME: arcan_ffunc_rv = 1;

const arcan_ffunc_cmd = c_int;
const FFUNC_CMD_POLL: arcan_ffunc_cmd = 0;
const FFUNC_CMD_RENDER: arcan_ffunc_cmd = 1;
const FFUNC_CMD_TICK: arcan_ffunc_cmd = 2;
const FFUNC_CMD_DESTROY: arcan_ffunc_cmd = 3;
const FFUNC_CMD_READBACK: arcan_ffunc_cmd = 4;
const FFUNC_CMD_READBACK_HANDLE: arcan_ffunc_cmd = 5;
const FFUNC_CMD_ADOPT: arcan_ffunc_cmd = 6;

// Misc constants
const ARCAN_EID: arcan_vobj_id = 0;
const ARCAN_TAG_FRAMESERV: c_int = 3;
const SHMIF_RHINT_VSIGNAL_EV: c_int = 32;
const FSRV_MAX_VBUFC: usize = 3;
const FSRV_MAX_ABUFC: usize = 12;
const ARCAN_SHMIF_SAMPLERATE: c_uint = 48000;
const SHMIF_CMRAMP_PLIM: usize = 4;
const SHMIF_CMRAMP_UPLIM: usize = 4095;
const SEGID_UNKNOWN: c_uint = 0;
const SEGID_ENCODER: c_uint = 7;

// Memory allocation
const ARCAN_MEM_VBUFFER: c_int = 1;
const ARCAN_MEM_TEMPORARY: c_int = 2;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEMALIGN_PAGE: c_int = 1;

// Sync flags
const SYNC_EVENT: c_int = 1;
const SYNC_AUDIO: c_int = 2;
const SYNC_VIDEO: c_int = 4;

// Generic helpers

fn ptrAdd(base: *anyopaque, off: usize) [*]u8 {
    return @as([*]u8, @ptrCast(base)) + off;
}

fn fieldPtr(comptime T: type, base: *anyopaque, off: usize) *T {
    return @ptrCast(@alignCast(ptrAdd(base, off)));
}

fn readField(comptime T: type, base: *anyopaque, off: usize) T {
    return fieldPtr(T, base, off).*;
}

fn writeField(comptime T: type, base: *anyopaque, off: usize, val: T) void {
    fieldPtr(T, base, off).* = val;
}

fn getBitfield(base: *anyopaque, byte_off: usize, mask: u8) bool {
    return (ptrAdd(base, byte_off)[0] & mask) != 0;
}

fn setBitfield(base: *anyopaque, byte_off: usize, mask: u8, val: bool) void {
    if (val) {
        ptrAdd(base, byte_off)[0] |= mask;
    } else {
        ptrAdd(base, byte_off)[0] &= ~mask;
    }
}

fn atomicLoad32(base: *anyopaque, off: usize) u32 {
    return @atomicLoad(u32, fieldPtr(u32, base, off), .seq_cst);
}

fn atomicStore32(base: *anyopaque, off: usize, val: u32) void {
    @atomicStore(u32, fieldPtr(u32, base, off), val, .seq_cst);
}

fn atomicFetchAnd32(base: *anyopaque, off: usize, mask: u32) u32 {
    return @atomicRmw(u32, fieldPtr(u32, base, off), .And, mask, .seq_cst);
}

// Generic atomic helpers (for chunk 6 code that uses typed atomics)
fn atomicLoad(comptime T: type, base: anytype, off: usize) T {
    const raw: [*]u8 = ptrAdd(@as(*anyopaque, @ptrCast(@constCast(base))), off);
    const ptr: *const T = @ptrCast(@alignCast(raw));
    return @atomicLoad(T, ptr, .seq_cst);
}

fn atomicStore(comptime T: type, base: anytype, off: usize, val: T) void {
    const raw: [*]u8 = ptrAdd(@as(*anyopaque, @ptrCast(@constCast(base))), off);
    const ptr: *T = @ptrCast(@alignCast(raw));
    @atomicStore(T, ptr, val, .seq_cst);
}

fn atomicFetchAnd(comptime T: type, base: anytype, off: usize, mask: T) T {
    const raw: [*]u8 = ptrAdd(@as(*anyopaque, @ptrCast(@constCast(base))), off);
    const ptr: *T = @ptrCast(@alignCast(raw));
    return @atomicRmw(T, ptr, .And, mask, .seq_cst);
}

// Type aliases

const arcan_errc = c_int;
const arcan_vobj_id = i64;
const arcan_aobj_id = i32;
const av_pixel = u32;

const arcan_frameserver = anyopaque;
const arcan_evctx = anyopaque;

const vfunc_state = extern struct {
    tag: c_int,
    ptr: ?*anyopaque,
};

// Engine/platform extern fn declarations

extern fn arcan_event_defaultctx() ?*arcan_evctx;
extern fn arcan_event_enqueue(ctx: ?*arcan_evctx, ev: ?*const anyopaque) arcan_errc;
extern fn arcan_event_queuetransfer(dstqueue: ?*arcan_evctx, srcqueue: ?*arcan_evctx, allowed: c_int, sat: f32, tgt: ?*anyopaque) c_int;
extern fn arcan_audio_hookfeed(aid: arcan_aobj_id, cb: ?*anyopaque, tag: ?*anyopaque, tag2: ?*anyopaque) void;
extern fn arcan_audio_rebuild(aid: arcan_aobj_id) void;
extern fn arcan_audio_stop(aid: arcan_aobj_id) void;
extern fn arcan_audio_feed(cb: ?*const anyopaque, tag: ?*anyopaque, errc: ?*arcan_errc) arcan_aobj_id;
extern fn arcan_audio_buffer(aobj: ?*anyopaque, buffer: c_uint, buf: ?*anyopaque, sz: u32, channels: u8, samplerate: c_uint, tag: ?*anyopaque) void;
extern fn arcan_aid_refresh(aid: arcan_aobj_id) void;
extern fn arcan_conductor_deregister_frameserver(fsrv: ?*anyopaque) void;
extern fn arcan_renderfun_release_fontgroup(group: ?*anyopaque) void;
extern fn arcan_renderfun_fontgroup(fds: ?*anyopaque, n: c_int) ?*anyopaque;
extern fn arcan_renderfun_fontgroup_replace(group: ?*anyopaque, slot: c_int, fd: c_int) void;
extern fn arcan_renderfun_fontgroup_size(group: ?*anyopaque, szmm: f32, ppcm: f32, cellw: *usize, cellh: *usize) void;
extern fn arcan_video_fontdefaults(fd: ?*c_int, pt_sz: ?*c_int, hint: ?*c_int) void;
extern fn arcan_video_alterfeed(vid: arcan_vobj_id, ffunc: c_int, state: vfunc_state) arcan_errc;
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*anyopaque;
extern fn arcan_video_feedstate(vid: arcan_vobj_id) ?*vfunc_state;
extern fn arcan_video_findstate(tag: c_int, ptr: ?*anyopaque) arcan_vobj_id;
extern fn arcan_video_resizefeed(vid: arcan_vobj_id, w: u16, h: u16) void;
extern fn platform_fsrv_pushevent(fsrv: ?*anyopaque, ev: ?*const anyopaque) arcan_errc;
extern fn platform_fsrv_validchild(fsrv: ?*anyopaque) bool;
extern fn platform_fsrv_destroy(fsrv: ?*anyopaque) bool;
extern fn platform_fsrv_lastwords(fsrv: ?*anyopaque, msg: [*]u8, sz: usize) bool;
extern fn platform_fsrv_resynch(fsrv: ?*anyopaque) c_int;
extern fn platform_fsrv_signal(fsrv: ?*anyopaque, fl: c_int) void;
extern fn platform_fsrv_socketpoll(fsrv: ?*anyopaque) c_int;
extern fn platform_fsrv_socketauth(fsrv: ?*anyopaque) c_int;
extern fn platform_video_displays(arr: ?*anyopaque, lim: *usize) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_vint_findrt(vobj: *anyopaque) ?*anyopaque;
extern fn platform_fsrv_pushfd(fsrv: ?*anyopaque, ev: *anyopaque, fd: c_int) c_int;
extern fn agp_rendertarget_swap(art: *anyopaque, swap: *bool) ?*anyopaque;
extern fn platform_video_export_vstore(vs: *anyopaque, planes: ?*anyopaque, count: usize) usize;
extern fn arcan_shmif_cookie() u32;
extern fn arcan_shmif_poll(ctx: ?*anyopaque, ev: ?*anyopaque) c_int;
extern fn arcan_frametime() i64;
extern fn arcan_timemillis() u64;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_find_resource(name: [*c]const u8, ns: c_int, rtype: c_int, outfd: ?*c_int) [*c]u8;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn platform_fsrv_enter(fsrv: ?*anyopaque, tramp: ?*anyopaque) void;
extern fn platform_fsrv_leave() void;
extern fn close(fd: c_int) c_int;
extern fn memmove(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn memset(dst: ?*anyopaque, val: c_int, n: usize) ?*anyopaque;

// Static state

var g_buffers_locked: c_int = 0;

// TRAMP_GUARD wrappers

const builtin_fsrv = @import("builtin");
const is_freestanding_fsrv = (builtin_fsrv.os.tag == .freestanding);

const c_setjmp = if (is_freestanding_fsrv) struct {
    const jmp_buf = [312]u8;
    fn _setjmp(_: *jmp_buf) c_int { return 0; }
} else @import("posix");

export fn fsrv_helper_tramp_enter(fsrv: ?*anyopaque) bool {
    if (is_freestanding_fsrv) return false;
    var tramp: c_setjmp.jmp_buf = undefined;
    if (c_setjmp._setjmp(&tramp) != 0) return false;
    platform_fsrv_enter(fsrv, &tramp);
    return true;
}

export fn fsrv_helper_tramp_leave() void {
    platform_fsrv_leave();
}

// Basic field accessor exports (C lines 79-108)

export fn fsrv_helper_get_vid(f: ?*anyopaque) arcan_vobj_id {
    return readField(arcan_vobj_id, f.?, o_vid);
}

export fn fsrv_helper_set_vid(f: ?*anyopaque, v: arcan_vobj_id) void {
    writeField(arcan_vobj_id, f.?, o_vid, v);
}

export fn fsrv_helper_get_tag(f: ?*anyopaque) isize {
    return readField(isize, f.?, o_tag);
}

export fn fsrv_helper_set_tag(f: ?*anyopaque, v: isize) void {
    writeField(isize, f.?, o_tag, v);
}

export fn fsrv_helper_get_aid(f: ?*anyopaque) arcan_aobj_id {
    return readField(arcan_aobj_id, f.?, o_aid);
}

export fn fsrv_helper_set_aid(f: ?*anyopaque, v: arcan_aobj_id) void {
    writeField(arcan_aobj_id, f.?, o_aid, v);
}

export fn fsrv_helper_get_dpipe(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, o_dpipe);
}

export fn fsrv_helper_get_segid(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, o_segid);
}

export fn fsrv_helper_set_segid(f: ?*anyopaque, v: c_int) void {
    writeField(c_int, f.?, o_segid, v);
}

export fn fsrv_helper_get_title_buf(f: ?*anyopaque) [*c]u8 {
    return @ptrCast(ptrAdd(f.?, o_title));
}

export fn fsrv_helper_get_title_buf_len(f: ?*anyopaque) usize {
    _ = f;
    return 64;
}

export fn fsrv_helper_get_title(f: ?*anyopaque) [*c]const u8 {
    return @ptrCast(ptrAdd(f.?, o_title));
}

export fn fsrv_helper_get_guid(f: ?*anyopaque, idx: c_int) u64 {
    const off = o_guid + @as(usize, @intCast(idx)) * 8;
    return readField(u64, f.?, off);
}

export fn fsrv_helper_get_cookie(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_cookie);
}

export fn fsrv_helper_get_cookie_fail(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_cookie_fail);
}

export fn fsrv_helper_set_cookie_fail(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_cookie_fail, v);
}

export fn fsrv_helper_get_shmptr(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, shm_ptr);
}

export fn fsrv_helper_get_queue_mask(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, o_queue_mask);
}

export fn fsrv_helper_get_xfer_sat(f: ?*anyopaque) f32 {
    return readField(f32, f.?, o_xfer_sat);
}

export fn fsrv_helper_get_inqueue(f: ?*anyopaque) ?*anyopaque {
    return @ptrCast(ptrAdd(f.?, o_inqueue));
}

export fn fsrv_helper_get_outqueue(f: ?*anyopaque) ?*anyopaque {
    return @ptrCast(ptrAdd(f.?, o_outqueue));
}

export fn fsrv_helper_get_watch_const(f: ?*anyopaque) u16 {
    return readField(u16, f.?, o_watch_const);
}

export fn fsrv_helper_get_abuf_cnt(f: ?*anyopaque) c_int {
    return @intCast(readField(usize, f.?, o_abuf_cnt));
}

export fn fsrv_helper_get_vbuf_cnt(f: ?*anyopaque) c_int {
    return @intCast(readField(usize, f.?, o_vbuf_cnt));
}

export fn fsrv_helper_get_fused(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_fused);
}

export fn fsrv_helper_set_fused(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_fused, v);
}

export fn fsrv_helper_get_fuse_blown(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_fuse_blown);
}

export fn fsrv_helper_set_fuse_blown(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_fuse_blown, v);
}

export fn fsrv_helper_get_n_pending(f: ?*anyopaque) usize {
    return readField(usize, f.?, o_n_pending);
}

export fn fsrv_helper_set_n_pending(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, o_n_pending, v);
}

export fn fsrv_helper_get_rz_known(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, o_rz_known);
}

export fn fsrv_helper_set_rz_known(f: ?*anyopaque, v: c_int) void {
    writeField(c_int, f.?, o_rz_known, v);
}

export fn fsrv_helper_get_parent_vid(f: ?*anyopaque) arcan_vobj_id {
    return readField(arcan_vobj_id, f.?, par_vid);
}

export fn fsrv_helper_set_parent_vid(f: ?*anyopaque, v: arcan_vobj_id) void {
    writeField(arcan_vobj_id, f.?, par_vid, v);
}

export fn fsrv_helper_get_parent_ptr(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, par_ptr);
}

export fn fsrv_helper_get_sockkey(f: ?*anyopaque) [*c]const u8 {
    return readField([*c]const u8, f.?, o_sockkey);
}

export fn fsrv_helper_get_playstate(f: ?*anyopaque) c_int {
    return @intCast(readField(c_uint, f.?, o_playstate));
}

export fn fsrv_helper_set_playstate(f: ?*anyopaque, v: c_int) void {
    writeField(c_uint, f.?, o_playstate, @intCast(v));
}

export fn fsrv_helper_get_vfcount(f: ?*anyopaque) c_uint {
    return readField(c_uint, f.?, o_vfcount);
}

export fn fsrv_helper_inc_vfcount(f: ?*anyopaque) void {
    const ptr = fieldPtr(c_uint, f.?, o_vfcount);
    ptr.* += 1;
}

export fn fsrv_helper_get_sz_audb(f: ?*anyopaque) usize {
    return readField(usize, f.?, o_sz_audb);
}

export fn fsrv_helper_set_sz_audb(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, o_sz_audb, v);
}

export fn fsrv_helper_get_ofs_audb(f: ?*anyopaque) isize {
    return @intCast(readField(i64, f.?, o_ofs_audb));
}

export fn fsrv_helper_set_ofs_audb(f: ?*anyopaque, v: isize) void {
    writeField(i64, f.?, o_ofs_audb, @intCast(v));
}

export fn fsrv_helper_get_audb(f: ?*anyopaque) ?[*]u8 {
    return readField(?[*]u8, f.?, o_audb);
}

export fn fsrv_helper_set_audb(f: ?*anyopaque, v: ?[*]u8) void {
    writeField(?[*]u8, f.?, o_audb, v);
}

export fn fsrv_helper_get_alocks(f: ?*anyopaque) ?[*]arcan_aobj_id {
    return readField(?[*]arcan_aobj_id, f.?, o_alocks);
}

export fn fsrv_helper_set_alocks(f: ?*anyopaque, v: ?[*]arcan_aobj_id) void {
    writeField(?[*]arcan_aobj_id, f.?, o_alocks, v);
}

export fn fsrv_helper_get_audio_flush_pending(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_audio_flush_pending);
}

export fn fsrv_helper_set_audio_flush_pending(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_audio_flush_pending, v);
}

export fn fsrv_helper_get_amixer_n_aids(f: ?*anyopaque) c_int {
    return @intCast(readField(c_uint, f.?, amx_n_aids));
}
// Chunk 2: flags + clock + desc accessors

// Flags: bitfield accessors (flags struct at o_flags)

// -- get_flags_* / set_flags_* (original C lines 111-123) --

export fn fsrv_helper_get_flags_alive(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_alive, fl_mask_alive);
}
export fn fsrv_helper_get_flags_explicit(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_explicit, fl_mask_explicit);
}
export fn fsrv_helper_get_flags_local_copy(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_local_copy, fl_mask_local_copy);
}
export fn fsrv_helper_get_flags_no_alpha_copy(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_alpha_copy, fl_mask_no_alpha_copy);
}
export fn fsrv_helper_get_flags_autoclock(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_autoclock, fl_mask_autoclock);
}
export fn fsrv_helper_get_flags_rz_ack(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_rz_ack, fl_mask_rz_ack);
}
export fn fsrv_helper_get_flags_locked(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_locked, fl_mask_locked);
}
export fn fsrv_helper_get_flags_release_pending(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_release_pending, fl_mask_release_pending);
}
export fn fsrv_helper_set_flags_release_pending(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_release_pending, fl_mask_release_pending, v);
}
export fn fsrv_helper_get_flags_block_hdr_meta(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_block_hdr_meta, fl_mask_block_hdr_meta);
}
export fn fsrv_helper_get_no_dms_free(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_dms_free, fl_mask_no_dms_free);
}
export fn fsrv_helper_set_no_dms_free(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_no_dms_free, fl_mask_no_dms_free, v);
}
export fn fsrv_helper_get_no_adopt(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_adopt, fl_mask_no_adopt);
}

// -- get_flag_* (C lines 1854-1870) --

export fn fsrv_helper_get_flag_alive(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_alive, fl_mask_alive);
}
export fn fsrv_helper_get_flag_pbo(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_pbo, fl_mask_pbo);
}
export fn fsrv_helper_get_flag_explicit(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_explicit, fl_mask_explicit);
}
export fn fsrv_helper_get_flag_local_copy(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_local_copy, fl_mask_local_copy);
}
export fn fsrv_helper_get_flag_no_alpha_copy(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_alpha_copy, fl_mask_no_alpha_copy);
}
export fn fsrv_helper_get_flag_autoclock(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_autoclock, fl_mask_autoclock);
}
export fn fsrv_helper_get_flag_gpu_auth(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_gpu_auth, fl_mask_gpu_auth);
}
export fn fsrv_helper_get_flag_no_dms_free(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_dms_free, fl_mask_no_dms_free);
}
export fn fsrv_helper_get_flag_rz_ack(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_rz_ack, fl_mask_rz_ack);
}
export fn fsrv_helper_get_flag_locked(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_locked, fl_mask_locked);
}
export fn fsrv_helper_get_flag_release_pending(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_release_pending, fl_mask_release_pending);
}
export fn fsrv_helper_get_flag_no_adopt(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_no_adopt, fl_mask_no_adopt);
}
export fn fsrv_helper_get_flag_block_hdr_meta(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_block_hdr_meta, fl_mask_block_hdr_meta);
}
export fn fsrv_helper_get_flag_external(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_external, fl_mask_external);
}
export fn fsrv_helper_get_flag_networked(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_networked, fl_mask_networked);
}
export fn fsrv_helper_get_flag_sandboxed(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_sandboxed, fl_mask_sandboxed);
}
export fn fsrv_helper_get_flag_wrapped(f: ?*anyopaque) bool {
    return getBitfield(f.?, fl_byte_wrapped, fl_mask_wrapped);
}

// -- set_flag_* (C lines 1872-1888) --

export fn fsrv_helper_set_flag_alive(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_alive, fl_mask_alive, v);
}
export fn fsrv_helper_set_flag_pbo(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_pbo, fl_mask_pbo, v);
}
export fn fsrv_helper_set_flag_explicit(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_explicit, fl_mask_explicit, v);
}
export fn fsrv_helper_set_flag_local_copy(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_local_copy, fl_mask_local_copy, v);
}
export fn fsrv_helper_set_flag_no_alpha_copy(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_no_alpha_copy, fl_mask_no_alpha_copy, v);
}
export fn fsrv_helper_set_flag_autoclock(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_autoclock, fl_mask_autoclock, v);
}
export fn fsrv_helper_set_flag_gpu_auth(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_gpu_auth, fl_mask_gpu_auth, v);
}
export fn fsrv_helper_set_flag_no_dms_free(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_no_dms_free, fl_mask_no_dms_free, v);
}
export fn fsrv_helper_set_flag_rz_ack(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_rz_ack, fl_mask_rz_ack, v);
}
export fn fsrv_helper_set_flag_locked(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_locked, fl_mask_locked, v);
}
export fn fsrv_helper_set_flag_release_pending(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_release_pending, fl_mask_release_pending, v);
}
export fn fsrv_helper_set_flag_no_adopt(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_no_adopt, fl_mask_no_adopt, v);
}
export fn fsrv_helper_set_flag_block_hdr_meta(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_block_hdr_meta, fl_mask_block_hdr_meta, v);
}
export fn fsrv_helper_set_flag_external(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_external, fl_mask_external, v);
}
export fn fsrv_helper_set_flag_networked(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_networked, fl_mask_networked, v);
}
export fn fsrv_helper_set_flag_sandboxed(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_sandboxed, fl_mask_sandboxed, v);
}
export fn fsrv_helper_set_flag_wrapped(f: ?*anyopaque, v: bool) void {
    setBitfield(f.?, fl_byte_wrapped, fl_mask_wrapped, v);
}

// -- activated (i32 at flags + 4, i.e. offset 760) --

export fn fsrv_helper_get_activated(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, fl_activated);
}
export fn fsrv_helper_set_activated(f: ?*anyopaque, v: c_int) void {
    writeField(c_int, f.?, fl_activated, v);
}

// Clock accessors (clock struct at o_clock_*)

export fn fsrv_helper_get_clock_left(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_clock_left);
}
export fn fsrv_helper_set_clock_left(f: ?*anyopaque, v: u32) void {
    writeField(u32, f.?, o_clock_left, v);
}
export fn fsrv_helper_get_clock_start(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_clock_start);
}
export fn fsrv_helper_get_clock_frametime(f: ?*anyopaque) i64 {
    return readField(i64, f.?, o_clock_frametime);
}
export fn fsrv_helper_set_clock_frametime(f: ?*anyopaque, v: i64) void {
    writeField(i64, f.?, o_clock_frametime, v);
}
export fn fsrv_helper_get_clock_id(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_clock_id);
}
export fn fsrv_helper_get_clock_present(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_clock_present);
}
export fn fsrv_helper_set_clock_present(f: ?*anyopaque, v: u32) void {
    writeField(u32, f.?, o_clock_present, v);
}
export fn fsrv_helper_get_clock_last_msc(f: ?*anyopaque) u32 {
    return readField(u32, f.?, o_clock_last_msc);
}
export fn fsrv_helper_set_clock_last_msc(f: ?*anyopaque, v: u32) void {
    writeField(u32, f.?, o_clock_last_msc, v);
}
export fn fsrv_helper_get_clock_once(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_clock_once);
}
export fn fsrv_helper_get_clock_frame(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_clock_frame);
}
export fn fsrv_helper_get_clock_msc_feedback(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_clock_msc_feedback);
}
export fn fsrv_helper_set_clock_msc_feedback(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_clock_msc_feedback, v);
}

// Desc accessors (arcan_frameserver_meta, desc at offset 0)

export fn fsrv_helper_get_desc_width(f: ?*anyopaque) u16 {
    return readField(u16, f.?, d_width);
}
export fn fsrv_helper_get_desc_height(f: ?*anyopaque) u16 {
    return readField(u16, f.?, d_height);
}
export fn fsrv_helper_get_desc_rows(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_rows);
}
export fn fsrv_helper_get_desc_cols(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_cols);
}
export fn fsrv_helper_get_desc_hints(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, d_hints);
}
export fn fsrv_helper_set_desc_hints(f: ?*anyopaque, v: c_int) void {
    writeField(c_int, f.?, d_hints, v);
}
export fn fsrv_helper_get_desc_pending_hints(f: ?*anyopaque) c_int {
    return readField(c_int, f.?, d_pending_hints);
}
export fn fsrv_helper_get_desc_rz_flag(f: ?*anyopaque) bool {
    return readField(bool, f.?, d_rz_flag);
}
export fn fsrv_helper_set_desc_rz_flag(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, d_rz_flag, v);
}
export fn fsrv_helper_get_desc_region_valid(f: ?*anyopaque) bool {
    return readField(bool, f.?, d_region_valid);
}
export fn fsrv_helper_set_desc_region_valid(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, d_region_valid, v);
}
export fn fsrv_helper_get_desc_callback_framestate(f: ?*anyopaque) bool {
    return readField(bool, f.?, d_callback_framestate);
}
export fn fsrv_helper_get_desc_framecount(f: ?*anyopaque) u64 {
    return readField(u64, f.?, d_framecount);
}
export fn fsrv_helper_inc_desc_framecount(f: ?*anyopaque) void {
    const cur = readField(u64, f.?, d_framecount);
    writeField(u64, f.?, d_framecount, cur +% 1);
}
export fn fsrv_helper_get_desc_dropcount(f: ?*anyopaque) u64 {
    return readField(u64, f.?, d_dropcount);
}
export fn fsrv_helper_inc_desc_dropcount(f: ?*anyopaque) void {
    const cur = readField(u64, f.?, d_dropcount);
    writeField(u64, f.?, d_dropcount, cur +% 1);
}
export fn fsrv_helper_get_desc_synch_ts(f: ?*anyopaque) u32 {
    return readField(u32, f.?, d_synch_ts);
}
export fn fsrv_helper_set_desc_synch_ts(f: ?*anyopaque, v: u32) void {
    writeField(u32, f.?, d_synch_ts, v);
}
export fn fsrv_helper_get_desc_samplerate(f: ?*anyopaque) c_uint {
    return readField(c_uint, f.?, d_samplerate);
}
export fn fsrv_helper_get_desc_channels(f: ?*anyopaque) u8 {
    return readField(u8, f.?, d_channels);
}
export fn fsrv_helper_get_desc_aproto(f: ?*anyopaque) c_uint {
    return readField(c_uint, f.?, d_aproto);
}

// desc.region: read 4 i16 values (x1, x2, y1, y2 in memory order per OFFSETS.md)
export fn fsrv_helper_get_desc_region(
    f: ?*anyopaque,
    x1: *i16,
    y1: *i16,
    x2: *i16,
    y2: *i16,
) void {
    x1.* = readField(i16, f.?, d_region_x1);
    y1.* = readField(i16, f.?, d_region_y1);
    x2.* = readField(i16, f.?, d_region_x2);
    y2.* = readField(i16, f.?, d_region_y2);
}
export fn fsrv_helper_set_desc_region(
    f: ?*anyopaque,
    x1: i16,
    y1: i16,
    x2: i16,
    y2: i16,
) void {
    writeField(i16, f.?, d_region_x1, x1);
    writeField(i16, f.?, d_region_x2, x2);
    writeField(i16, f.?, d_region_y1, y1);
    writeField(i16, f.?, d_region_y2, y2);
}

// desc.text
export fn fsrv_helper_get_desc_text_group(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, d_text_group);
}
export fn fsrv_helper_set_desc_text_group(f: ?*anyopaque, g: ?*anyopaque) void {
    writeField(?*anyopaque, f.?, d_text_group, g);
}
export fn fsrv_helper_get_desc_text_cellw(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_text_cellw);
}
export fn fsrv_helper_get_desc_text_cellh(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_text_cellh);
}
export fn fsrv_helper_set_desc_text_cellw(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, d_text_cellw, v);
}
export fn fsrv_helper_set_desc_text_cellh(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, d_text_cellh, v);
}
export fn fsrv_helper_get_desc_text_szmm(f: ?*anyopaque) f32 {
    return readField(f32, f.?, d_text_szmm);
}
export fn fsrv_helper_set_desc_text_szmm(f: ?*anyopaque, v: f32) void {
    writeField(f32, f.?, d_text_szmm, v);
}

// desc.hint
export fn fsrv_helper_get_desc_hint_ppcm(f: ?*anyopaque) f32 {
    return readField(f32, f.?, d_hint_ppcm);
}
export fn fsrv_helper_set_desc_hint_ppcm(f: ?*anyopaque, v: f32) void {
    writeField(f32, f.?, d_hint_ppcm, v);
}
export fn fsrv_helper_get_desc_hint_width(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_hint_width);
}
export fn fsrv_helper_set_desc_hint_width(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, d_hint_width, v);
}
export fn fsrv_helper_get_desc_hint_height(f: ?*anyopaque) usize {
    return readField(usize, f.?, d_hint_height);
}
export fn fsrv_helper_set_desc_hint_height(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, d_hint_height, v);
}

// desc.aext
export fn fsrv_helper_get_desc_aext_hdr(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, d_aext_hdr);
}
export fn fsrv_helper_get_desc_aext_gamma(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, d_aext_gamma);
}
export fn fsrv_helper_get_desc_aext_gamma_map(f: ?*anyopaque) u8 {
    return readField(u8, f.?, d_aext_gamma_map);
}
export fn fsrv_helper_set_desc_aext_gamma_map(f: ?*anyopaque, v: u8) void {
    writeField(u8, f.?, d_aext_gamma_map, v);
}

// desc.recovery_tick
export fn fsrv_helper_get_desc_recovery_tick(f: ?*anyopaque) c_uint {
    return readField(c_uint, f.?, d_recovery_tick);
}

// (chunk 2 unique accessors: pending_queue, vbufs, abufs, shm_external, vstream, amixer_inaud)

export fn fsrv_helper_get_pending_queue(f: ?*anyopaque) [*]u8 {
    return ptrAdd(f.?, o_pending_queue);
}
export fn fsrv_helper_pending_queue_len() usize {
    return 4;
}

// vbufs / abufs — array of pointers, each 8 bytes
export fn fsrv_helper_get_vbuf(f: ?*anyopaque, i: c_int) ?*anyopaque {
    const idx: usize = @intCast(i);
    return readField(?*anyopaque, f.?, o_vbufs + idx * 8);
}
export fn fsrv_helper_get_abuf(f: ?*anyopaque, i: c_int) ?*anyopaque {
    const idx: usize = @intCast(i);
    return readField(?*anyopaque, f.?, o_abufs + idx * 8);
}

// shm_external
export fn fsrv_helper_get_shm_external(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, o_shm_external);
}

// vstream
export fn fsrv_helper_get_vstream_dead(f: ?*anyopaque) bool {
    return readField(bool, f.?, o_vstream_dead);
}
export fn fsrv_helper_set_vstream_dead(f: ?*anyopaque, v: bool) void {
    writeField(bool, f.?, o_vstream_dead, v);
}
export fn fsrv_helper_get_vstream_pending_used(f: ?*anyopaque) usize {
    return readField(usize, f.?, o_vstream_pending_used);
}
export fn fsrv_helper_set_vstream_pending_used(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, o_vstream_pending_used, v);
}
export fn fsrv_helper_get_vstream_incoming_used(f: ?*anyopaque) usize {
    return readField(usize, f.?, o_vstream_incoming_used);
}
export fn fsrv_helper_set_vstream_incoming_used(f: ?*anyopaque, v: usize) void {
    writeField(usize, f.?, o_vstream_incoming_used, v);
}

// amixer_inaud (unique to chunk 2)
export fn fsrv_helper_set_amixer_n_aids(f: ?*anyopaque, v: c_int) void {
    writeField(c_uint, f.?, o_amixer_n_aids, @bitCast(v));
}
export fn fsrv_helper_get_amixer_inaud(f: ?*anyopaque) ?*anyopaque {
    return readField(?*anyopaque, f.?, o_amixer_inaud);
}
export fn fsrv_helper_set_amixer_inaud(f: ?*anyopaque, v: ?*anyopaque) void {
    writeField(?*anyopaque, f.?, o_amixer_inaud, v);
}
// Chunk 3: page accessors + signal

// shmif_page field accessors (atomic / opaque)
//
// The page pointer `p` is ?*anyopaque (opaque arcan_shmif_page*).
// All field access is via byte offsets from OFFSETS.md.
//
// C source: arcan_frameserver_helpers.c lines 272-359

// -- Non-atomic page fields: resized, cookie, dms --

export fn fsrv_helper_page_get_resized(p: ?*anyopaque) i8 {
    return readField(i8, p.?, pg_resized);
}

export fn fsrv_helper_page_get_cookie(p: ?*anyopaque) u32 {
    // cookie is u64 in shmif_page, but the C helper returns uint32_t (truncates)
    return @truncate(readField(u64, p.?, pg_cookie));
}

export fn fsrv_helper_page_get_dms(p: ?*anyopaque) i8 {
    return @bitCast(readField(u8, p.?, pg_dms));
}

// -- Atomic u32 fields: vready, aready, vpending, apending --

export fn fsrv_helper_page_vready(p: ?*anyopaque) c_int {
    return @bitCast(atomicLoad32(p.?, pg_vready));
}

export fn fsrv_helper_page_set_vready(p: ?*anyopaque, v: c_int) void {
    atomicStore32(p.?, pg_vready, @bitCast(v));
}

export fn fsrv_helper_page_vpending(p: ?*anyopaque) c_int {
    return @bitCast(atomicLoad32(p.?, pg_vpending));
}

export fn fsrv_helper_page_vpending_and(p: ?*anyopaque, mask: c_int) void {
    _ = atomicFetchAnd32(p.?, pg_vpending, @bitCast(mask));
}

export fn fsrv_helper_page_aready(p: ?*anyopaque) c_int {
    return @bitCast(atomicLoad32(p.?, pg_aready));
}

export fn fsrv_helper_page_set_aready(p: ?*anyopaque, v: c_int) void {
    atomicStore32(p.?, pg_aready, @bitCast(v));
}

export fn fsrv_helper_page_apending(p: ?*anyopaque) c_int {
    return @bitCast(atomicLoad32(p.?, pg_apending));
}

export fn fsrv_helper_page_set_apending(p: ?*anyopaque, v: c_int) void {
    atomicStore32(p.?, pg_apending, @bitCast(v));
}

export fn fsrv_helper_page_apending_fetch_and(p: ?*anyopaque, mask: c_int) c_int {
    return @bitCast(atomicFetchAnd32(p.?, pg_apending, @bitCast(mask)));
}

// -- abufused: array of u16 at pg_abufused, each element 2 bytes --
//    C: atomic_store for set, plain read for get

export fn fsrv_helper_page_set_abufused(p: ?*anyopaque, i: c_int, v: u32) void {
    const off = pg_abufused + @as(usize, @intCast(i)) * 2;
    writeField(u16, p.?, off, @truncate(v));
}

export fn fsrv_helper_page_get_abufused(p: ?*anyopaque, i: c_int) u32 {
    const off = pg_abufused + @as(usize, @intCast(i)) * 2;
    return readField(u16, p.?, off);
}

// -- w, h: atomic u16 (uint_least16_t) --

export fn fsrv_helper_page_get_w(p: ?*anyopaque) u16 {
    return @atomicLoad(u16, fieldPtr(u16, p.?, pg_w), .seq_cst);
}

export fn fsrv_helper_page_get_h(p: ?*anyopaque) u16 {
    return @atomicLoad(u16, fieldPtr(u16, p.?, pg_h), .seq_cst);
}

// -- hints: atomic u8 (uint_least8_t) --

export fn fsrv_helper_page_get_hints(p: ?*anyopaque) c_int {
    return @atomicLoad(u8, fieldPtr(u8, p.?, pg_hints), .seq_cst);
}

// -- vpts: atomic u64 (uint_least64_t) --

export fn fsrv_helper_page_get_vpts(p: ?*anyopaque) i64 {
    return @bitCast(@atomicLoad(u64, fieldPtr(u64, p.?, pg_vpts), .seq_cst));
}

export fn fsrv_helper_page_set_vpts(p: ?*anyopaque, v: i64) void {
    @atomicStore(u64, fieldPtr(u64, p.?, pg_vpts), @bitCast(v), .seq_cst);
}

// -- dirty region: _Atomic struct arcan_shmif_region (8 bytes at pg_dirty) --
//    Layout within the 8 bytes: x1@+0, x2@+2, y1@+4, y2@+6 (each i16)
//    Load/store atomically as a single u64, then extract/pack fields.

export fn fsrv_helper_page_get_dirty(
    p: ?*anyopaque,
    x1: *i16,
    y1: *i16,
    x2: *i16,
    y2: *i16,
) void {
    const raw = @atomicLoad(u64, fieldPtr(u64, p.?, pg_dirty), .seq_cst);
    const bytes: [8]u8 = @bitCast(raw);
    x1.* = @bitCast([2]u8{ bytes[0], bytes[1] }); // offset +0
    x2.* = @bitCast([2]u8{ bytes[2], bytes[3] }); // offset +2
    y1.* = @bitCast([2]u8{ bytes[4], bytes[5] }); // offset +4
    y2.* = @bitCast([2]u8{ bytes[6], bytes[7] }); // offset +6
}

export fn fsrv_helper_page_set_dirty(
    p: ?*anyopaque,
    x1: i16,
    y1: i16,
    x2: i16,
    y2: i16,
) void {
    // Pack fields in memory order: x1@+0, x2@+2, y1@+4, y2@+6
    const b_x1: [2]u8 = @bitCast(x1);
    const b_x2: [2]u8 = @bitCast(x2);
    const b_y1: [2]u8 = @bitCast(y1);
    const b_y2: [2]u8 = @bitCast(y2);
    const raw: u64 = @bitCast([8]u8{
        b_x1[0], b_x1[1],
        b_x2[0], b_x2[1],
        b_y1[0], b_y1[1],
        b_y2[0], b_y2[1],
    });
    @atomicStore(u64, fieldPtr(u64, p.?, pg_dirty), raw, .seq_cst);
}

// signal: handles atomic CAS on shmpage futex fields
//
// C source: arcan_frameserver_helpers.c lines 343-358
//
// The C code does:
//   1. Check esync == 1, if so clear it and accumulate SYNC_EVENT
//   2. atomic_compare_exchange_strong(&vsync, &(inv=1), 0) → accumulate SYNC_VIDEO
//   3. atomic_compare_exchange_strong(&async, &(inv=1), 0) → accumulate SYNC_AUDIO
//   4. Call platform_fsrv_signal(tgt, outfl) with accumulated flags

export fn fsrv_helper_signal(tgt: ?*anyopaque, fl: c_int) void {
    const t = tgt orelse return;

    // tgt->shm.ptr
    const page: ?*anyopaque = readField(?*anyopaque, t, o_shm_ptr);
    const p = page orelse return;

    // Check dms — if dead-man-switch is 0, client has disconnected
    if (readField(u8, p, pg_dms) == 0) {
        return;
    }

    var outfl: c_int = 0;

    // SYNC_EVENT: non-atomic read/write on esync (plain u32, not _Atomic in C)
    if (fl & SYNC_EVENT != 0) {
        if (readField(u32, p, pg_esync) == 1) {
            writeField(u32, p, pg_esync, 0);
            outfl |= SYNC_EVENT;
        }
    }

    // SYNC_VIDEO: atomic CAS vsync 1→0
    if (fl & SYNC_VIDEO != 0) {
        const result = @cmpxchgStrong(
            u32,
            fieldPtr(u32, p, pg_vsync),
            1,
            0,
            .seq_cst,
            .seq_cst,
        );
        if (result == null) {
            // CAS succeeded: vsync was 1, now 0
            outfl |= SYNC_VIDEO;
        }
    }

    // SYNC_AUDIO: atomic CAS async 1→0
    if (fl & SYNC_AUDIO != 0) {
        const result = @cmpxchgStrong(
            u32,
            fieldPtr(u32, p, pg_async),
            1,
            0,
            .seq_cst,
            .seq_cst,
        );
        if (result == null) {
            // CAS succeeded: async was 1, now 0
            outfl |= SYNC_AUDIO;
        }
    }

    platform_fsrv_signal(t, outfl);
}
// Chunk 4: autoclock + control + free + emit
//
// Functions ported from arcan_frameserver_helpers.c lines 361-705, 1112-1289.
// Uses readField/writeField/getBitfield/setBitfield/ptrAdd/fieldPtr from chunk 1,
// all offset constants from the shared constants block, and extern fn declarations.

// Local helper: write a typed value into a zeroed event buffer at an offset

fn writeEventField(comptime T: type, ev: *[128]u8, off: usize, val: T) void {
    @as(*align(1) T, @ptrCast(&ev[off])).* = val;
}

fn readEventField(comptime T: type, ev: *const [128]u8, off: usize) T {
    return @as(*align(1) const T, @ptrCast(&ev[off])).*;
}

// Chunk 4 unique constants

// Alias offsets for shmif_page fields used in chunk 4 with different names
const page_dms: usize = pg_dms;
const page_cookie: usize = pg_cookie;

// Aliases for struct sizes used in chunk 4
const sizeof_arcan_event: usize = sz_arcan_event;
const sizeof_agp_buffer_plane: usize = sz_agp_buffer_plane;

// (chunk 4 uses extern fn from chunk 1 and local fsrv_helper_* functions)

// ─────────────────────────────────────────────────────────────────────────────
// 1. fsrv_helper_default_adoph(tgt, id)
//    C: tgt->parent.vid = arcan_video_findstate(ARCAN_TAG_FRAMESERV, tgt->parent.ptr);
//       tgt->vid = id;
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_default_adoph(tgt: ?*anyopaque, id: i64) void {
    const f = tgt orelse return;
    const parent_ptr = readField(?*anyopaque, f, o_parent_ptr);
    const found_vid = arcan_video_findstate(ARCAN_TAG_FRAMESERV, parent_ptr);
    writeField(i64, f, o_parent_vid, found_vid);
    writeField(i64, f, o_vid, id);
}

// ─────────────────────────────────────────────────────────────────────────────
// 2. fsrv_helper_autoclock_frame(tgt)
//    Reads clock.left/frametime/start/id/once, constructs STEPFRAME event.
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_autoclock_frame(tgt: ?*anyopaque) void {
    const f = tgt orelse return;

    const left = readField(u32, f, o_clock_left);
    if (left == 0) return;

    var frametime = readField(i64, f, o_clock_frametime);
    if (frametime == 0) {
        frametime = arcan_frametime();
        writeField(i64, f, o_clock_frametime, frametime);
    }

    const now = arcan_frametime();
    const delta: i64 = now - frametime;
    if (delta < 0) {
        writeField(i64, f, o_clock_frametime, now);
        return;
    }
    if (delta == 0) return;

    const start = readField(u32, f, o_clock_start);

    if (@as(i64, @intCast(left)) <= delta) {
        // Reset clock
        writeField(u32, f, o_clock_left, start);
        writeField(i64, f, o_clock_frametime, now);

        // Build TARGET_COMMAND_STEPFRAME event
        var ev = std.mem.zeroes([128]u8);
        writeEventField(u8, &ev, ev_category, EVENT_TARGET);
        writeEventField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);

        // ioevs[0].iv = delta / start
        const step_count: i32 = @intCast(@divTrunc(delta, @as(i64, @intCast(start))));
        writeEventField(i32, &ev, ev_tgt_ioevs0_iv, step_count);

        // ioevs[1].uiv = clock.id
        const clock_id = readField(u32, f, o_clock_id);
        writeEventField(u32, &ev, ev_tgt_ioevs1_uiv, clock_id);

        // If once, zero out left so we don't fire again
        const once = readField(bool, f, o_clock_once);
        if (once) {
            writeField(u32, f, o_clock_left, 0);
        }

        _ = platform_fsrv_pushevent(f, &ev);
    } else {
        // Subtract delta from left
        const new_left = left -% @as(u32, @intCast(@as(u32, @truncate(@as(u64, @bitCast(delta))))));
        writeField(u32, f, o_clock_left, new_left);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. fsrv_helper_control_chld(src)
//    Checks alive, shm.ptr, dms, cookie, parent vobj. Frees if dead.
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_control_chld(src: ?*anyopaque) bool {
    const f = src orelse return false;

    // Track which specific aliveness check failed first. We record the
    // reason in a small integer so the log line at the bottom of this
    // function can identify the exact invariant that went bad — otherwise
    // we just see "control_chld returned false" and have to guess.
    // 0 = still alive, 1 = flags.alive, 2 = shm_ptr null, 3 = dms==0,
    // 4 = validchild failed, 5 = cookie, 6 = parent vobj missing/retyped.
    var death_cause: c_int = 0;

    // Check flags.alive
    var alive = getBitfield(f, fl_byte_alive, fl_mask_alive);
    if (!alive) death_cause = 1;

    // Check shm.ptr != null
    const shm_ptr_val = readField(?[*]u8, f, o_shm_ptr);
    if (alive) {
        alive = (shm_ptr_val != null);
        if (!alive) death_cause = 2;
    }

    // Check shm.ptr->dms != 0
    if (alive) {
        if (shm_ptr_val) |page| {
            const dms = page[page_dms];
            if (dms == 0) {
                alive = false;
                death_cause = 3;
            }
        }
    }

    // platform_fsrv_validchild
    if (alive) {
        alive = platform_fsrv_validchild(f);
        if (!alive) death_cause = 4;

        // Cookie check
        if (alive) {
            if (shm_ptr_val) |page| {
                const cookie_ptr: *align(1) const u64 = @ptrCast(&page[page_cookie]);
                const page_cookie_val: u32 = @truncate(cookie_ptr.*);
                if (page_cookie_val != arcan_shmif_cookie()) {
                    writeField(bool, f, o_cookie_fail, true);
                    alive = false;
                    death_cause = 5;
                }
            }
        }
    }

    // Check parent vobj
    if (alive) {
        const parent_vid = readField(i64, f, o_parent_vid);
        if (parent_vid != ARCAN_EID) {
            const vobj = arcan_video_getobject(parent_vid);
            if (vobj) |vo| {
                // Check feed.state.tag == ARCAN_TAG_FRAMESERV
                const vo_bytes: [*]const u8 = @ptrCast(vo);
                const tag_val = @as(*align(1) const c_int, @ptrCast(&vo_bytes[vo_feed_state_tag])).*;
                if (tag_val != ARCAN_TAG_FRAMESERV) {
                    alive = false;
                    death_cause = 6;
                }
            } else {
                alive = false;
                death_cause = 6;
            }
        }
    }

    if (!alive) {
        // Log EXACTLY which invariant first went false. This pins the root
        // of bug #30 (terminals destroyed on font-size change) — each
        // cause points at a different upstream fix.
        const pid = readField(c_int, f, o_child);
        const vid = readField(i64, f, o_vid);
        const c_fopen = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const c_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const c_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (c_fopen("/tmp/arcan_fsrv_free.log", "a")) |log_f| {
            _ = c_fprintf(
                log_f,
                "control_chld_died: vid=%lld pid=%d cause=%d (1=flag,2=shm_null,3=dms0,4=invalidchild,5=cookie,6=parent)\n",
                @as(c_longlong, vid),
                @as(c_int, pid),
                death_cause,
            );
            _ = c_fclose(log_f);
        }
        _ = fsrv_helper_free(src);
        return false;
    }
    return true;
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. fsrv_helper_close_bufferqueues(src, incoming, pending)
//    Iterates vstream.incoming/pending arrays, closes fd/fence.
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_close_bufferqueues(src: ?*anyopaque, incoming: bool, pending: bool) void {
    const f = src orelse return;

    if (incoming) {
        const used = readField(usize, f, o_vstream_incoming_used);
        var i: usize = 0;
        while (i < used) : (i += 1) {
            const base = o_vstream_incoming + i * sizeof_agp_buffer_plane;
            const fd_val = readField(c_int, f, base + bp_fd);
            if (fd_val > 0) {
                _ = close(@intCast(fd_val));
                writeField(c_int, f, base + bp_fd, -1);
            }
            const fence_val = readField(c_int, f, base + bp_fence);
            if (fence_val > 0) {
                _ = close(@intCast(fence_val));
                writeField(c_int, f, base + bp_fence, -1);
            }
        }
        writeField(usize, f, o_vstream_incoming_used, 0);
    }

    if (pending) {
        const used = readField(usize, f, o_vstream_pending_used);
        var i: usize = 0;
        while (i < used) : (i += 1) {
            const base = o_vstream_pending + i * sizeof_agp_buffer_plane;
            const fd_val = readField(c_int, f, base + bp_fd);
            if (fd_val > 0) {
                _ = close(@intCast(fd_val));
                writeField(c_int, f, base + bp_fd, -1);
            }
            const fence_val = readField(c_int, f, base + bp_fence);
            if (fence_val > 0) {
                _ = close(@intCast(fence_val));
                writeField(c_int, f, base + bp_fence, -1);
            }
        }
        writeField(usize, f, o_vstream_pending_used, 0);
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// 5. fsrv_helper_flush_queued(tgt)
//    Iterates pending_queue[0..n_pending], pushes events.
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_flush_queued(tgt: ?*anyopaque) void {
    const f = tgt orelse return;

    const n_pending = readField(usize, f, o_n_pending);
    var torem: usize = 0;

    var i: usize = 0;
    while (i < n_pending) : (i += 1) {
        const ev_ptr = ptrAdd(f, o_pending_queue + i * sizeof_arcan_event);
        const ev: *const [128]u8 = @ptrCast(ev_ptr);
        if (ARCAN_OK != platform_fsrv_pushevent(f, ev))
            return;
        torem += 1;
    }

    if (torem == n_pending) {
        writeField(usize, f, o_n_pending, 0);
        return;
    }

    // Partial flush: shift remaining events forward
    const remaining = n_pending - torem;
    writeField(usize, f, o_n_pending, remaining);

    const dst_ptr = ptrAdd(f, o_pending_queue);
    const src_ptr = ptrAdd(f, o_pending_queue + torem * sizeof_arcan_event);
    const byte_count = sizeof_arcan_event * remaining;

    // memmove equivalent: use copyBackwards/copyForwards as appropriate
    // Since dst < src (torem > 0 when partial), forward copy is safe.
    const dst_slice: [*]u8 = @ptrCast(dst_ptr);
    const src_slice: [*]const u8 = @ptrCast(src_ptr);
    @memcpy(dst_slice[0..byte_count], src_slice[0..byte_count]);
}

// ─────────────────────────────────────────────────────────────────────────────
// 7. emit_deliveredframe(src, pts, framecount) — internal, NOT exported
// ─────────────────────────────────────────────────────────────────────────────

fn emit_deliveredframe(src: *anyopaque, pts: u64, framecount: u64) void {
    var ev = std.mem.zeroes([128]u8);

    writeEventField(u8, &ev, ev_category, EVENT_FSRV);
    writeEventField(u32, &ev, ev_fsrv_kind, EVENT_FSRV_DELIVEREDFRAME);
    writeEventField(u64, &ev, ev_fsrv_pts, pts);
    writeEventField(u64, &ev, ev_fsrv_counter, framecount);
    writeEventField(isize, &ev, ev_fsrv_otag, readField(isize, src, o_tag));
    writeEventField(i32, &ev, ev_fsrv_audio, readField(i32, src, o_aid));
    writeEventField(i64, &ev, ev_fsrv_video, readField(i64, src, o_vid));

    // If region_valid, use region dimensions; otherwise use desc.width/height
    const region_valid = readField(bool, src, d_region_valid);
    if (region_valid) {
        const rx1 = readField(i16, src, d_region_x1);
        const ry1 = readField(i16, src, d_region_y1);
        const rx2 = readField(i16, src, d_region_x2);
        const ry2 = readField(i16, src, d_region_y2);
        writeEventField(usize, &ev, ev_fsrv_xofs, @intCast(@as(u16, @bitCast(rx1))));
        writeEventField(usize, &ev, ev_fsrv_yofs, @intCast(@as(u16, @bitCast(ry1))));
        writeEventField(usize, &ev, ev_fsrv_width, @intCast(@as(u16, @bitCast(rx2 - rx1))));
        writeEventField(usize, &ev, ev_fsrv_height, @intCast(@as(u16, @bitCast(ry2 - ry1))));
    } else {
        const w = readField(u16, src, d_width);
        const h = readField(u16, src, d_height);
        writeEventField(usize, &ev, ev_fsrv_width, @intCast(w));
        writeEventField(usize, &ev, ev_fsrv_height, @intCast(h));
    }

    _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

// ─────────────────────────────────────────────────────────────────────────────
// 8. emit_droppedframe(src, pts, dropcount) — internal, NOT exported
// ─────────────────────────────────────────────────────────────────────────────

fn emit_droppedframe(src: *anyopaque, pts: u64, dropcount: u64) void {
    var ev = std.mem.zeroes([128]u8);

    writeEventField(u8, &ev, ev_category, EVENT_FSRV);
    writeEventField(u32, &ev, ev_fsrv_kind, EVENT_FSRV_DROPPEDFRAME);
    writeEventField(u64, &ev, ev_fsrv_pts, pts);
    writeEventField(u64, &ev, ev_fsrv_counter, dropcount);
    writeEventField(isize, &ev, ev_fsrv_otag, readField(isize, src, o_tag));
    writeEventField(i32, &ev, ev_fsrv_audio, readField(i32, src, o_aid));
    writeEventField(i64, &ev, ev_fsrv_video, readField(i64, src, o_vid));

    _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

// ─────────────────────────────────────────────────────────────────────────────
// 6. fsrv_helper_free(src) — the big cleanup function
//    C: arcan_frameserver_helpers.c lines 1234-1289
// ─────────────────────────────────────────────────────────────────────────────

export fn fsrv_helper_free(src: ?*anyopaque) c_int {
    const f = src orelse return ARCAN_ERRC_NO_SUCH_OBJECT;

    // One-line-per-free trace to /tmp/arcan_fsrv_free.log. Lightweight,
    // useful for correlating frameserver teardowns with other log streams
    // (control_chld cause, validchild waitpid status) when diagnosing
    // unexpected disappearances. The noisy dumpCurrentStackTrace that
    // initially diagnosed bug #30 was dropped once it had done its job.
    {
        const pid = readField(c_int, f, o_child);
        const vid = readField(i64, f, o_vid);
        const activated = readField(c_int, f, fl_activated);
        const fused_flag = readField(bool, f, o_fused);
        const c_fopen = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const c_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const c_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        if (c_fopen("/tmp/arcan_fsrv_free.log", "a")) |log_f| {
            _ = c_fprintf(
                log_f,
                "fsrv_helper_free: vid=%lld pid=%d activated=%d fused=%d\n",
                @as(c_longlong, vid),
                @as(c_int, pid),
                @as(c_int, activated),
                @as(c_int, if (fused_flag) 1 else 0),
            );
            _ = c_fclose(log_f);
        }
    }

    // If fused, just mark fuse_blown and return OK
    const fused = readField(bool, f, o_fused);
    if (fused) {
        writeField(bool, f, o_fuse_blown, true);
        return ARCAN_OK;
    }

    // Deregister from conductor
    arcan_conductor_deregister_frameserver(src);

    // Close buffer queues (both incoming and pending)
    fsrv_helper_close_bufferqueues(src, true, true);

    // Save aid, tag, vid before teardown
    const aid = readField(i32, f, o_aid);
    const tag = readField(isize, f, o_tag);
    const vid = readField(i64, f, o_vid);

    // Walk alocks array, unhook each audio feed
    const alocks = readField(?[*]i32, f, o_alocks);
    if (alocks) |base_start| {
        var idx: usize = 0;
        while (base_start[idx] != 0) {
            arcan_audio_hookfeed(base_start[idx], null, null, null);
            idx += 1;
        }
    }
    writeField(?[*]i32, f, o_alocks, null);

    // Release font group
    const text_group = readField(?*anyopaque, f, d_text_group);
    arcan_renderfun_release_fontgroup(text_group);
    writeField(?*anyopaque, f, d_text_group, null);

    // Build EVENT_FSRV_TERMINATED event
    var sevent = std.mem.zeroes([128]u8);
    writeEventField(u8, &sevent, ev_category, EVENT_FSRV);
    writeEventField(u32, &sevent, ev_fsrv_kind, EVENT_FSRV_TERMINATED);
    writeEventField(i64, &sevent, ev_fsrv_video, vid);
    writeEventField(i32, &sevent, ev_fsrv_audio, aid);
    writeEventField(isize, &sevent, ev_fsrv_otag, tag);
    writeEventField(i8, &sevent, ev_fsrv_fmt_fl, 0);

    // Build lastwords message
    var msg = std.mem.zeroes([32]u8);
    const cookie_fail = readField(bool, f, o_cookie_fail);

    if (cookie_fail) {
        const m = "Integrity cookie mismatch";
        @memcpy(msg[0..m.len], m);
    } else {
        if (!platform_fsrv_lastwords(f, &msg, 32)) {
            const m = "Couldn't access metadata";
            @memcpy(msg[0..m.len], m);
        }
    }

    // Detach video feed: alterfeed(vid, FFUNC_NULL, {0})
    const empty_state = vfunc_state{ .tag = 0, .ptr = null };
    _ = arcan_video_alterfeed(vid, FFUNC_NULL, empty_state);

    // MAY-151: stop audio FIRST, then destroy the frameserver. If destroy
    // runs first, the frameserver memory is freed but Aobj.feed_tag still
    // points at the recycled allocator slot; the next main-thread
    // arcan_aid_refresh -> refillStream -> audioframe_direct reads garbage
    // through that dangling pointer and trips @alignCast on the o_segid
    // offset (debug.FullPanic.incorrectAlignment). C upstream gets away with
    // the destroy-first order because malloc tends to hand the slot to the
    // next frameserver alloc, where o_segid happens to be valid; Zig's
    // alignment check surfaces the transient garbage as a hard crash.
    // Stopping audio first unlinks the Aobj from st.head, so refillStream
    // can never observe the dangling feed_tag.
    arcan_audio_stop(aid);

    // Destroy the platform-side frameserver
    if (!platform_fsrv_destroy(f)) {
        return ARCAN_ERRC_UNACCEPTED_STATE;
    }

    // Copy lastwords message into event and enqueue
    @memcpy(sevent[ev_fsrv_message .. ev_fsrv_message + 32], &msg);
    _ = arcan_event_enqueue(arcan_event_defaultctx(), &sevent);

    return ARCAN_OK;
}
// Chunk 5: FFuncs
//
// Pure-Zig ports of the 8 FFUNC implementations from arcan_frameserver_helpers.c.
// All use offset-based struct access via readField/writeField/atomicLoad32/atomicStore32
// from chunk 1, and emit_deliveredframe/emit_droppedframe from chunk 4.
//
// Available from chunk 1:
//   readField, writeField, getBitfield, setBitfield, ptrAdd, fieldPtr,
//   atomicLoad32, atomicStore32 — utility functions
//   All o_*, d_*, fl_*, sp_* offset/mask constants
//   All extern fn declarations (arcan_frameserver_free, platform_fsrv_*, etc.)
//   g_buffers_locked — file-scope var
//   const std = @import("std")
//
// Available from chunk 4:
//   emit_deliveredframe(src, pts, framecount)
//   emit_droppedframe(src, pts, dropcount)

// Chunk 5 unique FFUNC identifier aliases
const FFUNC_ID_NULL: c_int = FFUNC_NULL;
const FFUNC_ID_VFRAME: c_int = FFUNC_VFRAME_ENUM;
const FFUNC_ID_NULLFRAME: c_int = FFUNC_NULLFRAME;
const FFUNC_ID_SOCKVER: c_int = FFUNC_SOCKVER;

// Chunk 5 unique hints
const SHMIF_RHINT_SUBREGION: c_int = 2;

// Chunk 5 renamed constant aliases
const ARCAN_PLAYING_C5: c_int = ARCAN_PLAYING;
const SYNC_VIDEO_C5: c_int = SYNC_VIDEO;
const ARCAN_OK_C5: c_int = ARCAN_OK;

// Chunk 5 unique event layout constants
const ev_size: usize = sz_arcan_event;
const ev_tgt_ioevs_0_iv: usize = ev_tgt_ioevs0_iv; // alias
const ev_tgt_ioevs_1_iv: usize = 8; // i32 (union: .iv / .uiv)
const ev_tgt_ioevs_2_uiv: usize = 12; // u32
const ev_tgt_ioevs_3_iv: usize = 16; // i32

// fsrv event field offsets unique to chunk 5
const ev_fsrv_descriptor: usize = 40; // i64 (union alt: ident at 8..40)
const ev_fsrv_ident: usize = 8; // [32]u8 (union alt)
const ev_fsrv_ident_len: usize = 32;

// Chunk 5 shmif_page aliases (sp_* → pg_*)
const sp_resized: usize = pg_resized;
const sp_vready: usize = pg_vready;
const sp_aready: usize = pg_aready;
const sp_apending: usize = pg_apending;
const sp_vpts: usize = pg_vpts;
const sp_dirty: usize = pg_dirty;
const sp_hints: usize = pg_hints;
const sp_w: usize = pg_w;
const sp_h: usize = pg_h;
const sp_abufused: usize = pg_abufused;

// vobject_frameset offsets (sizeof = 40)
const fs_frames: usize = 0; // *frameset_store
const fs_index: usize = 16; // usize

// frameset_store (sizeof = 40, .frame at offset 0)
const fss_frame: usize = 0;
const fss_stride: usize = 40;

// arcan_shmif_cont offsets (sizeof = 192)
const cont_addr_off: usize = 0; // ?*arcan_shmif_page
const cont_vidp_off: usize = 8; // *av_pixel
const cont_w_off: usize = 80; // usize
const cont_h_off: usize = 88; // usize
const cont_stride_off: usize = 96; // usize

// stream_meta offsets unique to chunk 5 (sizeof = 240)
const sm_size: usize = 240;
// sm_buf, sm_w, sm_h defined in chunk 6
const sm_stride_off: usize = 28; // unsigned int (c_uint)
const sm_type: usize = 232; // c_int (enum stream_type)

// Chunk 5 unique constants
const EBADF: c_int = 9;
const EWOULDBLOCK: c_int = 11;

extern fn __errno_location() *c_int;
fn getErrno() c_int {
    return __errno_location().*;
}

// Helpers for constructing events as byte arrays

fn zeroEvent() [ev_size]u8 {
    var buf: [ev_size]u8 = undefined;
    @memset(&buf, 0);
    return buf;
}

/// Write a typed value into an event byte buffer at the given offset.
fn writeEvField(comptime T: type, buf: *[ev_size]u8, offset: usize, val: T) void {
    const ptr: *const [@sizeOf(T)]u8 = @ptrCast(&val);
    @memcpy(buf[offset..][0..@sizeOf(T)], ptr);
}

/// Get dst_store: if vobj has frameset, use frameset->frames[index].frame; else vobj->vstore
fn getDstStore(vobj: *anyopaque) ?*anyopaque {
    const frameset_ptr = readField(?*anyopaque, vobj, vo_frameset);
    if (frameset_ptr) |fs| {
        const frames = readField(?*anyopaque, fs, fs_frames);
        const index = readField(usize, fs, fs_index);
        if (frames) |fr| {
            // frames[index].frame — each frameset_store is fss_stride bytes, .frame at offset 0
            return readField(?*anyopaque, fr, index * fss_stride + fss_frame);
        }
    }
    return readField(?*anyopaque, vobj, vo_vstore);
}

/// Get the owner rendertarget's msc for a vobj
fn getOwnerMsc(vobj: *anyopaque) u32 {
    const owner = readField(?*anyopaque, vobj, vo_owner);
    if (owner) |o| {
        return readField(u32, o, rt_msc);
    }
    return 0;
}

/// Build and push a TARGET_COMMAND_STEPFRAME event
fn pushStepframeEvent(tgt: *anyopaque, iv0: i32, iv1: i32, msc: u32) void {
    var ev = zeroEvent();
    writeEvField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);
    writeEvField(i32, &ev, ev_tgt_ioevs_0_iv, iv0);
    writeEvField(i32, &ev, ev_tgt_ioevs_1_iv, iv1);
    writeEvField(u32, &ev, ev_tgt_ioevs_2_uiv, msc);
    ev[ev_category] = EVENT_TARGET;
    _ = platform_fsrv_pushevent(tgt, &ev);
}

/// Write @sizeOf(T) bytes from val into a byte buffer at offset.
fn writeBytesAt(comptime T: type, buf: [*]u8, offset: usize, val: T) void {
    const ptr: *const [@sizeOf(T)]u8 = @ptrCast(&val);
    @memcpy(buf[offset..][0..@sizeOf(T)], ptr);
}

/// Read @sizeOf(T) bytes from a byte buffer at offset.
fn readBytesAt(comptime T: type, buf: [*]const u8, offset: usize) T {
    var val: T = undefined;
    const dst: *[@sizeOf(T)]u8 = @ptrCast(&val);
    @memcpy(dst, buf[offset..][0..@sizeOf(T)]);
    return val;
}

// ════════════════════════════════════════════════════════════════════════════
// 1. nullfeed (C lines 1628-1654)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_nullfeed(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    const tgt_ptr = state.ptr orelse return FRV_NOFRAME;
    if (state.tag != ARCAN_TAG_FRAMESERV)
        return FRV_NOFRAME;

    if (!fsrv_helper_tramp_enter(tgt_ptr))
        return FRV_NOFRAME;

    if (cmd == FFUNC_CMD_DESTROY) {
        _ = fsrv_helper_free(tgt_ptr);
    } else if (cmd == FFUNC_CMD_ADOPT) {
        fsrv_helper_default_adoph(tgt_ptr, srcid);
    } else if (cmd == FFUNC_CMD_TICK) {
        if (!fsrv_helper_control_chld(tgt_ptr)) {
            platform_fsrv_leave();
            return FRV_NOFRAME;
        }
        _ = arcan_event_queuetransfer(
            arcan_event_defaultctx(),
            @as(?*anyopaque, @ptrCast(ptrAdd(tgt_ptr, o_inqueue))),
            readField(c_int, tgt_ptr, o_queue_mask),
            0.5,
            tgt_ptr,
        );
    }

    platform_fsrv_leave();
    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 2. emptyframe (C lines 1656-1700)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_emptyframe(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    const tgt_ptr = state.ptr orelse return FRV_NOFRAME;
    if (state.tag != ARCAN_TAG_FRAMESERV)
        return FRV_NOFRAME;

    if (!fsrv_helper_tramp_enter(tgt_ptr))
        return FRV_NOFRAME;

    switch (cmd) {
        FFUNC_CMD_POLL => {
            const shmpage = readField(?*anyopaque, tgt_ptr, o_shm_ptr);
            if (shmpage) |shm| {
                if (readField(i8, shm, sp_resized) != 0) {
                    if (fsrv_helper_tick_control(tgt_ptr, false, FFUNC_ID_VFRAME)) {
                        const shm2 = readField(?*anyopaque, tgt_ptr, o_shm_ptr);
                        if (shm2) |s2| {
                            if (atomicLoad32(s2, sp_vready) != 0) {
                                platform_fsrv_leave();
                                return FRV_GOTFRAME;
                            }
                        }
                    }
                }
            }
            if (readField(usize, tgt_ptr, o_n_pending) > 0)
                fsrv_helper_flush_queued(tgt_ptr);
            if (getBitfield(tgt_ptr, fl_byte_autoclock, fl_mask_autoclock) and
                readField(bool, tgt_ptr, o_clock_frame))
            {
                fsrv_helper_autoclock_frame(tgt_ptr);
            }
        },
        FFUNC_CMD_TICK => {
            _ = fsrv_helper_tick_control(tgt_ptr, true, FFUNC_ID_VFRAME);
        },
        FFUNC_CMD_DESTROY => {
            _ = fsrv_helper_free(tgt_ptr);
        },
        FFUNC_CMD_ADOPT => {
            fsrv_helper_default_adoph(tgt_ptr, srcid);
        },
        else => {},
    }

    platform_fsrv_leave();
    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 3. pollffunc (C lines 1703-1753)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_pollffunc(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = srcid;

    const tgt_ptr = state.ptr orelse return FRV_NOFRAME;
    const shmpage = readField(?*anyopaque, tgt_ptr, o_shm_ptr);

    if (state.tag != ARCAN_TAG_FRAMESERV or shmpage == null) {
        arcan_warning("platform/posix/frameserver.c:socketpoll, called with" ++
            " invalid source tag, investigate.\n");
        return FRV_NOFRAME;
    }

    switch (cmd) {
        FFUNC_CMD_POLL => {
            const sc = platform_fsrv_socketpoll(tgt_ptr);
            if (sc == -1) {
                if (getErrno() == EBADF)
                    _ = fsrv_helper_free(tgt_ptr);
                return FRV_NOFRAME;
            }

            // Switch feed to SOCKVER
            _ = arcan_video_alterfeed(
                readField(i64, tgt_ptr, o_vid),
                FFUNC_ID_SOCKVER,
                state,
            );

            // Build EXTCONN event
            var ev = zeroEvent();
            ev[ev_category] = EVENT_FSRV;
            writeEvField(u32, &ev, ev_fsrv_kind, EVENT_FSRV_EXTCONN);
            writeEvField(i64, &ev, ev_fsrv_descriptor, @as(i64, sc));
            writeEvField(isize, &ev, ev_fsrv_otag, readField(isize, tgt_ptr, o_tag));
            writeEvField(i64, &ev, ev_fsrv_video, readField(i64, tgt_ptr, o_vid));

            // Copy sockkey into fsrv.ident (32 bytes at offset 8)
            const sockkey = readField(?[*]const u8, tgt_ptr, o_sockkey);
            if (sockkey) |key| {
                var i: usize = 0;
                while (i < ev_fsrv_ident_len - 1) : (i += 1) {
                    if (key[i] == 0) break;
                    ev[ev_fsrv_ident + i] = key[i];
                }
                ev[ev_fsrv_ident + i] = 0;
            }

            _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);

            // Tail-call to verifyffunc
            return fsrv_helper_verifyffunc(
                cmd,
                buf,
                buf_sz,
                width,
                height,
                mode,
                state,
                readField(i64, tgt_ptr, o_vid),
            );
        },
        FFUNC_CMD_DESTROY => {
            _ = fsrv_helper_free(tgt_ptr);
        },
        else => {},
    }

    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 4. verifyffunc (C lines 1756-1791)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_verifyffunc(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;
    _ = srcid;

    const tgt_ptr = state.ptr orelse return FRV_NOFRAME;

    switch (cmd) {
        FFUNC_CMD_POLL => {
            while (platform_fsrv_socketauth(tgt_ptr) == -1) {
                const errno_val = getErrno();
                if (errno_val == EBADF) {
                    _ = fsrv_helper_free(tgt_ptr);
                    return FRV_NOFRAME;
                } else if (errno_val == EWOULDBLOCK) {
                    return FRV_NOFRAME;
                }
            }
            // Auth succeeded — switch to NULLFRAME feed
            _ = arcan_video_alterfeed(
                readField(i64, tgt_ptr, o_vid),
                FFUNC_ID_NULLFRAME,
                state,
            );

            // Set up audio feed. Register the callconv(.c) wrapper
            // fsrv_helper_audioframe_direct, NOT the .auto-callconv private
            // audioframe_direct — refillStream calls this via an
            // arcan_afunc_cb (.c) pointer; an .auto callee shifts the arg
            // registers and @alignCast-panics on a garbage `tag`.
            var errc: c_int = 0;
            const aid = arcan_audio_feed(
                @as(?*const anyopaque, @ptrCast(&fsrv_helper_audioframe_direct)),
                tgt_ptr,
                &errc,
            );
            writeField(i32, tgt_ptr, o_aid, aid);
            writeField(usize, tgt_ptr, o_sz_audb, 0);
            writeField(i64, tgt_ptr, o_ofs_audb, 0);
            writeField(?[*]u8, tgt_ptr, o_audb, null);
            return FRV_NOFRAME;
        },
        FFUNC_CMD_DESTROY => {
            _ = fsrv_helper_free(tgt_ptr);
        },
        else => {},
    }

    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 5. vdirect (C lines 736-887)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_vdirect(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    var rv: c_int = FRV_NOFRAME;
    var do_aud: bool = false;

    if (state.tag != ARCAN_TAG_FRAMESERV or state.ptr == null)
        return rv;

    const tgt: *anyopaque = state.ptr.?;
    const shmpage = readField(?*anyopaque, tgt, o_shm_ptr) orelse return FRV_NOFRAME;

    if (!fsrv_helper_tramp_enter(tgt))
        return FRV_NOFRAME;

    // segid == SEGID_UNKNOWN -> tick_control and leave
    if (readField(c_int, tgt, o_segid) == SEGID_UNKNOWN) {
        _ = fsrv_helper_tick_control(tgt, false, FFUNC_ID_VFRAME);
        platform_fsrv_leave();
        if (do_aud) arcan_aid_refresh(readField(i32, tgt, o_aid));
        return rv;
    }

    switch (cmd) {
        FFUNC_CMD_READBACK, FFUNC_CMD_READBACK_HANDLE => {
            // no-op break
        },

        FFUNC_CMD_POLL => poll_blk: {
            if (readField(i8, shmpage, sp_resized) != 0) {
                _ = fsrv_helper_tick_control(tgt, false, FFUNC_ID_VFRAME);
                break :poll_blk;
            }
            if (readField(c_int, tgt, o_playstate) != ARCAN_PLAYING_C5)
                break :poll_blk;
            if (readField(usize, tgt, o_n_pending) > 0)
                fsrv_helper_flush_queued(tgt);

            do_aud = (atomicLoad32(shmpage, sp_aready) > 0 and
                atomicLoad32(shmpage, sp_apending) > 0);

            if (getBitfield(tgt, fl_byte_autoclock, fl_mask_autoclock) and
                readField(bool, tgt, o_clock_frame))
            {
                fsrv_helper_autoclock_frame(tgt);
            }

            rv = if (atomicLoad32(shmpage, sp_vready) != 0 and
                !getBitfield(tgt, fl_byte_release_pending, fl_mask_release_pending))
                FRV_GOTFRAME
            else
                FRV_NOFRAME;
        },

        FFUNC_CMD_TICK => {
            if (!fsrv_helper_tick_control(tgt, true, FFUNC_ID_VFRAME)) {
                platform_fsrv_leave();
                if (do_aud) arcan_aid_refresh(readField(i32, tgt, o_aid));
                return rv;
            }
        },

        FFUNC_CMD_DESTROY => {
            _ = fsrv_helper_free(tgt);
            platform_fsrv_leave();
            return rv;
        },

        FFUNC_CMD_RENDER => render_blk: {
            // Queue transfer
            const qt_rv = arcan_event_queuetransfer(
                arcan_event_defaultctx(),
                @as(?*anyopaque, @ptrCast(ptrAdd(tgt, o_inqueue))),
                readField(c_int, tgt, o_queue_mask),
                readField(f32, tgt, o_xfer_sat),
                tgt,
            );
            switch (qt_rv) {
                -2 => {
                    _ = fsrv_helper_free(tgt);
                    platform_fsrv_leave();
                    return rv;
                },
                -1 => {
                    // Re-enter tramp guard (C code: TRAMP_GUARD(FRV_NOFRAME, tgt))
                    if (!fsrv_helper_tramp_enter(tgt))
                        return FRV_NOFRAME;
                },
                else => {},
            }

            const vid = readField(i64, tgt, o_vid);
            const vobj = arcan_video_getobject(vid) orelse break :render_blk;
            const dst_store = getDstStore(vobj) orelse break :render_blk;

            do_aud = (atomicLoad32(shmpage, sp_aready) > 0 and
                atomicLoad32(shmpage, sp_apending) > 0);

            if (g_buffers_locked == 1 or getBitfield(tgt, fl_byte_locked, fl_mask_locked))
                break :render_blk;

            // Dirty region: if SHMIF_RHINT_SUBREGION set, pass 8-byte dirty region
            const hints_val = readField(u8, shmpage, sp_hints);
            var dirty_bytes: [8]u8 = undefined;
            const dirty_ptr: ?*anyopaque = if ((hints_val & @as(u8, @intCast(SHMIF_RHINT_SUBREGION))) != 0) blk: {
                const src_ptr = ptrAdd(shmpage, sp_dirty);
                @memcpy(&dirty_bytes, src_ptr[0..8]);
                break :blk @ptrCast(&dirty_bytes);
            } else null;

            const buffer_status = fsrv_helper_push_buffer(tgt, dst_store, dirty_ptr);
            if (buffer_status == -1)
                break :render_blk;

            // dst_store->vinf.text.vpts = shmpage->vpts
            const vpts = readField(u64, shmpage, sp_vpts);
            writeField(i64, dst_store, vs_vinf_text_vpts, @bitCast(vpts));

            // MSC feedback
            if (readField(bool, tgt, o_clock_msc_feedback)) {
                const owner_msc = getOwnerMsc(vobj);
                const clock_present = readField(u32, tgt, o_clock_present);

                if (clock_present != 0 and (clock_present + 1 <= owner_msc)) {
                    pushStepframeEvent(tgt, 1, 1, owner_msc);
                    writeField(u32, tgt, o_clock_present, 0);
                    writeField(bool, tgt, o_clock_msc_feedback, false);
                } else if (clock_present == 0 and readField(u32, tgt, o_clock_last_msc) != owner_msc) {
                    pushStepframeEvent(tgt, 1, 1, owner_msc);
                    writeField(u32, tgt, o_clock_last_msc, owner_msc);
                }
            }

            // Frame delivery bookkeeping
            if (readField(bool, tgt, d_callback_framestate) and buffer_status != 0)
                emit_deliveredframe(tgt, vpts, readField(u64, tgt, d_framecount));
            const fc = readField(u64, tgt, d_framecount);
            writeField(u64, tgt, d_framecount, fc +% 1);

            // Release or defer
            if (g_buffers_locked != 2) {
                atomicStore32(shmpage, sp_vready, 0);
                fsrv_helper_signal(tgt, SYNC_VIDEO_C5);

                if ((readField(c_int, tgt, d_hints) & SHMIF_RHINT_VSIGNAL_EV) != 0) {
                    pushStepframeEvent(tgt, 1, 0, getOwnerMsc(vobj));
                }
            } else {
                setBitfield(tgt, fl_byte_release_pending, fl_mask_release_pending, true);
            }
        },

        FFUNC_CMD_ADOPT => {
            fsrv_helper_default_adoph(tgt, srcid);
        },

        else => {},
    }

    platform_fsrv_leave();
    if (do_aud) arcan_aid_refresh(readField(i32, tgt, o_aid));
    return rv;
}

// ════════════════════════════════════════════════════════════════════════════
// 6. feedcopy (C lines 890-952)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_feedcopy(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    const src: *anyopaque = state.ptr orelse return FRV_NOFRAME;

    if (!fsrv_helper_tramp_enter(src))
        return FRV_NOFRAME;

    if (cmd == FFUNC_CMD_DESTROY) {
        _ = fsrv_helper_free(state.ptr);
    } else if (cmd == FFUNC_CMD_ADOPT) {
        fsrv_helper_default_adoph(src, srcid);
    } else if (cmd == FFUNC_CMD_POLL) {
        if (!fsrv_helper_control_chld(src)) {
            platform_fsrv_leave();
            return FRV_NOFRAME;
        }

        const shmpage = readField(?*anyopaque, src, o_shm_ptr) orelse {
            platform_fsrv_leave();
            return FRV_NOFRAME;
        };

        if (atomicLoad32(shmpage, sp_vready) == 0) poll_copy: {
            const vid = readField(i64, src, o_vid);
            const me = arcan_video_getobject(vid) orelse break :poll_copy;
            const me_vstore = readField(?*anyopaque, me, vo_vstore) orelse break :poll_copy;

            // Check update_ts changed
            const update_ts = readField(usize, me_vstore, vs_update_ts);
            if (update_ts == @as(usize, readField(u32, src, d_synch_ts)))
                break :poll_copy;
            writeField(u32, src, d_synch_ts, @truncate(update_ts));

            // Size mismatch check
            const shm_w = readField(u16, shmpage, sp_w);
            const shm_h = readField(u16, shmpage, sp_h);
            const store_w = readField(usize, me_vstore, vs_w);
            const store_h = readField(usize, me_vstore, vs_h);
            if (@as(usize, shm_w) != store_w or @as(usize, shm_h) != store_h) {
                _ = fsrv_helper_free(state.ptr);
                platform_fsrv_leave();
                return FRV_NOFRAME;
            }

            // Build STEPFRAME event
            const vfc = readField(c_uint, src, o_vfcount);
            var ev = zeroEvent();
            writeEvField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);
            ev[ev_category] = EVENT_TARGET;
            writeEvField(i32, &ev, ev_tgt_ioevs_0_iv, @bitCast(vfc));
            writeField(c_uint, src, o_vfcount, vfc +% 1);

            // memcpy vbufs[0] <- vstore->vinf.text.raw
            const raw_ptr = readField(?[*]u8, me_vstore, vs_vinf_text_raw);
            const s_raw = readField(usize, me_vstore, vs_vinf_text_s_raw);
            const vbuf0 = readField(?[*]u8, src, o_vbufs);
            if (raw_ptr != null and vbuf0 != null and s_raw > 0) {
                @memcpy(vbuf0.?[0..s_raw], raw_ptr.?[0..s_raw]);
            }

            // shmpage->vpts = vstore->vinf.text.vpts
            const text_vpts: u64 = @bitCast(readField(i64, me_vstore, vs_vinf_text_vpts));
            writeField(u64, shmpage, sp_vpts, text_vpts);

            // shmpage->vready = true (1)
            atomicStore32(shmpage, sp_vready, 1);

            // FORCE_SYNCH — full memory barrier
            asm volatile ("" ::: .{ .memory = true });
            _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);

            // Push event (queue if push fails)
            if (platform_fsrv_pushevent(src, &ev) != ARCAN_OK_C5) {
                const n_pend = readField(usize, src, o_n_pending);
                if (n_pend < 4) { // COUNT_OF(pending_queue) = 4
                    const pq_base = ptrAdd(src, o_pending_queue);
                    @memcpy(pq_base[n_pend * ev_size ..][0..ev_size], &ev);
                    writeField(usize, src, o_n_pending, n_pend + 1);
                }
            }
        }

        if (getBitfield(src, fl_byte_autoclock, fl_mask_autoclock) and
            readField(bool, src, o_clock_frame))
        {
            fsrv_helper_autoclock_frame(src);
        }

        if (arcan_event_queuetransfer(
            arcan_event_defaultctx(),
            @as(?*anyopaque, @ptrCast(ptrAdd(src, o_inqueue))),
            readField(c_int, src, o_queue_mask),
            readField(f32, src, o_xfer_sat),
            src,
        ) == -2) {
            _ = fsrv_helper_free(src);
        }
    }

    platform_fsrv_leave();
    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 7. wrapped (C lines 955-990)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_wrapped(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = buf;
    _ = buf_sz;
    _ = width;
    _ = height;
    _ = mode;

    const src: *anyopaque = state.ptr orelse return FRV_NOFRAME;

    // C = src->shm_external (arcan_shmif_cont*)
    const cont = readField(?*anyopaque, src, o_shm_external) orelse return FRV_NOFRAME;
    // C->addr (arcan_shmif_page*)
    const cont_page = readField(?*anyopaque, cont, cont_addr_off) orelse return FRV_NOFRAME;

    if (cmd == FFUNC_CMD_DESTROY) {
        _ = fsrv_helper_free(src);
    } else if (cmd == FFUNC_CMD_POLL) {
        if (atomicLoad32(cont_page, sp_vready) != 0)
            return FRV_GOTFRAME;
    } else if (cmd == FFUNC_CMD_RENDER) {
        // Build stream_meta as byte buffer: buf=C->vidp, stride, w, h
        var sm_bytes: [sm_size]u8 = undefined;
        @memset(&sm_bytes, 0);
        const c_vidp = readField(?*anyopaque, cont, cont_vidp_off);
        const c_w_val = readField(usize, cont, cont_w_off);
        const c_h_val = readField(usize, cont, cont_h_off);
        const c_stride_val = readField(usize, cont, cont_stride_off);

        writeBytesAt(?*anyopaque, &sm_bytes, sm_buf, c_vidp);
        writeBytesAt(c_uint, &sm_bytes, sm_stride_off, @truncate(c_stride_val));
        writeBytesAt(c_uint, &sm_bytes, sm_w, @truncate(c_w_val));
        writeBytesAt(c_uint, &sm_bytes, sm_h, @truncate(c_h_val));
        writeBytesAt(c_int, &sm_bytes, sm_type, STREAM_RAW_DIRECT_SYNCHRONOUS);

        const vid = readField(i64, src, o_vid);
        const vobj = arcan_video_getobject(vid) orelse return FRV_NOFRAME;
        const store = getDstStore(vobj) orelse return FRV_NOFRAME;

        var stream: StreamMeta = @bitCast(sm_bytes);
        stream = agp_stream_prepare(store, stream, STREAM_RAW_DIRECT_SYNCHRONOUS);
        agp_stream_commit(store, stream);
        agp_stream_release(store, stream);

        atomicStore32(cont_page, sp_vready, 0);
    } else if (cmd == FFUNC_CMD_TICK) {
        // Poll the shmif connection until drained or error
        var ev_bytes: [ev_size]u8 = undefined;
        @memset(&ev_bytes, 0);
        while (arcan_shmif_poll(cont, &ev_bytes) > 0) {
            @memset(&ev_bytes, 0);
        }
    } else if (cmd == FFUNC_CMD_ADOPT) {
        fsrv_helper_default_adoph(src, srcid);
    }

    return FRV_NOFRAME;
}

// ════════════════════════════════════════════════════════════════════════════
// 8. avfeedframe (C lines 993-1109)
// ════════════════════════════════════════════════════════════════════════════

export fn fsrv_helper_avfeedframe(
    cmd: c_int,
    buf: ?[*]u32,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: i64,
) callconv(.c) c_int {
    _ = width;
    _ = height;
    _ = mode;

    const src: *anyopaque = state.ptr orelse return FRV_NOFRAME;
    var rv: c_int = FRV_NOFRAME;

    if (!fsrv_helper_tramp_enter(src))
        return FRV_NOFRAME;

    if (cmd == FFUNC_CMD_DESTROY) {
        _ = fsrv_helper_free(src);
    } else if (cmd == FFUNC_CMD_ADOPT) {
        fsrv_helper_default_adoph(src, srcid);
    } else if (cmd == FFUNC_CMD_TICK) {
        if (!fsrv_helper_control_chld(src)) {
            platform_fsrv_leave();
            return rv;
        }
        _ = arcan_event_queuetransfer(
            arcan_event_defaultctx(),
            @as(?*anyopaque, @ptrCast(ptrAdd(src, o_inqueue))),
            readField(c_int, src, o_queue_mask),
            0.5,
            src,
        );
    } else if (cmd == FFUNC_CMD_POLL) {
        if (readField(?*anyopaque, src, o_shm_ptr)) |shm| {
            if (atomicLoad32(shm, sp_vready) != 0)
                rv = FRV_GOTFRAME;
        }
    } else if (cmd == FFUNC_CMD_READBACK or cmd == FFUNC_CMD_READBACK_HANDLE) {
        const shmpage = readField(?*anyopaque, src, o_shm_ptr);
        if (shmpage == null) {
            // No shm page — switch to NULL feed
            const emptys = vfunc_state{ .tag = 0, .ptr = null };
            _ = arcan_video_alterfeed(readField(i64, src, o_vid), FFUNC_ID_NULL, emptys);
            rv = FRV_NOFRAME;
            platform_fsrv_leave();
            return rv;
        }

        const shm = shmpage.?;
        if (atomicLoad32(shm, sp_vready) == 0) {
            // Build STEPFRAME event
            var ev = zeroEvent();
            writeEvField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);
            ev[ev_category] = EVENT_TARGET;

            // Copy audio buffer if ofs_audb > 0
            const ofs_audb_val = readField(i64, src, o_ofs_audb);
            if (ofs_audb_val > 0) {
                const ofs: usize = @intCast(ofs_audb_val);
                const audb_ptr = readField(?[*]u8, src, o_audb);
                const abuf0 = readField(?[*]u8, src, o_abufs);
                if (audb_ptr != null and abuf0 != null) {
                    @memcpy(abuf0.?[0..ofs], audb_ptr.?[0..ofs]);
                }
                // shmpage->abufused[0] = ofs (u16)
                const abuf_dst = ptrAdd(shm, sp_abufused);
                const ofs_u16: u16 = @truncate(ofs);
                const ofs_bytes: *const [2]u8 = @ptrCast(&ofs_u16);
                @memcpy(abuf_dst[0..2], ofs_bytes);
                writeField(i64, src, o_ofs_audb, 0);
            }

            // Build dirty region (arcan_shmif_region = 8 bytes: x1,x2,y1,y2 as i16)
            var reg: [8]u8 = undefined;
            @memset(&reg, 0);
            if (readField(bool, src, d_region_valid)) {
                // Copy from desc.region (8 bytes starting at d_region_x1)
                const region_ptr = ptrAdd(src, d_region_x1);
                @memcpy(&reg, region_ptr[0..8]);
            } else {
                // Default: x1=0, x2=desc.width, y1=0, y2=desc.height
                const dw = readField(u16, src, d_width);
                const dh = readField(u16, src, d_height);
                const x2 = @as(i16, @intCast(dw));
                const y2 = @as(i16, @intCast(dh));
                const x2p: *const [2]u8 = @ptrCast(&x2);
                const y2p: *const [2]u8 = @ptrCast(&y2);
                reg[2] = x2p[0];
                reg[3] = x2p[1]; // x2 at bytes 2-3
                reg[6] = y2p[0];
                reg[7] = y2p[1]; // y2 at bytes 6-7
            }

            // atomic_store vpts and dirty
            writeField(u64, shm, sp_vpts, arcan_timemillis());
            const dirty_dst = ptrAdd(shm, sp_dirty);
            @memcpy(dirty_dst[0..8], &reg);

            if (cmd == FFUNC_CMD_READBACK) {
                // memcpy vbufs[0] <- buf
                const vbuf0 = readField(?[*]u8, src, o_vbufs);
                if (buf != null and vbuf0 != null and buf_sz > 0) {
                    const src_bytes: [*]const u8 = @ptrCast(buf.?);
                    @memcpy(vbuf0.?[0..buf_sz], src_bytes[0..buf_sz]);
                }
                const vfc = readField(c_uint, src, o_vfcount);
                writeEvField(i32, &ev, ev_tgt_ioevs_0_iv, @bitCast(vfc));
                writeField(c_uint, src, o_vfcount, vfc +% 1);

                atomicStore32(shm, sp_vready, 1);
                platform_fsrv_signal(src, 2);
                _ = platform_fsrv_pushevent(src, &ev);
            } else {
                // READBACK_HANDLE path
                writeEvField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_DEVICE_NODE);
                writeEvField(i32, &ev, ev_tgt_ioevs_2_uiv, 0);
                writeEvField(i32, &ev, ev_tgt_ioevs_3_iv, 0);

                const vid = readField(i64, src, o_vid);
                const vobj = arcan_video_getobject(vid) orelse {
                    arcan_warning("Couldn't find rendertarget for frameserver, revert shm");
                    platform_fsrv_leave();
                    return rv;
                };

                const rt = arcan_vint_findrt(vobj) orelse {
                    arcan_warning("Couldn't find rendertarget for frameserver, revert shm");
                    platform_fsrv_leave();
                    return rv;
                };

                var swap: bool = false;
                const art = readField(?*anyopaque, rt, rt_art) orelse {
                    platform_fsrv_leave();
                    return rv;
                };
                const vs = agp_rendertarget_swap(art, &swap);
                if (!swap) {
                    platform_fsrv_leave();
                    return rv;
                }

                if (vs) |vs_ptr| {
                    // agp_buffer_plane[4] — sizeof(agp_buffer_plane) = 56, total 224
                    var planes: [224]u8 = undefined;
                    @memset(&planes, 0);
                    const np = platform_video_export_vstore(vs_ptr, @ptrCast(&planes), 4);
                    if (np != 1) {
                        arcan_warning("Platform rejected export, revert shm");
                        writeField(bool, rt, rt_hwreadback, false);
                    } else {
                        // planes[0].fd is c_int at offset 0
                        const fd = readBytesAt(c_int, &planes, 0);
                        const pfd_rc = platform_fsrv_pushfd(src, &ev, fd);
                        // fossil 7c2828e9bd: arcan-net bridge clients can't
                        // import DMA-BUF (kernel SCM_RIGHTS rejects with
                        // EACCES — different graphics domain on listener
                        // side / no GPU access in the helper_cl grandchild).
                        // Existing path already handles "platform rejected
                        // export"; treat a failed pushfd the same way —
                        // disable HW readback for this rendertarget so the
                        // next frame uses the SHM fallback.  Without this
                        // every frame retries the doomed DMA-BUF push and
                        // tears the bridge down within a few frames.
                        if (pfd_rc != ARCAN_OK) {
                            arcan_warning("pushfd failed, revert to shm readback\n");
                            writeField(bool, rt, rt_hwreadback, false);
                        }
                    }
                    // Close all returned plane fds and fences
                    if (np > 0) {
                        var i: usize = 0;
                        while (i < np) : (i += 1) {
                            const off = i * 56; // sizeof(agp_buffer_plane)
                            const fd_val = readBytesAt(c_int, &planes, off); // .fd at +0
                            const fence_val = readBytesAt(c_int, &planes, off + 4); // .fence at +4
                            if (fd_val > 0) _ = close(fd_val);
                            if (fence_val > 0) _ = close(fence_val);
                        }
                    }
                }
            }

            if (readField(bool, src, d_callback_framestate)) {
                emit_deliveredframe(src, 0, readField(u64, src, d_framecount));
                const fcount = readField(u64, src, d_framecount);
                writeField(u64, src, d_framecount, fcount +% 1);
            }
        } else {
            // vready != 0 — frame dropped
            if (readField(bool, src, d_callback_framestate)) {
                emit_droppedframe(src, 0, readField(u64, src, d_dropcount));
                const dc = readField(u64, src, d_dropcount);
                writeField(u64, src, d_dropcount, dc +% 1);
            }
        }
    }

    platform_fsrv_leave();
    return rv;
}
// Chunk 6: push_buffer + tick_control + releaselock
//
// Pure Zig port of fsrv_helper_push_buffer, fsrv_helper_releaselock,
// and fsrv_helper_tick_control from arcan_frameserver_helpers.c.
// Uses byte-offset arithmetic for opaque C structs.

// FORCE_SYNCH dummy for hardware memory barrier

var force_synch_dummy: u32 = 0;

// Chunk 6 unique constants

// drm_hdr_meta within agp_vstore (absolute offsets from vstore base)
const vs_hdr_drm_eotf: usize = 204; // c_int (4 bytes)
const vs_hdr_drm_rx: usize = 208; // f32
const vs_hdr_drm_ry: usize = 212; // f32
const vs_hdr_drm_gx: usize = 216; // f32
const vs_hdr_drm_gy: usize = 220; // f32
const vs_hdr_drm_bx: usize = 224; // f32
const vs_hdr_drm_by: usize = 228; // f32
const vs_hdr_drm_wpx: usize = 232; // f32
const vs_hdr_drm_wpy: usize = 236; // f32
const vs_hdr_drm_cll: usize = 248; // f32
const vs_hdr_drm_fll: usize = 252; // f32

// arcan_shmif_region offsets (4 x u16)
const sr_x1: usize = 0; // u16
const sr_x2: usize = 2; // u16
const sr_y1: usize = 4; // u16
const sr_y2: usize = 6; // u16

// shmif_hdr offsets (source side, u16 color primaries)
const shdr_drm_eotf: usize = 4; // c_int (4 bytes)
const shdr_drm_rx: usize = 8; // u16
const shdr_drm_ry: usize = 10; // u16
const shdr_drm_gx: usize = 12; // u16
const shdr_drm_gy: usize = 14; // u16
const shdr_drm_bx: usize = 16; // u16
const shdr_drm_by: usize = 18; // u16
const shdr_drm_wpx: usize = 20; // u16
const shdr_drm_wpy: usize = 22; // u16
const shdr_drm_cll_max: usize = 28; // u16
const shdr_drm_fll_max: usize = 30; // u16

// RHINT constants unique to chunk 6
const SHMIF_RHINT_ORIGO_LL: c_int = 1;
const SHMIF_RHINT_IGNORE_ALPHA: c_int = 4;
const SHMIF_RHINT_EMPTY: u8 = 64;
const SHMIF_RHINT_TPACK: c_int = 128;
const SHMIF_META_CM: c_uint = 2;

const GL_STORE_PIXEL_FORMAT: c_uint = 0x1908;
const GL_NOALPHA_PIXEL_FORMAT: c_uint = 0x1907;

// stream_type enum values
const STREAM_RAW_DIRECT: c_uint = 1;
const STREAM_RAW_DIRECT_COPY: c_uint = 2;
const STREAM_RAW_DIRECT_SYNCHRONOUS: c_uint = 3;
const STREAM_HANDLE: c_uint = 5;

// event struct sizes
const ev_sizeof: usize = 128;

// buffer plane sizeof
const bp_sizeof: usize = 56;

// ABI-compatible C struct wrappers
// stream_meta (240 bytes) and tui_constraints (32 bytes) are passed
// by value across the C ABI. On aarch64, structs > 16 bytes are passed
// indirectly (hidden pointer), so a byte-array of the right size works.

const StreamMeta = extern struct {
    data: [240]u8 = [_]u8{0} ** 240,
};

const TuiConstraints = extern struct {
    data: [32]u8 = [_]u8{0} ** 32,
};

// tui_cbcfg: 1 tag pointer + 27 function pointers = 28 × 8 = 224 bytes
const tui_cbcfg_sizeof: usize = 224;
const TuiCbcfg = extern struct {
    data: [224]u8 = [_]u8{0} ** 224,
};

// stream_meta field accessors

const sm_buf: usize = 0; // ?*anyopaque
const sm_x1: usize = 12; // u32
const sm_y1: usize = 16; // u32
const sm_w: usize = 20; // u32
const sm_h: usize = 24; // u32
const sm_used: usize = 224; // usize
const sm_state: usize = 236; // bool

fn smSetBuf(sm: *StreamMeta, v: ?*anyopaque) void {
    const p: *align(1) ?*anyopaque = @ptrCast(&sm.data[sm_buf]);
    p.* = v;
}

fn smGetBuf(sm: *const StreamMeta) ?*anyopaque {
    const p: *align(1) const ?*anyopaque = @ptrCast(&sm.data[sm_buf]);
    return p.*;
}

fn smSetX1(sm: *StreamMeta, v: u32) void {
    const p: *align(1) u32 = @ptrCast(&sm.data[sm_x1]);
    p.* = v;
}

fn smSetY1(sm: *StreamMeta, v: u32) void {
    const p: *align(1) u32 = @ptrCast(&sm.data[sm_y1]);
    p.* = v;
}

fn smSetW(sm: *StreamMeta, v: u32) void {
    const p: *align(1) u32 = @ptrCast(&sm.data[sm_w]);
    p.* = v;
}

fn smSetH(sm: *StreamMeta, v: u32) void {
    const p: *align(1) u32 = @ptrCast(&sm.data[sm_h]);
    p.* = v;
}

fn smSetStride(sm: *StreamMeta, v: u32) void {
    const p: *align(1) u32 = @ptrCast(&sm.data[sm_stride_off]);
    p.* = v;
}

fn smGetX1(sm: *const StreamMeta) u32 {
    const p: *align(1) const u32 = @ptrCast(&sm.data[sm_x1]);
    return p.*;
}

fn smGetY1(sm: *const StreamMeta) u32 {
    const p: *align(1) const u32 = @ptrCast(&sm.data[sm_y1]);
    return p.*;
}

fn smGetW(sm: *const StreamMeta) u32 {
    const p: *align(1) const u32 = @ptrCast(&sm.data[sm_w]);
    return p.*;
}

fn smGetH(sm: *const StreamMeta) u32 {
    const p: *align(1) const u32 = @ptrCast(&sm.data[sm_h]);
    return p.*;
}

fn smGetState(sm: *const StreamMeta) bool {
    return sm.data[sm_state] != 0;
}

fn smGetUsed(sm: *const StreamMeta) usize {
    const p: *align(1) const usize = @ptrCast(&sm.data[sm_used]);
    return p.*;
}

fn smSetUsed(sm: *StreamMeta, v: usize) void {
    const p: *align(1) usize = @ptrCast(&sm.data[sm_used]);
    p.* = v;
}

// tui_constraints field accessors

const tc_max_rows: usize = 8;
const tc_max_cols: usize = 12;

fn tcSetMaxRows(tc: *TuiConstraints, v: c_int) void {
    const p: *align(1) c_int = @ptrCast(&tc.data[tc_max_rows]);
    p.* = v;
}

fn tcSetMaxCols(tc: *TuiConstraints, v: c_int) void {
    const p: *align(1) c_int = @ptrCast(&tc.data[tc_max_cols]);
    p.* = v;
}

// Chunk 6 unique extern C functions

// These pass/return StreamMeta by value (240 bytes, passed indirectly on aarch64)
extern fn agp_stream_prepare(store: *anyopaque, base: StreamMeta, stream_type: c_uint) StreamMeta;
extern fn agp_stream_commit(store: *anyopaque, meta: StreamMeta) void;
extern fn agp_stream_release(store: *anyopaque, meta: StreamMeta) void;

extern fn agp_vstore_copyreg(
    src_store: *anyopaque,
    dst_store: *anyopaque,
    x1: usize,
    y1: usize,
    x2: usize,
    y2: usize,
) void;

// agp_region is 4 x usize = 32 bytes, passed by value
const AgpRegion = extern struct { x1: usize, y1: usize, x2: usize, y2: usize };
extern fn platform_video_invalidate_map(vs: *anyopaque, region: AgpRegion) void;

extern fn arcan_tui_setup(
    con: ?*anyopaque,
    parent: ?*anyopaque,
    cfg: *const TuiCbcfg,
    cfg_sz: usize,
) ?*anyopaque;

// tui_constraints passed by value (32 bytes)
extern fn arcan_tui_wndhint(wnd: ?*anyopaque, par: ?*anyopaque, cons: TuiConstraints) void;

extern fn arcan_tui_tunpack(
    tui: ?*anyopaque,
    buf: [*]u8,
    buf_sz: usize,
    x: usize,
    y: usize,
    w: usize,
    h: usize,
) bool;
extern fn arcan_renderfun_fontraster(group: ?*anyopaque) ?*anyopaque;
extern fn tui_raster_renderagp(
    ctx: ?*anyopaque,
    dst: *anyopaque,
    buf: [*]u8,
    buf_sz: usize,
    out: *StreamMeta,
) c_int;

extern fn tui_raster_gpu_flush(ctx: ?*anyopaque, out_count: *u32) ?*const anyopaque;
extern fn agp_slug_draw_instances(instances: ?*const anyopaque, count: u32, tex_id: u32) void;
extern fn vk_env_texture_matches_size(tex_id: u32, w: u32, h: u32) bool;

extern fn poll(fds: *anyopaque, nfds: usize, timeout: c_int) c_int;

// helper: build a zeroed event

fn zeroEventBuf(buf: *[ev_sizeof]u8) void {
    @memset(buf, 0);
}

fn eventSetCategory(buf: *[ev_sizeof]u8, cat: u8) void {
    buf[ev_category] = cat;
}

fn eventWriteField(comptime T: type, buf: *[ev_sizeof]u8, off: usize, val: T) void {
    const p: *align(1) T = @ptrCast(&buf[off]);
    p.* = val;
}

// helper: read from arcan_shmif_region (opaque, 8 bytes)

fn regionGetX1(dirty: *anyopaque) u16 {
    return readField(u16, dirty, sr_x1);
}
fn regionGetX2(dirty: *anyopaque) u16 {
    return readField(u16, dirty, sr_x2);
}
fn regionGetY1(dirty: *anyopaque) u16 {
    return readField(u16, dirty, sr_y1);
}
fn regionGetY2(dirty: *anyopaque) u16 {
    return readField(u16, dirty, sr_y2);
}

// helper: copy HDR metadata from shmif_hdr to agp_vstore
// shmif_hdr.drm has u16 color primaries; drm_hdr_meta has float fields.
// The C code does implicit u16 → float promotion via designated initializer.

fn copyHdrMetadata(src_fsrv: *anyopaque, store: *anyopaque) void {
    const hdr_ptr = readField(?*anyopaque, src_fsrv, d_aext_hdr) orelse return;
    writeField(c_int, store, vs_hdr_model, 1);
    // eotf: int → int (same type)
    writeField(c_int, store, vs_hdr_drm_eotf, readField(c_int, hdr_ptr, shdr_drm_eotf));
    // u16 → float conversions for color primaries
    writeField(f32, store, vs_hdr_drm_rx, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_rx)));
    writeField(f32, store, vs_hdr_drm_ry, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_ry)));
    writeField(f32, store, vs_hdr_drm_gx, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_gx)));
    writeField(f32, store, vs_hdr_drm_gy, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_gy)));
    writeField(f32, store, vs_hdr_drm_bx, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_bx)));
    writeField(f32, store, vs_hdr_drm_by, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_by)));
    writeField(f32, store, vs_hdr_drm_wpx, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_wpx)));
    writeField(f32, store, vs_hdr_drm_wpy, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_wpy)));
    writeField(f32, store, vs_hdr_drm_cll, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_cll_max)));
    writeField(f32, store, vs_hdr_drm_fll, @floatFromInt(readField(u16, hdr_ptr, shdr_drm_fll_max)));
}

// ═══════════════════════════════════════════════════════════════════
// push_buffer
// ═══════════════════════════════════════════════════════════════════

export fn fsrv_helper_push_buffer(
    src: *anyopaque,
    store: *anyopaque,
    dirty: ?*anyopaque,
) callconv(.c) c_int {
    var stream = StreamMeta{};
    var is_explicit = getBitfield(src, fl_byte_explicit, fl_mask_explicit);
    var rv: c_int = 1;

    const page = readField(?*anyopaque, src, o_shm_ptr) orelse return 0;

    // atomic_load vready and vpending
    const raw_vready: i32 = @bitCast(atomicLoad(u32, page, pg_vready));
    const raw_vpending: u32 = atomicLoad(u32, page, pg_vpending);

    // push_buffer debug logging removed
    const vmask: u32 = ~raw_vpending;

    // Clamp vready to valid buffer index
    // C: vready = (vready <= 0 || vready > src->vbuf_cnt) ? 0 : vready - 1;
    const vbuf_cnt = readField(usize, src, o_vbuf_cnt);
    const vready_idx: usize = blk: {
        if (raw_vready <= 0) break :blk 0;
        const vr: usize = @intCast(raw_vready);
        if (vr > vbuf_cnt) break :blk 0;
        break :blk vr - 1;
    };

    const buf: ?*anyopaque = readField(?*anyopaque, src, o_vbufs + vready_idx * 8);

    // SHMIF_RHINT_EMPTY: skip all processing, go to commit_mask
    const page_hints: u8 = atomicLoad(u8, page, pg_hints);
    if (page_hints & SHMIF_RHINT_EMPTY != 0) {
        _ = atomicFetchAnd(u32, page, pg_vpending, vmask);
        return rv;
    }

    // HDR metadata copy
    const aext_hdr = readField(?*anyopaque, src, d_aext_hdr);
    if (aext_hdr != null and !getBitfield(src, fl_byte_block_hdr_meta, fl_mask_block_hdr_meta)) {
        copyHdrMetadata(src, store);
    }

    // Check for resize
    const desc_w = readField(u16, src, d_width);
    const desc_h = readField(u16, src, d_height);
    const store_w = readField(usize, store, vs_w);
    const store_h = readField(usize, store, vs_h);
    const desc_hints = readField(c_int, src, d_hints);
    const desc_pending_hints = readField(c_int, src, d_pending_hints);
    const desc_rz_flag = readField(bool, src, d_rz_flag);

    if (@as(usize, desc_w) != store_w or
        @as(usize, desc_h) != store_h or
        desc_hints != desc_pending_hints or desc_rz_flag)
    {
        // Update hints
        writeField(c_int, src, d_hints, desc_pending_hints);

        // Build EVENT_FSRV_RESIZED event
        var rezev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
        eventSetCategory(&rezev, EVENT_FSRV);
        eventWriteField(u32, &rezev, ev_fsrv_kind, EVENT_FSRV_RESIZED);
        eventWriteField(usize, &rezev, ev_fsrv_width, @as(usize, desc_w));
        eventWriteField(usize, &rezev, ev_fsrv_height, @as(usize, desc_h));
        eventWriteField(i64, &rezev, ev_fsrv_video, readField(i64, src, o_vid));
        eventWriteField(i32, &rezev, ev_fsrv_audio, readField(i32, src, o_aid));
        eventWriteField(isize, &rezev, ev_fsrv_otag, readField(isize, src, o_tag));
        const cur_hints = readField(c_int, src, d_hints);
        const fmt_fl: i8 = @truncate(
            (cur_hints & SHMIF_RHINT_ORIGO_LL) | (cur_hints & SHMIF_RHINT_TPACK),
        );
        eventWriteField(i8, &rezev, ev_fsrv_fmt_fl, fmt_fl);

        // TPACK: ensure tui context exists, apply wndhint
        if (cur_hints & SHMIF_RHINT_TPACK != 0) {
            const tui_ptr = readField(?*anyopaque, store, vs_vinf_text_tpack_tui);
            if (tui_ptr == null) {
                const cbcfg = TuiCbcfg{};
                const new_tui = arcan_tui_setup(null, null, &cbcfg, tui_cbcfg_sizeof);
                writeField(?*anyopaque, store, vs_vinf_text_tpack_tui, new_tui);
            }
            const final_tui = readField(?*anyopaque, store, vs_vinf_text_tpack_tui);
            var cons = TuiConstraints{};
            tcSetMaxRows(&cons, @as(c_int, @intCast(readField(usize, src, d_rows))));
            tcSetMaxCols(&cons, @as(c_int, @intCast(readField(usize, src, d_cols))));
            arcan_tui_wndhint(final_tui, null, cons);
        }

        // rz_ack handling
        if (getBitfield(src, fl_byte_rz_ack, fl_mask_rz_ack)) {
            const rz_known = readField(c_int, src, o_rz_known);
            if (rz_known == 0) {
                _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&rezev));
                writeField(c_int, src, o_rz_known, 1);
                return 0;
            } else if (rz_known == 1) {
                return 0;
            } else {
                writeField(c_int, src, o_rz_known, 0);
            }
        } else {
            _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&rezev));
        }

        // Update d_fmt based on alpha hints
        const ignore_alpha = (cur_hints & SHMIF_RHINT_IGNORE_ALPHA) != 0;
        const no_alpha = getBitfield(src, fl_byte_no_alpha_copy, fl_mask_no_alpha_copy);
        const d_fmt_val: c_uint = if (ignore_alpha or no_alpha) GL_NOALPHA_PIXEL_FORMAT else GL_STORE_PIXEL_FORMAT;
        writeField(c_uint, store, vs_vinf_text_d_fmt, d_fmt_val);

        // Resize the video feed
        arcan_video_resizefeed(readField(i64, src, o_vid), desc_w, desc_h);

        writeField(bool, src, d_rz_flag, false);
        is_explicit = true;
    }

    // TPACK path
    const cur_hints2 = readField(c_int, src, d_hints);
    if (cur_hints2 & SHMIF_RHINT_TPACK != 0) {
        tpack_blk: {
            // Ensure font group exists — use system default font and the
            // frameserver's density/size so the raster cell metrics match what
            // the terminal client computed from target_fonthint/displayhint.
            if (readField(?*anyopaque, src, d_text_group) == null) {
                var def_fd: c_int = BADFD;
                arcan_video_fontdefaults(&def_fd, null, null);
                var fds: [4]c_int = .{
                    if (def_fd != BADFD) dup(def_fd) else BADFD,
                    BADFD,
                    BADFD,
                    BADFD,
                };
                const grp = arcan_renderfun_fontgroup(&fds, 4);
                writeField(?*anyopaque, src, d_text_group, grp);
                var cellw: usize = 0;
                var cellh: usize = 0;
                const szmm = readField(f32, src, d_text_szmm);
                const ppcm = readField(f32, src, d_hint_ppcm);
                arcan_renderfun_fontgroup_size(grp, szmm, ppcm, &cellw, &cellh);
                writeField(usize, src, d_text_cellw, cellw);
                writeField(usize, src, d_text_cellh, cellh);
            }

            const raster = arcan_renderfun_fontraster(readField(?*anyopaque, src, d_text_group));

            const buf_sz: usize = @as(usize, desc_w) * @as(usize, desc_h) * 4;
            const buf_ptr: [*]u8 = @ptrCast(buf orelse {
                rv = 0;
                break :tpack_blk;
            });
            const tui_ctx = readField(?*anyopaque, store, vs_vinf_text_tpack_tui);
            _ = arcan_tui_tunpack(
                tui_ctx,
                buf_ptr,
                buf_sz,
                0,
                0,
                readField(usize, src, d_cols),
                readField(usize, src, d_rows),
            );

            // tui_raster_renderagp returns -1 on failure
            const rr = tui_raster_renderagp(
                raster,
                store,
                buf_ptr,
                @as(usize, desc_w) * @as(usize, desc_h) * 4,
                &stream,
            );
            if (rr == -1) {
                rv = 0;
                break :tpack_blk;
            }

            // Update desc.region from stream output
            writeField(i16, src, d_region_x1, @as(i16, @intCast(smGetX1(&stream))));
            writeField(i16, src, d_region_y1, @as(i16, @intCast(smGetY1(&stream))));
            writeField(i16, src, d_region_x2, @as(i16, @intCast(smGetX1(&stream) + smGetW(&stream))));
            writeField(i16, src, d_region_y2, @as(i16, @intCast(smGetY1(&stream) + smGetH(&stream))));
            writeField(bool, src, d_region_valid, true);

            if (smGetBuf(&stream) == null) {
                arcan_warning("client-tpack() - couldn't raster buffer\n");
                rv = 0;
                break :tpack_blk;
            }

            // dst_copy handling
            const dst_copy = readField(?*anyopaque, store, vs_dst_copy);
            if (dst_copy) |dc| {
                const reg = AgpRegion{
                    .x1 = @as(usize, smGetX1(&stream)),
                    .y1 = @as(usize, smGetY1(&stream)),
                    .x2 = @as(usize, smGetX1(&stream) + smGetW(&stream)),
                    .y2 = @as(usize, smGetY1(&stream) + smGetH(&stream)),
                };
                agp_vstore_copyreg(store, dc, reg.x1, reg.y1, reg.x2, reg.y2);
                platform_video_invalidate_map(dc, reg);
            }

            // GPU renders all cell content. Ensure texture exists at correct size.
            {
                var gpu_count: u32 = 0;
                const instances = tui_raster_gpu_flush(raster, &gpu_count);
                const store_bytes: [*]const u8 = @ptrCast(store);
                var tex_id = @as(*align(1) const u32, @ptrCast(store_bytes + 16)).*;
                const sw = readField(usize, store, vs_w);
                const sh = readField(usize, store, vs_h);
                if (tex_id == 0 or !vk_env_texture_matches_size(tex_id, @intCast(sw), @intCast(sh))) {
                    // Texture missing or wrong size (after resize) — recreate
                    stream = agp_stream_prepare(store, stream, STREAM_RAW_DIRECT);
                    agp_stream_commit(store, stream);
                    tex_id = @as(*align(1) const u32, @ptrCast(store_bytes + 16)).*;
                }
                agp_slug_draw_instances(if (instances) |i| @as(?*const anyopaque, @ptrCast(i)) else null, gpu_count, tex_id);
            }

            // Validate sizes
            const desc_height_check = readField(u16, src, d_height);
            const text_cellh = readField(usize, src, d_text_cellh);
            if (desc_height_check == 0 or text_cellh == 0) {
                rv = 0;
                break :tpack_blk;
            }

            const n_rows = readField(usize, src, d_rows);
            const n_cols = readField(usize, src, d_cols);
            const n_cells = n_rows * n_cols;

            if (readField(usize, src, d_text_cellw) == 0) {
                const cols_val = readField(usize, src, d_cols);
                const rows_val = readField(usize, src, d_rows);
                if (cols_val > 0 and rows_val > 0) {
                    writeField(usize, src, d_text_cellw, @as(usize, desc_w) / cols_val);
                    writeField(usize, src, d_text_cellh, @as(usize, desc_h) / rows_val);
                }
            }

            // memset(buf, cellw, n_cells)
            const cellw_val = readField(usize, src, d_text_cellw);
            _ = memset(buf, @as(c_int, @intCast(cellw_val & 0xff)), n_cells);
        }
        // commit_mask and return
        _ = atomicFetchAnd(u32, page, pg_vpending, vmask);
        return rv;
    }

    // Handle pending plane transfers (vstream.pending_used > 0)
    const pending_used = readField(usize, src, o_vstream_pending_used);
    if (pending_used > 0) {
        var failev = readField(bool, src, o_vstream_dead);

        if (!failev) {
            // Check fence on first pending plane
            const fence_val = readField(c_int, src, o_vstream_pending + bp_fence);
            if (fence_val > 0) {
                // poll the fence fd
                var pfd = extern struct {
                    fd: c_int,
                    events: c_short,
                    revents: c_short,
                }{
                    .fd = fence_val,
                    .events = 1, // POLLIN
                    .revents = 0,
                };
                const poll_ret = poll(@ptrCast(&pfd), 1, 0);
                if (poll_ret == -1) {
                    return 0;
                }
                _ = close(fence_val);
                writeField(c_int, src, o_vstream_pending + bp_fence, -1);
            }

            // Copy planes into stream.data (union overlaps buf/planes at offset 0)
            const plane_bytes = bp_sizeof * pending_used;
            _ = memcpy(@ptrCast(&stream.data), @ptrCast(ptrAdd(src, o_vstream_pending)), plane_bytes);
            smSetUsed(&stream, pending_used);

            // agp_stream_prepare with STREAM_HANDLE
            stream = agp_stream_prepare(store, stream, STREAM_HANDLE);
            writeField(usize, src, o_vstream_pending_used, 0);

            failev = !smGetState(&stream);
        }

        if (failev) {
            // Send TARGET_COMMAND_BUFFER_FAIL event
            var ev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
            eventSetCategory(&ev, EVENT_TARGET);
            eventWriteField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_BUFFER_FAIL);
            const outqueue_ptr: *anyopaque = @ptrCast(ptrAdd(src, o_outqueue));
            _ = arcan_event_enqueue(outqueue_ptr, @ptrCast(&ev));
            fsrv_helper_close_bufferqueues(src, true, true);
            writeField(bool, src, o_vstream_dead, true);
        } else {
            agp_stream_commit(store, stream);
        }

        // commit_mask and return
        _ = atomicFetchAnd(u32, page, pg_vpending, vmask);
        return rv;
    }

    // Normal pixel copy path
    smSetBuf(&stream, buf);
    // Set stride from shmif cont (without this, stride=0 → fallback to w*4 which is wrong
    // if the shmif buffer has page-aligned stride)
    {
        const cont_ptr = readField(?*anyopaque, src, o_shm_external);
        if (cont_ptr) |cp| {
            const c_stride_val = readField(usize, @ptrCast(cp), cont_stride_off);
            smSetStride(&stream, @truncate(c_stride_val));
        }
    }
    if (dirty) |d| {
        smSetX1(&stream, @as(u32, regionGetX1(d)));
        smSetY1(&stream, @as(u32, regionGetY1(d)));
        smSetW(&stream, @as(u32, regionGetX2(d)) -% @as(u32, regionGetX1(d)));
        smSetH(&stream, @as(u32, regionGetY2(d)) -% @as(u32, regionGetY1(d)));
        // Copy dirty region into desc.region
        writeField(i16, src, d_region_x1, @as(i16, @bitCast(regionGetX1(d))));
        writeField(i16, src, d_region_x2, @as(i16, @bitCast(regionGetX2(d))));
        writeField(i16, src, d_region_y1, @as(i16, @bitCast(regionGetY1(d))));
        writeField(i16, src, d_region_y2, @as(i16, @bitCast(regionGetY2(d))));
        writeField(bool, src, d_region_valid, true);
    } else {
        smSetW(&stream, @as(u32, @intCast(store_w)));
        smSetH(&stream, @as(u32, @intCast(store_h)));
        writeField(bool, src, d_region_valid, false);
    }

    // Choose stream type
    const stype: c_uint = if (is_explicit)
        STREAM_RAW_DIRECT_SYNCHRONOUS
    else if (getBitfield(src, fl_byte_local_copy, fl_mask_local_copy))
        STREAM_RAW_DIRECT_COPY
    else
        STREAM_RAW_DIRECT;

    stream = agp_stream_prepare(store, stream, stype);
    agp_stream_commit(store, stream);

    // commit_mask
    _ = atomicFetchAnd(u32, page, pg_vpending, vmask);
    return rv;
}

// ═══════════════════════════════════════════════════════════════════
// releaselock
// ═══════════════════════════════════════════════════════════════════

export fn fsrv_helper_releaselock(tgt: *anyopaque) callconv(.c) c_int {
    // Check flags.release_pending
    if (!getBitfield(tgt, fl_byte_release_pending, fl_mask_release_pending))
        return 0;

    const page = readField(?*anyopaque, tgt, o_shm_ptr) orelse return 0;

    // Clear release_pending
    setBitfield(tgt, fl_byte_release_pending, fl_mask_release_pending, false);

    // TRAMP_GUARD(0, tgt)
    if (!fsrv_helper_tramp_enter(tgt))
        return 0;

    // atomic_store vready = 0
    atomicStore(u32, page, pg_vready, 0);

    // arcan_frameserver_signal(tgt, SYNC_VIDEO)
    fsrv_helper_signal(tgt, SYNC_VIDEO);

    // SHMIF_RHINT_VSIGNAL_EV: send STEPFRAME event
    const hints = readField(c_int, tgt, d_hints);
    if (hints & SHMIF_RHINT_VSIGNAL_EV != 0) {
        const vid = readField(i64, tgt, o_vid);
        const vobj = arcan_video_getobject(vid);

        var ev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
        eventSetCategory(&ev, EVENT_TARGET);
        eventWriteField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);
        eventWriteField(i32, &ev, ev_tgt_ioevs_0_iv, 1);
        eventWriteField(i32, &ev, ev_tgt_ioevs_1_iv, 0);
        // vobj->owner->msc
        const msc_val: u32 = if (vobj) |vo| blk: {
            const owner = readField(?*anyopaque, vo, vo_owner) orelse break :blk 0;
            break :blk readField(u32, owner, rt_msc);
        } else 0;
        eventWriteField(u32, &ev, ev_tgt_ioevs_2_uiv, msc_val);
        _ = platform_fsrv_pushevent(tgt, @ptrCast(&ev));
    }

    platform_fsrv_leave();
    return 0;
}

// ═══════════════════════════════════════════════════════════════════
// tick_control
// ═══════════════════════════════════════════════════════════════════

export fn fsrv_helper_tick_control(
    src: *anyopaque,
    tick: bool,
    dst_ffunc: c_int,
) callconv(.c) bool {
    var fail = true;

    // control_chld check + paused check
    const alive = leave_blk: {
        if (!fsrv_helper_control_chld(src))
            break :leave_blk false;

        const playstate = readField(c_uint, src, o_playstate);
        if (playstate == ARCAN_PAUSED)
            break :leave_blk false;

        // arcan_event_queuetransfer
        const inqueue_ptr: *anyopaque = @ptrCast(ptrAdd(src, o_inqueue));
        const queue_mask = readField(c_int, src, o_queue_mask);
        const xfer_sat = readField(f32, src, o_xfer_sat);
        const rv = arcan_event_queuetransfer(
            arcan_event_defaultctx(),
            inqueue_ptr,
            queue_mask,
            xfer_sat,
            src,
        );

        if (rv == -2) {
            _ = fsrv_helper_free(src);
            break :leave_blk false;
        }
        if (rv == -1)
            break :leave_blk false;

        // Check page resized flag
        const page = readField(?*anyopaque, src, o_shm_ptr) orelse break :leave_blk false;
        const resized: i8 = readField(i8, page, pg_resized);
        if (resized == 0) {
            fail = false;
            break :leave_blk true;
        }

        // Memory fence (FORCE_SYNCH equivalent: asm volatile + __sync_synchronize)
        asm volatile ("" ::: .{ .memory = true });
        _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);

        // Check if dimensions changed -> close buffer queues
        const desc_w = readField(u16, src, d_width);
        const desc_h = readField(u16, src, d_height);
        const page_w = atomicLoad(u16, page, pg_w);
        const page_h = atomicLoad(u16, page, pg_h);
        if (desc_w != page_w or desc_h != page_h) {
            fsrv_helper_close_bufferqueues(src, true, true);
        }

        // platform_fsrv_resynch
        const rzc = platform_fsrv_resynch(src);
        if (rzc <= 0)
            break :leave_blk false;

        if (rzc == 2) {
            // Emit EVENT_FSRV_APROTO
            var ev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
            eventSetCategory(&ev, EVENT_FSRV);
            eventWriteField(u32, &ev, ev_fsrv_kind, EVENT_FSRV_APROTO);
            eventWriteField(i64, &ev, ev_fsrv_video, readField(i64, src, o_vid));
            eventWriteField(i32, &ev, ev_fsrv_audio, @as(i32, @bitCast(readField(c_uint, src, d_aproto))));
            eventWriteField(isize, &ev, ev_fsrv_otag, readField(isize, src, o_tag));
            _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&ev));
        }
        fail = false;

        // If dimensions changed across the resynch, emit EVENT_FSRV_RESIZED.
        // push_buffer also generates this on frame signal, but clients that
        // resize without immediately signaling a frame (e.g. gamescope) need
        // the event here so the WM can allocate space.
        // Use pre-resynch desc_w/desc_h vs page_w/page_h (already computed above).
        const vid = readField(i64, src, o_vid);
        if (desc_w != page_w or desc_h != page_h) {
            var rezev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
            eventSetCategory(&rezev, EVENT_FSRV);
            eventWriteField(u32, &rezev, ev_fsrv_kind, EVENT_FSRV_RESIZED);
            eventWriteField(usize, &rezev, ev_fsrv_width, @as(usize, page_w));
            eventWriteField(usize, &rezev, ev_fsrv_height, @as(usize, page_h));
            eventWriteField(i64, &rezev, ev_fsrv_video, vid);
            eventWriteField(i32, &rezev, ev_fsrv_audio, readField(i32, src, o_aid));
            eventWriteField(isize, &rezev, ev_fsrv_otag, readField(isize, src, o_tag));
            const cur_hints = readField(c_int, src, d_hints);
            const fmt_fl: i8 = @truncate(
                (cur_hints & SHMIF_RHINT_ORIGO_LL) | (cur_hints & SHMIF_RHINT_TPACK),
            );
            eventWriteField(i8, &rezev, ev_fsrv_fmt_fl, fmt_fl);
            _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&rezev));

            // Set rz_flag so push_buffer also calls arcan_video_resizefeed
            writeField(bool, src, d_rz_flag, true);
        }

        // arcan_video_alterfeed(src->vid, dst_ffunc, *arcan_video_feedstate(src->vid))
        const fstate = arcan_video_feedstate(vid);
        if (fstate) |fs| {
            _ = arcan_video_alterfeed(vid, dst_ffunc, fs.*);
        }

        break :leave_blk true;
    };
    _ = alive;

    // Post-leave: gamma ramp check
    if (!fail) {
        const aproto_val = readField(c_uint, src, d_aproto);
        if (aproto_val & SHMIF_META_CM != 0) {
            const gamma = readField(?*anyopaque, src, d_aext_gamma);
            if (gamma) |gam| {
                // atomic_load dirty_out from shmif_ramp
                const in_map: u8 = atomicLoad(u8, gam, ramp_dirty_out);
                var cur_map = readField(u8, src, d_aext_gamma_map);
                var i: u8 = 0;
                while (i < 8) : (i += 1) {
                    const bit: u8 = @as(u8, 1) << @as(u3, @intCast(i));
                    if ((in_map & bit) != 0 and (cur_map & bit) == 0) {
                        var ev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
                        eventSetCategory(&ev, EVENT_FSRV);
                        eventWriteField(u32, &ev, ev_fsrv_kind, EVENT_FSRV_GAMMARAMP);
                        eventWriteField(u64, &ev, ev_fsrv_counter, @as(u64, i));
                        eventWriteField(i64, &ev, ev_fsrv_video, readField(i64, src, o_vid));
                        _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&ev));
                        cur_map |= bit;
                        writeField(u8, src, d_aext_gamma_map, cur_map);
                    }
                }
            }
        }
    }

    // Tick: decrement clock.left, send STEPFRAME if expired
    if (!fail and tick) {
        const clock_left = readField(u32, src, o_clock_left);
        const new_left: u32 = clock_left -% 1;
        writeField(u32, src, o_clock_left, new_left);
        // C code: `0 >= --src->clock.left` on uint32_t.
        // The left field is unsigned. In C, `0 >= unsigned` is true only when == 0.
        // After decrement-with-wrap: if clock_left was 0 => new_left = 0xFFFFFFFF (not <= 0).
        // If clock_left was 1 => new_left = 0 (match). So condition is: new_left == 0.
        if (new_left == 0) {
            const start = readField(u32, src, o_clock_start);
            writeField(u32, src, o_clock_left, start);
            // Push STEPFRAME event
            var ev: [ev_sizeof]u8 align(8) = [_]u8{0} ** ev_sizeof;
            eventSetCategory(&ev, EVENT_TARGET);
            eventWriteField(u32, &ev, ev_tgt_kind, TARGET_COMMAND_STEPFRAME);
            eventWriteField(i32, &ev, ev_tgt_ioevs_0_iv, 1);
            eventWriteField(i32, &ev, ev_tgt_ioevs_1_iv, @as(i32, @bitCast(readField(u32, src, o_clock_id))));
            _ = platform_fsrv_pushevent(src, @ptrCast(&ev));
        }
    }

    return !fail;
}
// Chunk 7: audio + font + ramps + dump + top-level exports
//
// Functions ported from arcan_frameserver_helpers.c lines 1291-1625, 1794-1849.
// Uses readField/writeField/ptrAdd/fieldPtr/getBitfield/setBitfield from chunk 1,
// all offset constants from the shared constants block, and extern fn declarations.

// Additional rendertarget offsets (not in chunk 1)
const rt_readback: usize = 204; // int
const rt_refresh: usize = 216; // int
const rt_flags: usize = 196; // enum rtgt_flags (c_int)
const rt_vppcm: usize = 252; // f32

// Additional vobject offsets (not in chunk 1)
const vo_cellid: usize = 376; // arcan_vobj_id (i64)
const vo_order: usize = 100; // signed int

// arcan_shmif_ramp offsets
const ramp_magic: usize = 0; // u32
const ramp_dirty_in: usize = 4; // u8 (atomic)
const ramp_dirty_out: usize = 5; // u8 (atomic)
const ramp_n_blocks: usize = 6; // u8
const ramp_ramps: usize = 8; // struct ramp_block[] (flexible array)
const ARCAN_SHMIF_RAMPMAGIC: u32 = 0xfafafa10;

// ramp_block offsets
const sz_ramp_block: usize = 16568;
const rb_format: usize = 0; // u8
const rb_checksum: usize = 2; // u16
const rb_plane_sizes: usize = 8; // [4]usize
const rb_edid: usize = 40; // [128]u8
const rb_planes: usize = 188; // [4095]f32

// Misc constants (used locally)
const BADFD: c_int = -1;
const EPSILON: f32 = 0.000001;
const RESOURCE_SYS_FONT: c_int = 128;
const ARES_FILE: c_int = 1;
const ARES_RDONLY: c_int = 512;

// External function: dup(2)
extern fn dup(fd: c_int) c_int;

// External functions for dump_*
extern fn fprintf(stream: ?*anyopaque, fmt: [*c]const u8, ...) callconv(.c) c_int;
extern fn fputc(ch: c_int, stream: ?*anyopaque) callconv(.c) c_int;
extern fn fputs(s: [*c]const u8, stream: ?*anyopaque) callconv(.c) c_int;

// ═══════════════════════════════════════════════════════════════════════
// subp_checksum (from arcan_shmif_sub.h:53)
// ═══════════════════════════════════════════════════════════════════════

fn subp_checksum(buf: [*]const u8, len: usize) u16 {
    var res: u32 = 0;
    for (0..len) |i| {
        if (res & 1 != 0)
            res |= 0x10000;
        res = ((res >> 1) + buf[i]) & 0xffff;
    }
    return @intCast(res);
}

// ═══════════════════════════════════════════════════════════════════════
// feed_amixer (C line 1291)
// ═══════════════════════════════════════════════════════════════════════

fn feed_amixer(
    dst: *anyopaque,
    srcid: arcan_aobj_id,
    buf_in: [*]i16,
    nsamples_in: c_int,
) void {
    const n_aids = readField(c_uint, dst, amx_n_aids);
    const inaud_base: ?[*]u8 = readField(?[*]u8, dst, amx_inaud);
    if (inaud_base == null or n_aids == 0) return;

    var minv: usize = std.math.maxInt(usize);
    var buf = buf_in;
    var nsamples = nsamples_in;

    for (0..n_aids) |i| {
        const cur = inaud_base.? + i * sz_frameserver_audsrc;
        const cur_src_aid = @as(*align(1) const arcan_aobj_id, @ptrCast(cur + fas_src_aid)).*;

        if (cur_src_aid == srcid) {
            const ulim: usize = 4096; // sizeof(inbuf) / sizeof(float)
            var count: usize = 0;
            var inofs = @as(*align(1) i64, @ptrCast(cur + fas_inofs)).*;

            while (nsamples > 0 and inofs < @as(i64, @intCast(ulim))) {
                const val: f32 = @floatFromInt(buf[0]);
                const gain_off: usize = if (count % 2 != 0) fas_l_gain else fas_r_gain;
                const gain = @as(*align(1) const f32, @ptrCast(cur + gain_off)).*;
                const inbuf_off = @as(usize, @intCast(inofs)) * @sizeOf(f32);
                @as(*align(1) f32, @ptrCast(cur + fas_inbuf + inbuf_off)).* = gain * (val / 32767.0);

                inofs += 1;
                count += 1;
                nsamples -= 1;
                buf += 1;
            }

            @as(*align(1) i64, @ptrCast(cur + fas_inofs)).* = inofs;
        }

        const cur_inofs: usize = @intCast(@as(*align(1) const i64, @ptrCast(cur + fas_inofs)).*);
        if (cur_inofs < minv) minv = cur_inofs;
    }

    if (minv != std.math.maxInt(usize) and minv > 512) {
        const sz_audb = readField(usize, dst, o_sz_audb);
        const ofs_audb_raw = readField(i64, dst, o_ofs_audb);
        const ofs_audb: usize = @intCast(ofs_audb_raw);

        if (sz_audb > ofs_audb) {
            // Clamp minv if output buffer can't hold it all
            var minv_clamped = minv;
            if (ofs_audb + minv * 2 > sz_audb) {
                minv_clamped = (sz_audb - ofs_audb) / 2;
            }

            const audb: [*]u8 = readField([*]u8, dst, o_audb);

            for (0..minv_clamped) |sc| {
                var work_sample: f32 = 0.0;

                for (0..n_aids) |ii| {
                    const cur2 = inaud_base.? + ii * sz_frameserver_audsrc;
                    const sample_off = sc * @sizeOf(f32);
                    const sval = @as(*align(1) const f32, @ptrCast(cur2 + fas_inbuf + sample_off)).*;
                    work_sample += sval - (work_sample * sval);
                }

                const sample_conv: i16 = if (work_sample >= 1.0)
                    32767
                else if (work_sample < -1.0)
                    -32768
                else
                    @intFromFloat(work_sample * 32767.0);

                const dst_ptr: *align(1) i16 = @ptrCast(audb + ofs_audb + sc * 2);
                dst_ptr.* = sample_conv;
            }

            writeField(i64, dst, o_ofs_audb, @as(i64, @intCast(ofs_audb + minv_clamped * 2)));

            // Shift remaining samples
            for (0..n_aids) |j| {
                const cur3 = inaud_base.? + j * sz_frameserver_audsrc;
                const cur3_inofs: usize = @intCast(@as(*align(1) const i64, @ptrCast(cur3 + fas_inofs)).*);

                if (cur3_inofs > minv_clamped) {
                    _ = memmove(
                        cur3 + fas_inbuf,
                        cur3 + fas_inbuf + minv_clamped * @sizeOf(f32),
                        (cur3_inofs - minv_clamped) * @sizeOf(f32),
                    );
                    @as(*align(1) i64, @ptrCast(cur3 + fas_inofs)).* = @intCast(cur3_inofs - minv_clamped);
                } else {
                    @as(*align(1) i64, @ptrCast(cur3 + fas_inofs)).* = 0;
                }
            }
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// avfeed_mixer (C line 1346)
// ═══════════════════════════════════════════════════════════════════════

fn avfeed_mixer(
    dst: *anyopaque,
    n_sources: c_int,
    sources: [*]arcan_aobj_id,
) void {
    if (n_sources <= 0) return;
    const n: usize = @intCast(n_sources);

    // Free existing inaud if any
    const old_n = readField(c_uint, dst, amx_n_aids);
    if (old_n > 0) {
        const old_ptr = readField(?*anyopaque, dst, amx_inaud);
        arcan_mem_free(old_ptr);
    }

    // Allocate new array (ARCAN_MEM_ATAG=3, ARCAN_MEM_BZERO=0x10, ARCAN_MEMALIGN_NATURAL=0)
    const alloc_sz = n * sz_frameserver_audsrc;
    const new_ptr = arcan_alloc_mem(alloc_sz, 3, 0x10, 0);
    writeField(?*anyopaque, dst, amx_inaud, new_ptr);

    if (new_ptr) |base| {
        const base_bytes: [*]u8 = @ptrCast(base);
        for (0..n) |i| {
            const cur = base_bytes + i * sz_frameserver_audsrc;
            @as(*align(1) f32, @ptrCast(cur + fas_l_gain)).* = 1.0;
            @as(*align(1) f32, @ptrCast(cur + fas_r_gain)).* = 1.0;
            @as(*align(1) i64, @ptrCast(cur + fas_inofs)).* = 0;
            @as(*align(1) arcan_aobj_id, @ptrCast(cur + fas_src_aid)).* = sources[i];
        }
    }

    writeField(c_uint, dst, amx_n_aids, @intCast(n));
}

// ═══════════════════════════════════════════════════════════════════════
// update_mixweight (C line 1369)
// ═══════════════════════════════════════════════════════════════════════

fn update_mixweight(
    dst: *anyopaque,
    src: arcan_aobj_id,
    left: f32,
    right: f32,
) void {
    const n_aids = readField(c_uint, dst, amx_n_aids);
    const inaud_base: ?[*]u8 = readField(?[*]u8, dst, amx_inaud);
    if (inaud_base == null or n_aids == 0) return;

    for (0..n_aids) |i| {
        const cur = inaud_base.? + i * sz_frameserver_audsrc;
        const cur_src_aid = @as(*align(1) const arcan_aobj_id, @ptrCast(cur + fas_src_aid)).*;
        if (src == 0 or cur_src_aid == src) {
            @as(*align(1) f32, @ptrCast(cur + fas_l_gain)).* = left;
            @as(*align(1) f32, @ptrCast(cur + fas_r_gain)).* = right;
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// avfeedmon (C line 1381)
// ═══════════════════════════════════════════════════════════════════════

fn avfeedmon(
    src: arcan_aobj_id,
    buf: [*]u8,
    buf_sz: usize,
    channels: c_uint,
    frequency: c_uint,
    tag: ?*anyopaque,
) void {
    _ = channels;
    const dst: *anyopaque = tag orelse return;

    if (frequency != ARCAN_SHMIF_SAMPLERATE) {
        const S = struct {
            var warn: bool = false;
        };
        if (!S.warn) {
            arcan_warning("arcan_frameserver_avfeedmon(), monitoring an audio feed\n" ++
                "with a non-native samplerate, this is >currently< supported for\n" ++
                "playback but not for recording (TOFIX).\n");
            S.warn = true;
        }
    }

    const n_aids = readField(c_uint, dst, amx_n_aids);
    if (n_aids > 0) {
        feed_amixer(dst, src, @ptrCast(@alignCast(buf)), @intCast(buf_sz >> 1));
    } else {
        const ofs_audb: usize = @intCast(readField(i64, dst, o_ofs_audb));
        const sz_audb = readField(usize, dst, o_sz_audb);
        if (ofs_audb + buf_sz < sz_audb) {
            const audb: [*]u8 = readField([*]u8, dst, o_audb);
            _ = memcpy(audb + ofs_audb, buf, buf_sz);
            writeField(i64, dst, o_ofs_audb, @intCast(ofs_audb + buf_sz));
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// audioframe_direct (C line 1408)
// ═══════════════════════════════════════════════════════════════════════

fn audioframe_direct(
    aobj: ?*anyopaque,
    id: arcan_aobj_id,
    buffer: c_uint,
    cont: bool,
    tag: ?*anyopaque,
) callconv(.c) arcan_errc {
    _ = id;
    const src: *anyopaque = tag orelse return ARCAN_ERRC_NOTREADY;

    // buffer == -1 check (unsigned -1 = max)
    if (buffer == @as(c_uint, @bitCast(@as(c_int, -1))))
        return ARCAN_ERRC_NOTREADY;

    const segid = readField(c_uint, src, o_segid);
    if (segid == SEGID_UNKNOWN)
        return ARCAN_ERRC_NOTREADY;

    if (readField(u16, src, o_watch_const) != 0xfeed)
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const shm_pg: ?*anyopaque = readField(?*anyopaque, src, shm_ptr);
    if (shm_pg == null)
        return ARCAN_ERRC_UNACCEPTED_STATE;
    const pg: [*]u8 = @ptrCast(shm_pg.?);

    // TRAMP_GUARD
    if (!fsrv_helper_tramp_enter(src))
        return ARCAN_ERRC_UNACCEPTED_STATE;

    const aready_val = @atomicLoad(u32, @as(*const u32, @ptrCast(@alignCast(pg + pg_aready))), .seq_cst);
    const ind_raw: i64 = @as(i64, @intCast(aready_val)) - 1;
    const amask = @atomicLoad(u32, @as(*const u32, @ptrCast(@alignCast(pg + pg_apending))), .seq_cst);

    const abuf_cnt = readField(usize, src, o_abuf_cnt);

    if (ind_raw >= @as(i64, @intCast(abuf_cnt)) or ind_raw < 0) {
        platform_fsrv_leave();
        return ARCAN_ERRC_NOTREADY;
    }

    const ind: u5 = @intCast(ind_raw);

    if (amask == 0 or ((@as(u32, 1) << ind) & amask) == 0) {
        @atomicStore(u32, @as(*u32, @ptrCast(@alignCast(pg + pg_aready))), 0, .release);
        fsrv_helper_signal(src, SYNC_AUDIO);
        platform_fsrv_leave();
        return ARCAN_ERRC_NOTREADY;
    }

    // Walk backwards to find the prev buffer
    var i_walk: i64 = ind_raw;
    var prev: i64 = i_walk;
    while (true) {
        prev = i_walk;
        i_walk -= 1;
        if (i_walk < 0) i_walk = @intCast(abuf_cnt - 1);
        if (i_walk == ind_raw) break;
        if (((@as(u32, 1) << @intCast(i_walk)) & amask) == 0) break;
    }

    const audio_flush = readField(bool, src, o_audio_flush_pending);
    if (!audio_flush) {
        const prev_idx: usize = @intCast(prev);

        // src->abufs[prev]
        const abufs_base: [*]?*anyopaque = @ptrCast(@alignCast(ptrAdd(src, o_abufs)));
        const abuf_ptr = abufs_base[prev_idx];

        // src->shm.ptr->abufused[prev] — array of u16 at pg + pg_abufused
        const abufused_ptr: *align(1) u16 = @ptrCast(pg + pg_abufused + prev_idx * 2);
        const used_sz: u32 = @atomicLoad(u16, @as(*const u16, @ptrCast(@alignCast(abufused_ptr))), .seq_cst);

        const channels = readField(u8, src, d_channels);
        const samplerate = readField(c_uint, src, d_samplerate);

        arcan_audio_buffer(aobj, buffer, abuf_ptr, used_sz, channels, samplerate, tag);

        @atomicStore(u16, @as(*u16, @ptrCast(@alignCast(abufused_ptr))), 0, .seq_cst);

        const prev_bit: u5 = @intCast(prev);
        _ = @atomicRmw(u32, @as(*u32, @ptrCast(@alignCast(pg + pg_apending))), .And, ~(@as(u32, 1) << prev_bit), .release);
    } else {
        @atomicStore(u32, @as(*u32, @ptrCast(@alignCast(pg + pg_apending))), 0, .seq_cst);
        writeField(bool, src, o_audio_flush_pending, false);
    }

    if (!cont) {
        @atomicStore(u32, @as(*u32, @ptrCast(@alignCast(pg + pg_aready))), 0, .release);
        fsrv_helper_signal(src, SYNC_AUDIO);
        platform_fsrv_leave();
    }

    return ARCAN_OK;
}

// ═══════════════════════════════════════════════════════════════════════
// getramps (C line 1472)
// ═══════════════════════════════════════════════════════════════════════

fn getramps(
    src: *anyopaque,
    index: usize,
    table: [*]f32,
    table_sz: usize,
    ch_sz: [*]usize,
) bool {
    const gamma_ptr: ?*anyopaque = readField(?*anyopaque, src, d_aext_gamma);
    if (gamma_ptr == null) return false;
    const dm: [*]u8 = @ptrCast(gamma_ptr.?);

    // Check magic
    const magic = @as(*align(1) const u32, @ptrCast(dm + ramp_magic)).*;
    if (magic != ARCAN_SHMIF_RAMPMAGIC) return false;

    // Check display limit
    var lim: usize = 0;
    platform_video_displays(null, &lim);
    if (index >= lim) return false;

    // Check dirty_out bitmask
    const dirty_out = @atomicLoad(u8, @as(*const u8, @ptrCast(dm + ramp_dirty_out)), .seq_cst);
    if ((dirty_out & (@as(u8, 1) << @intCast(index))) == 0) return false;

    // Copy ramp_block (index * 2 for in/out pair)
    const block_base = dm + ramp_ramps + (index * 2) * sz_ramp_block;

    // Read checksum
    const stored_checksum = @as(*align(1) const u16, @ptrCast(block_base + rb_checksum)).*;

    // Compute expected checksum over edid + planes data
    const check_buf: [*]const u8 = block_base + rb_edid;
    const check_len: usize = 128 + SHMIF_CMRAMP_UPLIM * @sizeOf(f32);
    const computed = subp_checksum(check_buf, check_len);

    // Clear gamma_map bit
    const cur_map = readField(u8, src, d_aext_gamma_map);
    writeField(u8, src, d_aext_gamma_map, cur_map & ~(@as(u8, 1) << @intCast(index)));

    if (computed != stored_checksum) return false;

    // Copy plane data
    const copy_sz = if (table_sz < SHMIF_CMRAMP_UPLIM * @sizeOf(f32))
        table_sz
    else
        SHMIF_CMRAMP_UPLIM * @sizeOf(f32);
    _ = memcpy(table, block_base + rb_planes, copy_sz);

    // Copy plane_sizes
    _ = memcpy(ch_sz, block_base + rb_plane_sizes, @sizeOf(usize) * SHMIF_CMRAMP_PLIM);

    // Clear dirty_out bit
    _ = @atomicRmw(u8, @as(*u8, @ptrCast(dm + ramp_dirty_out)), .And, ~(@as(u8, 1) << @intCast(index)), .seq_cst);

    return true;
}

// ═══════════════════════════════════════════════════════════════════════
// setramps (C line 1511)
// ═══════════════════════════════════════════════════════════════════════

fn setramps(
    src: *anyopaque,
    index: usize,
    table: [*]f32,
    table_sz: usize,
    ch_sz: [*]usize,
    edid: ?[*]u8,
    edid_sz: usize,
) bool {
    const gamma_ptr: ?*anyopaque = readField(?*anyopaque, src, d_aext_gamma);
    if (gamma_ptr == null) return false;
    const dm: [*]u8 = @ptrCast(gamma_ptr.?);

    // Check display limit
    var lim: usize = 0;
    platform_video_displays(null, &lim);
    if (index >= lim) return false;

    // Validate plane sizes sum
    var sum: usize = 0;
    for (0..SHMIF_CMRAMP_PLIM) |i| {
        sum += ch_sz[i];
    }
    if (sum > SHMIF_CMRAMP_UPLIM) return false;

    // Build a zeroed ramp_block on the stack (via a byte buffer)
    var block: [sz_ramp_block]u8 = std.mem.zeroes([sz_ramp_block]u8);

    // Copy plane_sizes
    _ = memcpy(&block[rb_plane_sizes], ch_sz, @sizeOf(usize) * SHMIF_CMRAMP_PLIM);

    // Copy plane data
    var pdata_sz: usize = SHMIF_CMRAMP_UPLIM * @sizeOf(f32);
    if (pdata_sz > table_sz) pdata_sz = table_sz;
    _ = memcpy(&block[rb_planes], table, pdata_sz);

    // Copy edid if present and correct size
    const edid_bsz: usize = 128; // sizeof(edid) in ramp_block
    const block_at_index = dm + ramp_ramps + index * sz_ramp_block;
    if (edid != null and edid_sz == edid_bsz) {
        _ = memcpy(block_at_index + rb_edid, edid.?, edid_bsz);
    }

    // Compute checksum over edid + plane data in our block
    const check_buf: [*]const u8 = @ptrCast(&block[rb_edid]);
    const check_len: usize = edid_bsz + SHMIF_CMRAMP_UPLIM * @sizeOf(f32);
    const checksum = subp_checksum(check_buf, check_len);
    @as(*align(1) u16, @ptrCast(&block[rb_checksum])).* = checksum;

    // Write block to shared memory
    _ = memcpy(block_at_index, &block, sz_ramp_block);

    // Set dirty_in bit
    _ = @atomicRmw(u8, @as(*u8, @ptrCast(dm + ramp_dirty_in)), .Or, @as(u8, 1) << @intCast(index), .seq_cst);

    return true;
}

// ═══════════════════════════════════════════════════════════════════════
// setfont (C line 1556)
// ═══════════════════════════════════════════════════════════════════════

fn setfont(
    fsrv: *anyopaque,
    fd: c_int,
    sz: f32,
    hint: c_int,
    slot: c_int,
) arcan_errc {
    _ = hint;
    var replace: bool = true;
    var reprobe: bool = false;

    if (slot == 0) {
        if (sz > EPSILON) {
            writeField(f32, fsrv, d_text_szmm, sz);
            reprobe = true;
        }

        const group = readField(?*anyopaque, fsrv, d_text_group);
        if (group == null) {
            var ppcm = readField(f32, fsrv, d_hint_ppcm);
            if (ppcm < EPSILON) {
                const vid = readField(arcan_vobj_id, fsrv, o_vid);
                const vobj = arcan_video_getobject(vid);
                if (vobj) |vo| {
                    const tgt = arcan_vint_findrt(vo);
                    if (tgt) |rt| {
                        // Read vppcm from rendertarget
                        ppcm = @as(*align(1) const f32, @ptrCast(@as([*]u8, @ptrCast(rt)) + rt_vppcm)).*;
                    } else {
                        ppcm = 38.7;
                    }
                } else {
                    ppcm = 38.7;
                }
                writeField(f32, fsrv, d_hint_ppcm, ppcm);
            }

            // arcan_renderfun_fontgroup expects an array of 4 fds.
            // When fd is BADFD (no explicit font path), use the system default font
            // so the compositor-side raster matches the terminal's font metrics.
            var font_fd: c_int = BADFD;
            var font_fd_owned = false;
            if (fd == BADFD) {
                arcan_video_fontdefaults(&font_fd, null, null);
                if (font_fd == BADFD) {
                    // font_cache empty (appl never called system_defaultfont) —
                    // find default.ttf from the font resource path directly
                    const path = arcan_find_resource("default.ttf", RESOURCE_SYS_FONT, ARES_FILE | ARES_RDONLY, &font_fd);
                    if (path != null) {
                        arcan_mem_free(@ptrCast(path));
                        font_fd_owned = true;
                    }
                }
            }
            const use_fd = if (fd != BADFD) fd else font_fd;
            var fds: [4]c_int = .{ dup(use_fd), BADFD, BADFD, BADFD };
            if (font_fd_owned and font_fd != BADFD) {
                _ = close(font_fd);
            }
            const new_group = arcan_renderfun_fontgroup(&fds, 4);
            writeField(?*anyopaque, fsrv, d_text_group, new_group);
            replace = false;
        }
    }

    const group2 = readField(?*anyopaque, fsrv, d_text_group);
    if (group2 == null) {
        _ = close(fd);
        return ARCAN_ERRC_UNACCEPTED_STATE;
    }

    if (replace) {
        if (fd != -1) {
            arcan_renderfun_fontgroup_replace(group2, slot, dup(fd));
        } else if (slot == 0) {
            // No explicit font — use system default so raster matches terminal
            var def_fd: c_int = BADFD;
            var def_fd_owned = false;
            arcan_video_fontdefaults(&def_fd, null, null);
            if (def_fd == BADFD) {
                const path = arcan_find_resource("default.ttf", RESOURCE_SYS_FONT, ARES_FILE | ARES_RDONLY, &def_fd);
                if (path != null) {
                    arcan_mem_free(@ptrCast(path));
                    def_fd_owned = true;
                }
            }
            if (def_fd != BADFD) {
                arcan_renderfun_fontgroup_replace(group2, 0, dup(def_fd));
                if (def_fd_owned) {
                    _ = close(def_fd);
                }
            }
        }
    }

    if (reprobe) {
        const ppcm2 = readField(f32, fsrv, d_hint_ppcm);
        const szmm2 = readField(f32, fsrv, d_text_szmm);
        if (ppcm2 > EPSILON) {
            var cellw = readField(usize, fsrv, d_text_cellw);
            var cellh = readField(usize, fsrv, d_text_cellh);
            arcan_renderfun_fontgroup_size(
                group2,
                szmm2,
                ppcm2,
                &cellw,
                &cellh,
            );
            writeField(usize, fsrv, d_text_cellw, cellw);
            writeField(usize, fsrv, d_text_cellh, cellh);
        } else {
        }
    }

    return ARCAN_OK;
}

// ═══════════════════════════════════════════════════════════════════════
// displayhint (C line 1606)
// ═══════════════════════════════════════════════════════════════════════

fn displayhint(
    fsrv: *anyopaque,
    w: usize,
    h: usize,
    ppcm: f32,
) void {
    if (w > 0) writeField(usize, fsrv, d_hint_width, w);
    if (h > 0) writeField(usize, fsrv, d_hint_height, h);

    const cur_ppcm = readField(f32, fsrv, d_hint_ppcm);
    if (ppcm > EPSILON and ppcm != cur_ppcm) {
        writeField(f32, fsrv, d_hint_ppcm, ppcm);
        const group = readField(?*anyopaque, fsrv, d_text_group);
        if (group != null) {
            var cellw = readField(usize, fsrv, d_text_cellw);
            var cellh = readField(usize, fsrv, d_text_cellh);
            arcan_renderfun_fontgroup_size(group, 0, ppcm, &cellw, &cellh);
            writeField(usize, fsrv, d_text_cellw, cellw);
            writeField(usize, fsrv, d_text_cellh, cellh);
        }
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Constant helpers (C line 1794)
// ═══════════════════════════════════════════════════════════════════════

export fn fsrv_helper_ARCAN_PLAYING() c_int {
    return ARCAN_PLAYING;
}
export fn fsrv_helper_ARCAN_PAUSED() c_int {
    return ARCAN_PAUSED;
}
export fn fsrv_helper_ARCAN_EID() c_int {
    return @intCast(ARCAN_EID);
}
export fn fsrv_helper_SHMIF_RHINT_VSIGNAL_EV() c_int {
    return SHMIF_RHINT_VSIGNAL_EV;
}
export fn fsrv_helper_SYNC_VIDEO() c_int {
    return SYNC_VIDEO;
}
export fn fsrv_helper_SYNC_AUDIO() c_int {
    return SYNC_AUDIO;
}
export fn fsrv_helper_SYNC_EVENT() c_int {
    return SYNC_EVENT;
}

// ═══════════════════════════════════════════════════════════════════════
// fput_luasafe_str (C line 1806)
// ═══════════════════════════════════════════════════════════════════════

export fn fput_luasafe_str(dst: ?*anyopaque, str: [*c]const u8) void {
    if (dst == null or str == null) return;
    _ = fputc('"', dst);
    var p = str;
    while (p[0] != 0) {
        switch (p[0]) {
            '"', '\\' => {
                _ = fputc('\\', dst);
                _ = fputc(p[0], dst);
            },
            '\n' => {
                _ = fputc('\\', dst);
                _ = fputc('\n', dst);
            },
            '\r' => {
                _ = fputs("\\r", dst);
            },
            0 => {
                // Can't actually reach here because of while condition,
                // but matches the C switch for completeness
                _ = fputs("\\000", dst);
            },
            else => {
                _ = fputc(p[0], dst);
            },
        }
        p += 1;
    }
    _ = fputc('"', dst);
}

// ═══════════════════════════════════════════════════════════════════════
// dump_vobject (C line 1832)
// ═══════════════════════════════════════════════════════════════════════

export fn dump_vobject(dst: ?*anyopaque, src: ?*anyopaque) void {
    if (dst == null or src == null) return;
    const s: [*]u8 = @ptrCast(src.?);

    const cellid: c_int = @intCast(readField(arcan_vobj_id, src.?, vo_cellid));
    const origw: c_int = @intCast(@as(*align(1) const u16, @ptrCast(s + vo_origw)).*);
    const origh: c_int = @intCast(@as(*align(1) const u16, @ptrCast(s + vo_origh)).*);
    const order: c_int = @as(*align(1) const c_int, @ptrCast(@alignCast(s + vo_order))).*;

    _ = fprintf(dst, "vobj = {cellid = %d, origw = %d, origh = %d, order = %d};\n", cellid, origw, origh, order);
    _ = fprintf(dst, "props = {};\n");
    _ = fprintf(dst, "vobj.props = props;\n");
}

// ═══════════════════════════════════════════════════════════════════════
// dump_rtgt (C line 1842)
// ═══════════════════════════════════════════════════════════════════════

export fn dump_rtgt(dst: ?*anyopaque, rtgt: ?*anyopaque) void {
    if (dst == null or rtgt == null) return;
    const r: [*]u8 = @ptrCast(rtgt.?);

    const readback: c_int = @as(*align(1) const c_int, @ptrCast(@alignCast(r + rt_readback))).*;
    const refresh: c_int = @as(*align(1) const c_int, @ptrCast(@alignCast(r + rt_refresh))).*;
    const flags: c_int = @as(*align(1) const c_int, @ptrCast(@alignCast(r + rt_flags))).*;

    _ = fprintf(dst,
        "local rtgt = {attached = {}, readback = %d, refresh = %d, flags = %d};\n" ++
            "table.insert(ctx.rtargets, rtgt);\n",
        readback,
        refresh,
        flags,
    );
}

// ═══════════════════════════════════════════════════════════════════════
// ═══════════════════════════════════════════════════════════════════════
// All arcan_frameserver_* public API exports are in arcan_frameserver.zig.
// This file provides fsrv_helper_* implementations called by arcan_frameserver.zig.

// Export wrappers for chunk 7 functions

export fn fsrv_helper_update_mixweight(dst: *arcan_frameserver, src: arcan_aobj_id, left: f32, right: f32) void {
    update_mixweight(dst, src, left, right);
}

export fn fsrv_helper_avfeed_mixer(dst: *arcan_frameserver, n_sources: c_int, sources: [*]arcan_aobj_id) void {
    avfeed_mixer(dst, n_sources, sources);
}

export fn fsrv_helper_avfeedmon(src: arcan_aobj_id, buf: [*]u8, buf_sz: usize, channels: c_uint, frequency: c_uint, tag: ?*anyopaque) void {
    avfeedmon(src, buf, buf_sz, channels, frequency, tag);
}

export fn fsrv_helper_audioframe_direct(aobj: ?*anyopaque, id: arcan_aobj_id, buffer: c_uint, cont: bool, tag: ?*anyopaque) arcan_errc {
    return audioframe_direct(aobj, id, buffer, cont, tag);
}

export fn fsrv_helper_setfont(fsrv: *arcan_frameserver, fd: c_int, sz: f32, hint: c_int, slot: c_int) arcan_errc {
    return setfont(fsrv, fd, sz, hint, slot);
}

export fn fsrv_helper_displayhint(fsrv: *arcan_frameserver, w: usize, h: usize, ppcm: f32) void {
    displayhint(fsrv, w, h, ppcm);
}

export fn fsrv_helper_getramps(src: *arcan_frameserver, index: usize, table: [*]f32, table_sz: usize, ch_sz: [*]usize) bool {
    return getramps(src, index, table, table_sz, ch_sz);
}

export fn fsrv_helper_setramps(src: *arcan_frameserver, index: usize, table: [*]f32, table_sz: usize, ch_sz: [*]usize, edid: ?[*]u8, edid_sz: usize) bool {
    return setramps(src, index, table, table_sz, ch_sz, edid, edid_sz);
}
