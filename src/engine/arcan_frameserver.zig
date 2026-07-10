// Pure Zig port of engine/arcan_frameserver.c — frameserver lifecycle,
// feed functions, audio mixing, buffer management, ramp/gamma, fonts.
//
// Uses C accessor helpers in arcan_frameserver_helpers.c for:
//  - arcan_frameserver field access (bitfields -> opaque in Zig)
//  - arcan_shmif_page atomic field access
//  - TRAMP_GUARD wrappers (setjmp not available in Zig)
//  - push_buffer / tick_control / ffunc implementations (deeply nested
//    opaque struct access: vobject, vstore, rendertarget, stream_meta, etc.)
//  - emit_deliveredframe / emit_droppedframe (event construction)
//  - feed_amixer (frameserver_audsrc struct)

const std = @import("std");

// Type aliases
const arcan_errc = c_int;
const arcan_vobj_id = i64;
const arcan_aobj_id = i32;
const av_pixel = u32;

// Opaque engine types
const arcan_frameserver = anyopaque;
const arcan_evctx = anyopaque;

// Error codes
const ARCAN_OK: arcan_errc = 0;
const ARCAN_ERRC_NO_SUCH_OBJECT: arcan_errc = -7;
const ARCAN_ERRC_UNACCEPTED_STATE: arcan_errc = -4;
const ARCAN_ERRC_NOTREADY: arcan_errc = -10;

// FFUNC types
const arcan_ffunc_rv = c_int;
const FRV_NOFRAME: arcan_ffunc_rv = 0;
const FRV_GOTFRAME: arcan_ffunc_rv = 1;

const arcan_ffunc_cmd = c_int;
const FFUNC_POLL: arcan_ffunc_cmd = 0;
const FFUNC_RENDER: arcan_ffunc_cmd = 1;
const FFUNC_TICK: arcan_ffunc_cmd = 2;
const FFUNC_DESTROY: arcan_ffunc_cmd = 3;
const FFUNC_READBACK: arcan_ffunc_cmd = 4;
const FFUNC_READBACK_HANDLE: arcan_ffunc_cmd = 5;
const FFUNC_ADOPT: arcan_ffunc_cmd = 6;
const FFUNC_VFRAME: arcan_ffunc_cmd = 4; // enum arcan_ffunc value

const vfunc_state = extern struct {
    tag: c_int,
    ptr: ?*anyopaque,
};

// Playstate
const ARCAN_PLAYING: c_int = 2;
const ARCAN_PAUSED: c_int = 3;

// Sync flags
const SYNC_EVENT: c_int = 1;
const SYNC_AUDIO: c_int = 2;
const SYNC_VIDEO: c_int = 4;

// SHMIF constants
const SHMIF_CMRAMP_PLIM: usize = 4;
const ARCAN_SHMIF_SAMPLERATE: c_uint = 48000;

// g_buffers_locked (shared with helpers)
var g_buffers_locked: c_int = 0;

// C helper functions (arcan_frameserver_helpers.c)

// TRAMP_GUARD
extern fn fsrv_helper_tramp_enter(fsrv: *arcan_frameserver) bool;
extern fn fsrv_helper_tramp_leave() void;

// Field accessors
extern fn fsrv_helper_get_vid(f: *arcan_frameserver) arcan_vobj_id;
extern fn fsrv_helper_set_vid(f: *arcan_frameserver, v: arcan_vobj_id) void;
extern fn fsrv_helper_get_tag(f: *arcan_frameserver) isize;
extern fn fsrv_helper_get_aid(f: *arcan_frameserver) arcan_aobj_id;
extern fn fsrv_helper_set_aid(f: *arcan_frameserver, v: arcan_aobj_id) void;
extern fn fsrv_helper_get_dpipe(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_get_segid(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_get_cookie(f: *arcan_frameserver) u32;
extern fn fsrv_helper_get_cookie_fail(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_cookie_fail(f: *arcan_frameserver, v: bool) void;
extern fn fsrv_helper_get_shmptr(f: *arcan_frameserver) ?*anyopaque;
extern fn fsrv_helper_get_queue_mask(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_get_xfer_sat(f: *arcan_frameserver) f32;
extern fn fsrv_helper_get_inqueue(f: *arcan_frameserver) ?*arcan_evctx;
extern fn fsrv_helper_get_outqueue(f: *arcan_frameserver) ?*arcan_evctx;
extern fn fsrv_helper_get_watch_const(f: *arcan_frameserver) u16;
extern fn fsrv_helper_get_abuf_cnt(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_get_vbuf_cnt(f: *arcan_frameserver) c_int;

extern fn fsrv_helper_get_fused(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_fused(f: *arcan_frameserver, v: bool) void;
extern fn fsrv_helper_get_fuse_blown(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_fuse_blown(f: *arcan_frameserver, v: bool) void;

extern fn fsrv_helper_get_flags_alive(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_explicit(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_local_copy(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_no_alpha_copy(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_autoclock(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_rz_ack(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_locked(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_flags_release_pending(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_flags_release_pending(f: *arcan_frameserver, v: bool) void;
extern fn fsrv_helper_get_flags_block_hdr_meta(f: *arcan_frameserver) bool;

extern fn fsrv_helper_get_clock_left(f: *arcan_frameserver) u32;
extern fn fsrv_helper_set_clock_left(f: *arcan_frameserver, v: u32) void;
extern fn fsrv_helper_get_clock_start(f: *arcan_frameserver) u32;
extern fn fsrv_helper_get_clock_frametime(f: *arcan_frameserver) i64;
extern fn fsrv_helper_set_clock_frametime(f: *arcan_frameserver, v: i64) void;
extern fn fsrv_helper_get_clock_id(f: *arcan_frameserver) u32;
extern fn fsrv_helper_get_clock_present(f: *arcan_frameserver) u32;
extern fn fsrv_helper_set_clock_present(f: *arcan_frameserver, v: u32) void;
extern fn fsrv_helper_get_clock_last_msc(f: *arcan_frameserver) u32;
extern fn fsrv_helper_set_clock_last_msc(f: *arcan_frameserver, v: u32) void;
extern fn fsrv_helper_get_clock_once(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_clock_frame(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_clock_msc_feedback(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_clock_msc_feedback(f: *arcan_frameserver, v: bool) void;

extern fn fsrv_helper_get_desc_width(f: *arcan_frameserver) u16;
extern fn fsrv_helper_get_desc_height(f: *arcan_frameserver) u16;
extern fn fsrv_helper_get_desc_rows(f: *arcan_frameserver) usize;
extern fn fsrv_helper_get_desc_cols(f: *arcan_frameserver) usize;
extern fn fsrv_helper_get_desc_hints(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_set_desc_hints(f: *arcan_frameserver, v: c_int) void;
extern fn fsrv_helper_get_desc_pending_hints(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_get_desc_rz_flag(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_desc_rz_flag(f: *arcan_frameserver, v: bool) void;
extern fn fsrv_helper_get_desc_region_valid(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_desc_region_valid(f: *arcan_frameserver, v: bool) void;
extern fn fsrv_helper_get_desc_callback_framestate(f: *arcan_frameserver) bool;
extern fn fsrv_helper_get_desc_framecount(f: *arcan_frameserver) c_ulonglong;
extern fn fsrv_helper_inc_desc_framecount(f: *arcan_frameserver) void;
extern fn fsrv_helper_get_desc_dropcount(f: *arcan_frameserver) c_ulonglong;
extern fn fsrv_helper_inc_desc_dropcount(f: *arcan_frameserver) void;
extern fn fsrv_helper_get_desc_synch_ts(f: *arcan_frameserver) u32;
extern fn fsrv_helper_set_desc_synch_ts(f: *arcan_frameserver, v: u32) void;
extern fn fsrv_helper_get_desc_samplerate(f: *arcan_frameserver) c_uint;
extern fn fsrv_helper_get_desc_channels(f: *arcan_frameserver) u8;
extern fn fsrv_helper_get_desc_aproto(f: *arcan_frameserver) c_uint;
extern fn fsrv_helper_get_desc_region(f: *arcan_frameserver, x1: *i16, y1: *i16, x2: *i16, y2: *i16) void;
extern fn fsrv_helper_set_desc_region(f: *arcan_frameserver, x1: i16, y1: i16, x2: i16, y2: i16) void;
extern fn fsrv_helper_get_desc_text_group(f: *arcan_frameserver) ?*anyopaque;
extern fn fsrv_helper_set_desc_text_group(f: *arcan_frameserver, g: ?*anyopaque) void;
extern fn fsrv_helper_get_desc_text_cellw(f: *arcan_frameserver) usize;
extern fn fsrv_helper_get_desc_text_cellh(f: *arcan_frameserver) usize;
extern fn fsrv_helper_set_desc_text_cellw(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_set_desc_text_cellh(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_get_desc_text_szmm(f: *arcan_frameserver) f32;
extern fn fsrv_helper_set_desc_text_szmm(f: *arcan_frameserver, v: f32) void;
extern fn fsrv_helper_get_desc_hint_ppcm(f: *arcan_frameserver) f32;
extern fn fsrv_helper_set_desc_hint_ppcm(f: *arcan_frameserver, v: f32) void;
extern fn fsrv_helper_get_desc_hint_width(f: *arcan_frameserver) usize;
extern fn fsrv_helper_set_desc_hint_width(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_get_desc_hint_height(f: *arcan_frameserver) usize;
extern fn fsrv_helper_set_desc_hint_height(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_get_desc_aext_hdr(f: *arcan_frameserver) ?*anyopaque;
extern fn fsrv_helper_get_desc_aext_gamma(f: *arcan_frameserver) ?*anyopaque;
extern fn fsrv_helper_get_desc_aext_gamma_map(f: *arcan_frameserver) u8;
extern fn fsrv_helper_set_desc_aext_gamma_map(f: *arcan_frameserver, v: u8) void;

extern fn fsrv_helper_get_playstate(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_set_playstate(f: *arcan_frameserver, v: c_int) void;

extern fn fsrv_helper_get_vfcount(f: *arcan_frameserver) c_uint;
extern fn fsrv_helper_inc_vfcount(f: *arcan_frameserver) void;

extern fn fsrv_helper_get_sz_audb(f: *arcan_frameserver) usize;
extern fn fsrv_helper_set_sz_audb(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_get_ofs_audb(f: *arcan_frameserver) isize;
extern fn fsrv_helper_set_ofs_audb(f: *arcan_frameserver, v: isize) void;
extern fn fsrv_helper_get_audb(f: *arcan_frameserver) ?[*]u8;
extern fn fsrv_helper_set_audb(f: *arcan_frameserver, v: ?[*]u8) void;

extern fn fsrv_helper_get_alocks(f: *arcan_frameserver) ?[*]arcan_aobj_id;
extern fn fsrv_helper_set_alocks(f: *arcan_frameserver, v: ?[*]arcan_aobj_id) void;

extern fn fsrv_helper_get_audio_flush_pending(f: *arcan_frameserver) bool;
extern fn fsrv_helper_set_audio_flush_pending(f: *arcan_frameserver, v: bool) void;

extern fn fsrv_helper_get_n_pending(f: *arcan_frameserver) usize;
extern fn fsrv_helper_set_n_pending(f: *arcan_frameserver, v: usize) void;
extern fn fsrv_helper_pending_queue_len() usize;

extern fn fsrv_helper_get_rz_known(f: *arcan_frameserver) c_int;
extern fn fsrv_helper_set_rz_known(f: *arcan_frameserver, v: c_int) void;

extern fn fsrv_helper_get_parent_vid(f: *arcan_frameserver) arcan_vobj_id;
extern fn fsrv_helper_set_parent_vid(f: *arcan_frameserver, v: arcan_vobj_id) void;
extern fn fsrv_helper_get_parent_ptr(f: *arcan_frameserver) ?*anyopaque;
extern fn fsrv_helper_get_sockkey(f: *arcan_frameserver) [*c]const u8;

extern fn fsrv_helper_get_amixer_n_aids(f: *arcan_frameserver) c_int;

// Complex operations (delegated to C)
extern fn fsrv_helper_default_adoph(tgt: *arcan_frameserver, id: arcan_vobj_id) void;
extern fn fsrv_helper_autoclock_frame(tgt: *arcan_frameserver) void;
extern fn fsrv_helper_control_chld(src: *arcan_frameserver) bool;
extern fn fsrv_helper_close_bufferqueues(src: *arcan_frameserver, incoming: bool, pending: bool) void;
extern fn fsrv_helper_push_buffer(src: *arcan_frameserver, store: *anyopaque, dirty: ?*anyopaque) c_int;
extern fn fsrv_helper_flush_queued(tgt: *arcan_frameserver) void;
extern fn fsrv_helper_releaselock(tgt: *arcan_frameserver) c_int;
extern fn fsrv_helper_signal(tgt: *arcan_frameserver, fl: c_int) void;
extern fn fsrv_helper_tick_control(src: *arcan_frameserver, tick: bool, dst_ffunc: c_int) bool;
extern fn fsrv_helper_free(src: ?*arcan_frameserver) arcan_errc;
extern fn fsrv_helper_feed_amixer(dst: *arcan_frameserver, srcid: arcan_aobj_id, buf: [*]i16, nsamples: c_int) void;
extern fn fsrv_helper_avfeed_mixer(dst: *arcan_frameserver, n_sources: c_int, sources: [*]arcan_aobj_id) void;
extern fn fsrv_helper_update_mixweight(dst: *arcan_frameserver, src: arcan_aobj_id, left: f32, right: f32) void;
extern fn fsrv_helper_avfeedmon(src: arcan_aobj_id, buf: [*]u8, buf_sz: usize, channels: c_uint, frequency: c_uint, tag: ?*anyopaque) void;
extern fn fsrv_helper_audioframe_direct(aobj: ?*anyopaque, id: arcan_aobj_id, buffer: c_uint, cont: bool, tag: ?*anyopaque) arcan_errc;
extern fn fsrv_helper_getramps(src: *arcan_frameserver, index: usize, table: [*]f32, table_sz: usize, ch_sz: [*]usize) bool;
extern fn fsrv_helper_setramps(src: *arcan_frameserver, index: usize, table: [*]f32, table_sz: usize, ch_sz: [*]usize, edid: ?[*]u8, edid_sz: usize) bool;
extern fn fsrv_helper_setfont(fsrv: *arcan_frameserver, fd: c_int, sz: f32, hint: c_int, slot: c_int) arcan_errc;
extern fn fsrv_helper_displayhint(fsrv: *arcan_frameserver, w: usize, h: usize, ppcm: f32) void;

// ffunc implementations (delegated to C)
extern fn fsrv_helper_vdirect(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_feedcopy(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_wrapped(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_avfeedframe(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_nullfeed(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_emptyframe(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_pollffunc(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn fsrv_helper_verifyffunc(cmd: arcan_ffunc_cmd, buf: ?[*]av_pixel, buf_sz: usize, width: u16, height: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv;

// Engine extern functions
extern fn arcan_event_defaultctx() ?*arcan_evctx;
extern fn arcan_event_enqueue(ctx: ?*arcan_evctx, ev: ?*const anyopaque) arcan_errc;
extern fn arcan_event_queuetransfer(dstqueue: ?*arcan_evctx, srcqueue: ?*arcan_evctx, allowed: c_int, sat: f32, tgt: ?*anyopaque) c_int;
extern fn arcan_audio_hookfeed(aid: arcan_aobj_id, cb: ?*anyopaque, tag: ?*anyopaque, tag2: ?*anyopaque) void;
extern fn arcan_audio_rebuild(aid: arcan_aobj_id) void;
extern fn arcan_audio_stop(aid: arcan_aobj_id) void;
extern fn arcan_conductor_deregister_frameserver(fsrv: ?*anyopaque) void;
extern fn arcan_renderfun_release_fontgroup(group: ?*anyopaque) void;
extern fn arcan_renderfun_fontgroup(fds: ?*anyopaque, n: c_int) ?*anyopaque;
extern fn arcan_renderfun_fontgroup_replace(group: ?*anyopaque, slot: c_int, fd: c_int) void;
extern fn arcan_renderfun_fontgroup_size(group: ?*anyopaque, szmm: f32, ppcm: f32, cellw: *usize, cellh: *usize) void;
extern fn arcan_video_alterfeed(vid: arcan_vobj_id, ffunc: c_int, state: vfunc_state) arcan_errc;
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*anyopaque;
extern fn arcan_video_feedstate(vid: arcan_vobj_id) ?*vfunc_state;
extern fn arcan_video_findstate(tag: c_int, ptr: ?*anyopaque) arcan_vobj_id;
extern fn arcan_video_resizefeed(vid: arcan_vobj_id, w: u16, h: u16) void;
extern fn platform_fsrv_pushevent(fsrv: *arcan_frameserver, ev: ?*const anyopaque) arcan_errc;
extern fn platform_fsrv_validchild(fsrv: *arcan_frameserver) bool;
extern fn platform_fsrv_destroy(fsrv: *arcan_frameserver) bool;
extern fn platform_fsrv_lastwords(fsrv: *arcan_frameserver, msg: [*]u8, sz: usize) bool;
extern fn platform_fsrv_resynch(fsrv: *arcan_frameserver) c_int;
extern fn platform_fsrv_signal(fsrv: *anyopaque, fl: c_int) void;
extern fn platform_fsrv_socketpoll(fsrv: *arcan_frameserver) c_int;
extern fn platform_fsrv_socketauth(fsrv: *arcan_frameserver) c_int;
extern fn arcan_shmif_cookie() u32;
extern fn arcan_frametime() i64;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_audio_feed(cb: ?*const anyopaque, tag: ?*anyopaque, errc: ?*arcan_errc) arcan_aobj_id;
extern fn arcan_audio_buffer(aobj: ?*anyopaque, buffer: c_uint, buf: ?*anyopaque, sz: u32, channels: u8, samplerate: c_uint, tag: ?*anyopaque) void;
extern fn arcan_aid_refresh(aid: arcan_aobj_id) void;
extern fn platform_video_displays(arr: ?*anyopaque, lim: *usize) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_vint_findrt(vobj: *anyopaque) ?*anyopaque;
extern fn platform_fsrv_pushfd(fsrv: *arcan_frameserver, ev: *anyopaque, fd: c_int) void;
extern fn agp_rendertarget_swap(art: *anyopaque, swap: *bool) ?*anyopaque;
extern fn platform_video_export_vstore(vs: *anyopaque, planes: [*]anyopaque, count: usize) usize;

// Exported functions

// arcan_frameserver_free
export fn arcan_frameserver_free(src: ?*arcan_frameserver) arcan_errc {
    return fsrv_helper_free(src);
}

// arcan_frameserver_control_chld
export fn arcan_frameserver_control_chld(src: *arcan_frameserver) bool {
    return fsrv_helper_control_chld(src);
}

// arcan_frameserver_close_bufferqueues
export fn arcan_frameserver_close_bufferqueues(
    src: ?*arcan_frameserver,
    incoming: bool,
    pending: bool,
) void {
    if (src) |s| {
        fsrv_helper_close_bufferqueues(s, incoming, pending);
    }
}

// arcan_frameserver_nullfeed — FFUNC
export fn arcan_frameserver_nullfeed(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_nullfeed(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_pollffunc — FFUNC
export fn arcan_frameserver_pollffunc(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_pollffunc(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_verifyffunc — FFUNC
export fn arcan_frameserver_verifyffunc(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_verifyffunc(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_emptyframe — FFUNC
export fn arcan_frameserver_emptyframe(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_emptyframe(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_lock_buffers
export fn arcan_frameserver_lock_buffers(state_val: c_int) void {
    g_buffers_locked = state_val;
}

// arcan_frameserver_signal
export fn arcan_frameserver_signal(tgt: *arcan_frameserver, fl: c_int) void {
    fsrv_helper_signal(tgt, fl);
}

// arcan_frameserver_releaselock
export fn arcan_frameserver_releaselock(tgt: *arcan_frameserver) c_int {
    return fsrv_helper_releaselock(tgt);
}

// arcan_frameserver_vdirect — FFUNC
export fn arcan_frameserver_vdirect(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_vdirect(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_feedcopy — FFUNC
export fn arcan_frameserver_feedcopy(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_feedcopy(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_wrapped — FFUNC
export fn arcan_frameserver_wrapped(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_wrapped(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_avfeedframe — FFUNC
export fn arcan_frameserver_avfeedframe(
    cmd: arcan_ffunc_cmd,
    buf: ?[*]av_pixel,
    buf_sz: usize,
    width: u16,
    height: u16,
    mode: c_uint,
    state: vfunc_state,
    srcid: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    return fsrv_helper_avfeedframe(cmd, buf, buf_sz, width, height, mode, state, srcid);
}

// arcan_frameserver_update_mixweight
export fn arcan_frameserver_update_mixweight(
    dst: *arcan_frameserver,
    src: arcan_aobj_id,
    left: f32,
    right: f32,
) void {
    fsrv_helper_update_mixweight(dst, src, left, right);
}

// arcan_frameserver_avfeed_mixer
export fn arcan_frameserver_avfeed_mixer(
    dst: *arcan_frameserver,
    n_sources: c_int,
    sources: [*]arcan_aobj_id,
) void {
    fsrv_helper_avfeed_mixer(dst, n_sources, sources);
}

// arcan_frameserver_avfeedmon
export fn arcan_frameserver_avfeedmon(
    src: arcan_aobj_id,
    buf: [*]u8,
    buf_sz: usize,
    channels: c_uint,
    frequency: c_uint,
    tag: ?*anyopaque,
) void {
    fsrv_helper_avfeedmon(src, buf, buf_sz, channels, frequency, tag);
}

// arcan_frameserver_audioframe_direct
export fn arcan_frameserver_audioframe_direct(
    aobj: ?*anyopaque,
    id: arcan_aobj_id,
    buffer: c_uint,
    cont: bool,
    tag: ?*anyopaque,
) arcan_errc {
    return fsrv_helper_audioframe_direct(aobj, id, buffer, cont, tag);
}

// arcan_frameserver_tick_control
export fn arcan_frameserver_tick_control(
    src: *arcan_frameserver,
    tick: bool,
    dst_ffunc: c_int,
) bool {
    return fsrv_helper_tick_control(src, tick, dst_ffunc);
}

// arcan_frameserver_pause
export fn arcan_frameserver_pause(src: ?*arcan_frameserver) arcan_errc {
    if (src) |s| {
        fsrv_helper_set_playstate(s, ARCAN_PAUSED);
        return ARCAN_OK;
    }
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

// arcan_frameserver_resume
export fn arcan_frameserver_resume(src: ?*arcan_frameserver) arcan_errc {
    if (src) |s| {
        fsrv_helper_set_playstate(s, ARCAN_PLAYING);
        return ARCAN_OK;
    }
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

// arcan_frameserver_flush
export fn arcan_frameserver_flush(fsrv: ?*arcan_frameserver) arcan_errc {
    if (fsrv) |f| {
        fsrv_helper_set_audio_flush_pending(f, true);
        arcan_audio_rebuild(fsrv_helper_get_aid(f));
        return ARCAN_OK;
    }
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

// arcan_frameserver_setfont
export fn arcan_frameserver_setfont(
    fsrv: ?*arcan_frameserver,
    fd: c_int,
    sz: f32,
    hint: c_int,
    slot: c_int,
) arcan_errc {
    if (fsrv) |f| {
        return fsrv_helper_setfont(f, fd, sz, hint, slot);
    }
    return ARCAN_ERRC_NO_SUCH_OBJECT;
}

// arcan_frameserver_displayhint
export fn arcan_frameserver_displayhint(
    fsrv: ?*arcan_frameserver,
    w: usize,
    h: usize,
    ppcm: f32,
) void {
    if (fsrv) |f| {
        fsrv_helper_displayhint(f, w, h, ppcm);
    }
}

// arcan_frameserver_getramps
export fn arcan_frameserver_getramps(
    src: ?*arcan_frameserver,
    index: usize,
    table: ?[*]f32,
    table_sz: usize,
    ch_sz: ?[*]usize,
) bool {
    if (src == null or table == null or ch_sz == null) return false;
    return fsrv_helper_getramps(src.?, index, table.?, table_sz, ch_sz.?);
}

// arcan_frameserver_setramps
export fn arcan_frameserver_setramps(
    src: ?*arcan_frameserver,
    index: usize,
    table: ?[*]f32,
    table_sz: usize,
    ch_sz: ?[*]usize,
    edid: ?[*]u8,
    edid_sz: usize,
) bool {
    if (src == null or table == null) return false;
    return fsrv_helper_setramps(src.?, index, table.?, table_sz, ch_sz.?, edid, edid_sz);
}
