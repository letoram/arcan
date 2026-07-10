// Zig port of engine/arcan_audio.c
// Audio management: delegates to platform_audio_* functions.
// Only C shim: arcan_audio_warn.c for the arcan_warning varargs call.

const arcan_errc = i8;
const arcan_aobj_id = c_int;
const arcan_vobj_id = i64;
const ARCAN_OK: arcan_errc = 0;
const ARCAN_ERRC_NO_SUCH_OBJECT: arcan_errc = -7;
const ARCAN_ERRC_NOAUDIO: arcan_errc = -11;
const ARCAN_ERRC_BAD_ARGUMENT: arcan_errc = -5;
const ARCAN_EID: arcan_aobj_id = 0;

const arcan_afunc_cb = ?*const fn (?*anyopaque, arcan_aobj_id, c_uint, bool, ?*anyopaque) callconv(.c) arcan_errc;
const arcan_monafunc_cb = ?*const fn (arcan_aobj_id, [*c]u8, usize, c_uint, c_uint, ?*anyopaque) callconv(.c) void;

const aobj_kind = enum(c_int) {
    AOBJ_INVALID = 0,
    AOBJ_STREAM = 1,
    AOBJ_SAMPLE = 2,
    AOBJ_FRAMESTREAM = 3,
    AOBJ_CAPTUREFEED = 4,
};

const arcan_audio_cfg = extern struct {
    hrtf: bool,
    out: [*c]const u8,
};

const platform_audio_cfg = extern struct {
    hrtf: bool,
    scan: bool,
    out: [*c]const u8,
};

// Platform audio externs — provided by the audio platform implementation
extern fn platform_audio_alterfeed(id: arcan_aobj_id, cb: arcan_afunc_cb) bool;
extern fn platform_audio_init(nosound: bool) bool;
extern fn platform_audio_shutdown() void;
extern fn platform_audio_play(id: arcan_aobj_id, gain_override: bool, gain: f32, tag: isize) bool;
extern fn platform_audio_sample_buffer(buffer: [*c]f32, elems: usize, channels: c_int, samplerate: c_int, fmt: [*c]const u8) arcan_aobj_id;
extern fn platform_audio_load_sample(fname: [*c]const u8, gain: f32, err: *arcan_errc) arcan_aobj_id;
extern fn platform_audio_hookfeed(id: arcan_aobj_id, tag: ?*anyopaque, hookfun: arcan_monafunc_cb, oldtag: *?*anyopaque) bool;
extern fn platform_audio_feed(feed: arcan_afunc_cb, tag: ?*anyopaque, errc: *arcan_errc) arcan_aobj_id;
extern fn platform_audio_rebuild(id: arcan_aobj_id) bool;
extern fn platform_audio_kind(id: arcan_aobj_id) aobj_kind;
extern fn platform_audio_suspend() void;
extern fn platform_audio_resume() void;
extern fn platform_audio_pause(id: arcan_aobj_id) bool;
extern fn platform_audio_rewind(id: arcan_aobj_id) bool;
extern fn platform_audio_stop(id: arcan_aobj_id) bool;
extern fn platform_audio_getgain(id: arcan_aobj_id, gain: *f32) bool;
extern fn platform_audio_setgain(id: arcan_aobj_id, gain: f32, time: u16) bool;
extern fn platform_audio_buffer(aobj: ?*anyopaque, buffer: isize, audbuf: ?*anyopaque, abufs: usize, channels: c_uint, samplerate: c_uint, tag: ?*anyopaque) void;
extern fn platform_audio_aid_refresh(aid: arcan_aobj_id) void;
extern fn platform_audio_capturelist(list: [*c][*c]u8) void;
extern fn platform_audio_capturefeed(dev: [*c]const u8) arcan_aobj_id;
extern fn platform_audio_refresh() usize;
extern fn platform_audio_tick(ntt: u8) void;
extern fn platform_audio_purge(ids: [*c]arcan_aobj_id, nids: usize) void;
extern fn platform_audio_listener(vid: arcan_vobj_id) void;
extern fn platform_audio_reconfigure(cfg: platform_audio_cfg, device: c_int) void;
extern fn platform_audio_outputs() [*c]const u8;
extern fn platform_audio_position(id: arcan_aobj_id, vid: arcan_vobj_id) void;

// Direct varargs call to arcan_warning (no C shim needed)
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

// C extern for memory free (used in capturelist)
extern fn arcan_mem_free(ptr: ?*anyopaque) void;

export fn arcan_audio_alterfeed(id: arcan_aobj_id, cb: arcan_afunc_cb) arcan_errc {
    return if (platform_audio_alterfeed(id, cb)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_setup(nosound: bool) arcan_errc {
    if (nosound) {
        arcan_warning("arcan_audio_init(nosound)\n");
    }
    return if (platform_audio_init(nosound)) ARCAN_OK else ARCAN_ERRC_NOAUDIO;
}

export fn arcan_audio_shutdown() arcan_errc {
    platform_audio_shutdown();
    return ARCAN_OK;
}

export fn arcan_audio_play(id: arcan_aobj_id, gain_override: bool, gain: f32, tag: isize) arcan_errc {
    return if (platform_audio_play(id, gain_override, gain, tag)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_sample_buffer(buffer: [*c]f32, elems: usize, channels: c_int, samplerate: c_int, fmt: [*c]const u8) arcan_aobj_id {
    if (buffer == null or elems == 0 or channels <= 0 or channels > 2 or elems % @as(usize, @intCast(channels)) != 0)
        return ARCAN_EID;
    return platform_audio_sample_buffer(buffer, elems, channels, samplerate, fmt);
}

export fn arcan_audio_load_sample(fname: [*c]const u8, gain: f32, err: *arcan_errc) arcan_aobj_id {
    if (fname == null) {
        err.* = ARCAN_ERRC_BAD_ARGUMENT;
        return ARCAN_EID;
    }
    return platform_audio_load_sample(fname, gain, err);
}

export fn arcan_audio_hookfeed(id: arcan_aobj_id, tag: ?*anyopaque, hookfun: arcan_monafunc_cb, oldtag: *?*anyopaque) arcan_errc {
    return if (platform_audio_hookfeed(id, tag, hookfun, oldtag)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_feed(feed: arcan_afunc_cb, tag: ?*anyopaque, errc: *arcan_errc) arcan_aobj_id {
    return platform_audio_feed(feed, tag, errc);
}

export fn arcan_audio_rebuild(id: arcan_aobj_id) arcan_errc {
    return if (platform_audio_rebuild(id)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_kind(id: arcan_aobj_id) aobj_kind {
    return platform_audio_kind(id);
}

export fn arcan_audio_suspend() arcan_errc {
    platform_audio_suspend();
    return ARCAN_OK;
}

export fn arcan_audio_resume() arcan_errc {
    platform_audio_resume();
    return ARCAN_OK;
}

export fn arcan_audio_pause(id: arcan_aobj_id) arcan_errc {
    return if (platform_audio_pause(id)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_rewind(id: arcan_aobj_id) arcan_errc {
    return if (platform_audio_rewind(id)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_stop(id: arcan_aobj_id) arcan_errc {
    return if (platform_audio_stop(id)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_getgain(id: arcan_aobj_id, gain: *f32) arcan_errc {
    return if (platform_audio_getgain(id, gain)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_setgain(id: arcan_aobj_id, gain: f32, time: u16) arcan_errc {
    return if (platform_audio_setgain(id, gain, time)) ARCAN_OK else ARCAN_ERRC_NO_SUCH_OBJECT;
}

export fn arcan_audio_buffer(aobj: ?*anyopaque, buffer: isize, audbuf: ?*anyopaque, abufs: usize, channels: c_uint, samplerate: c_uint, tag: ?*anyopaque) void {
    platform_audio_buffer(aobj, buffer, audbuf, abufs, channels, samplerate, tag);
}

export fn arcan_aid_refresh(aid: arcan_aobj_id) void {
    platform_audio_aid_refresh(aid);
}

var capturelist: [*c][*c]u8 = null;

export fn arcan_audio_capturelist() [*c][*c]u8 {
    // free possibly previous result
    if (capturelist != null) {
        var cur = capturelist;
        while (cur[0] != null) {
            arcan_mem_free(cur[0]);
            cur[0] = null;
            cur += 1;
        }
        arcan_mem_free(@ptrCast(capturelist));
    }
    platform_audio_capturelist(capturelist);
    return capturelist;
}

export fn arcan_audio_capturefeed(dev: [*c]const u8) arcan_aobj_id {
    return platform_audio_capturefeed(dev);
}

export fn arcan_audio_refresh() usize {
    return platform_audio_refresh();
}

export fn arcan_audio_tick(ntt: u8) void {
    platform_audio_tick(ntt);
}

export fn arcan_audio_purge(ids: [*c]arcan_aobj_id, nids: usize) void {
    platform_audio_purge(ids, nids);
}

export fn arcan_audio_listener(vid: arcan_vobj_id) void {
    platform_audio_listener(vid);
}

export fn arcan_audio_reconfigure(cfg: arcan_audio_cfg) c_int {
    const incfg = platform_audio_cfg{
        .hrtf = cfg.hrtf,
        .scan = false,
        .out = cfg.out,
    };
    platform_audio_reconfigure(incfg, 0);
    return 0;
}

export fn arcan_audio_scan_devices() [*c]const u8 {
    return platform_audio_outputs();
}

export fn arcan_audio_position(id: arcan_aobj_id, vid: arcan_vobj_id) void {
    platform_audio_position(id, vid);
}
