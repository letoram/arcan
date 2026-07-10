// Zig port of platform/audio/openal.c
// OpenAL audio platform implementation for arcan.
// Exports all platform_audio_* symbols consumed by arcan_audio.zig.

const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

// POSIX: use al_cabi.zig — a hand-written replacement for the original
// @cImport({AL/al.h, AL/alc.h, arcan_shmif.h, arcan_video.h, ...}) block.
// The no-LLVM self-hosted fork can't run @cImport at all, so we re-export
// arcan types from the existing Zig modules and declare AL/ALC externs
// that the linker resolves against the dl_openal.zig shim.
const c = if (is_freestanding) @import("arcan_boot_compat") else @import("al_cabi.zig");

// Constants

const CONST_MAX_ASAMPLESZ: usize = 1048756;
const ARCAN_AUDIO_SLIMIT: usize = 32;
const ARCAN_ASTREAMBUF_LIMIT: usize = if (is_freestanding) 12 else @intCast(c.ARCAN_SHMIF_ABUFC_LIM);

// Type aliases for readability
const arcan_aobj_id = if (is_freestanding) c_int else c.arcan_aobj_id;
const arcan_vobj_id = if (is_freestanding) i64 else c.arcan_vobj_id;
const arcan_errc = if (is_freestanding) c_int else c.arcan_errc;
const arcan_tickv = c_uint;
const arcan_afunc_cb = ?*const fn (?*anyopaque, arcan_aobj_id, isize, bool, ?*anyopaque) callconv(.c) arcan_errc;
const arcan_monafunc_cb = ?*const fn (arcan_aobj_id, [*c]u8, usize, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
const arcan_again_cb = ?*const fn (f32, ?*anyopaque) callconv(.c) arcan_errc;

// Structs

const arcan_achain = struct {
    t_gain: c_uint = 0,
    d_gain: f32 = 0.0,
    next: ?*arcan_achain = null,
};

const arcan_aobj = struct {
    // shared
    id: arcan_aobj_id = 0,
    refobj: arcan_vobj_id = if (is_freestanding) 0 else c.ARCAN_VIDEO_WORLDID,

    alid: c_uint = 0,
    kind: c_int = if (is_freestanding) 0 else c.AOBJ_INVALID,
    active: bool = false,

    gain: f32 = 0.0,

    transform: ?*arcan_achain = null,

    // AOBJ proxy only
    gproxy: arcan_again_cb = null,

    // AOBJ_STREAM only
    streaming: bool = false,

    // AOBJ sample only
    samplebuf: [*c]u16 = null,

    // openAL Buffering
    n_streambuf: u8 = 0,
    last_used: arcan_tickv = 0,

    streambuf: [ARCAN_ASTREAMBUF_LIMIT]c_uint = [_]c_uint{0} ** ARCAN_ASTREAMBUF_LIMIT,
    streambufmask: [ARCAN_ASTREAMBUF_LIMIT]bool = [_]bool{false} ** ARCAN_ASTREAMBUF_LIMIT,

    used: c_short = 0,

    // global hooks
    feed: arcan_afunc_cb = null,
    monitor: arcan_monafunc_cb = null,
    monitortag: ?*anyopaque = null,
    tag: ?*anyopaque = null,

    // stored as linked list
    next: ?*arcan_aobj = null,
};

const ALCdevice = if (is_freestanding) anyopaque else c.ALCdevice;
const ALCcontext = if (is_freestanding) anyopaque else c.ALCcontext;
const AL_SOURCE_SPATIALIZE_SOFT = if (@hasDecl(c, "AL_SOURCE_SPATIALIZE_SOFT")) c.AL_SOURCE_SPATIALIZE_SOFT else 0x1214;

const arcan_acontext = struct {
    first: ?*arcan_aobj = null,
    context: ?*ALCcontext = null,
    device: ?*ALCdevice = null,

    al_active: bool = false,
    hrtf: bool = false,

    lastid: arcan_aobj_id = 0,
    listener: arcan_vobj_id = c.ARCAN_VIDEO_WORLDID,
    def_gain: f32 = 1.0,

    sample_sources: [ARCAN_AUDIO_SLIMIT]c.ALuint = [_]c.ALuint{0} ** ARCAN_AUDIO_SLIMIT,
    sample_tags: [ARCAN_AUDIO_SLIMIT]isize = [_]isize{0} ** ARCAN_AUDIO_SLIMIT,

    atick_counter: arcan_tickv = 0,

    globalhook: arcan_monafunc_cb = null,
    global_hooktag: ?*anyopaque = null,
};

// Extension function pointers

const Extensions = struct {
    alc_device_pause_soft: ?*const fn (?*ALCdevice) callconv(.c) void = null,
    alc_device_resume_soft: ?*const fn (?*ALCdevice) callconv(.c) void = null,
    alc_device_reopen_soft: ?*const fn (?*ALCdevice, [*c]const c.ALCchar, [*c]const c.ALCint) callconv(.c) c.ALCboolean = null,
};

var extensions = Extensions{};

// Global state

var _current_acontext = arcan_acontext{};
var current_acontext: *arcan_acontext = &_current_acontext;

// Clean math types (bypass @cImport anonymous union nesting)
// These have identical ABI to the C types but expose x/y/z/w directly.
const Vec3 = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };
const Quat = extern struct { x: f32 = 0, y: f32 = 0, z: f32 = 0, w: f32 = 0 };

const SurfOri = extern struct {
    yaw: f32 = 0,
    pitch: f32 = 0,
    roll: f32 = 0,
    quaternion: Quat = .{},
};

const SurfProps = extern struct {
    position: Vec3 = .{},
    scale: Vec3 = .{},
    opa: f32 = 0,
    rotation: SurfOri = .{},
};

// Extern C functions

extern fn platform_is_lwa_mode() bool;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, alignment: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_open_resource(name: [*c]const u8) c.data_source;
extern fn arcan_map_resource(src: *c.data_source, wr: bool) c.map_region;
extern fn arcan_release_resource(src: *c.data_source) void;
extern fn arcan_release_map(region: c.map_region) bool;
extern fn arcan_event_defaultctx() ?*c.struct_arcan_evctx;
extern fn arcan_event_denqueue(ctx: ?*c.struct_arcan_evctx, ev: *const c.struct_arcan_event) c_int;
extern fn arcan_event_enqueue(ctx: ?*c.struct_arcan_evctx, ev: *const c.struct_arcan_event) c_int;
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*c.arcan_vobject;
extern fn arcan_resolve_vidprop(vobj: *c.arcan_vobject, lerp: f32, props: *SurfProps) void;
extern fn arcan_video_properties_at(id: arcan_vobj_id, ticks: c_uint) SurfProps;
extern fn arcan_random(dst: [*c]u8, ntc: usize) void;
extern fn matr_quatf(q: Quat, dst: [*c]f32) [*c]f32;
extern fn mult_matrix_vecf(matrix: [*c]const f32, inv: [*c]const f32, out: [*c]f32) void;

// Memory allocation constants (from arcan_mem.h)
const ARCAN_MEM_ATAG: c_int = c.ARCAN_MEM_ATAG;
const ARCAN_MEM_ABUFFER: c_int = c.ARCAN_MEM_ABUFFER;
const ARCAN_MEM_BZERO: c_int = c.ARCAN_MEM_BZERO;
const ARCAN_MEM_SENSITIVE: c_int = c.ARCAN_MEM_SENSITIVE;
const ARCAN_MEM_STRINGBUF: c_int = c.ARCAN_MEM_STRINGBUF;
const ARCAN_MEMALIGN_NATURAL: c_int = c.ARCAN_MEMALIGN_NATURAL;
const ARCAN_MEMALIGN_PAGE: c_int = c.ARCAN_MEMALIGN_PAGE;

// Internal helper: wrap OpenAL error check

fn _wrap_alError(obj_opt: ?*arcan_aobj, prefix: [*c]const u8) bool {
    const errc = c.alGetError();
    var fallback = arcan_aobj{};
    const obj = obj_opt orelse &fallback;

    // In non-debug builds just return the status
    if (errc == c.AL_NO_ERROR) return true;

    arcan_warning("(openAL): ");
    switch (errc) {
        c.AL_INVALID_NAME => {
            arcan_warning("(%u:%u), %s - bad ID passed to function\n", obj.id, obj.alid, prefix);
        },
        c.AL_INVALID_ENUM => {
            arcan_warning("(%u:%u), %s - bad enum value passed to function\n", obj.id, obj.alid, prefix);
        },
        c.AL_INVALID_VALUE => {
            arcan_warning("(%u:%u), %s - bad value passed to function\n", obj.id, obj.alid, prefix);
        },
        c.AL_INVALID_OPERATION => {
            arcan_warning("(%u:%u), %s - requested operation is not valid\n", obj.id, obj.alid, prefix);
        },
        c.AL_OUT_OF_MEMORY => {
            arcan_warning("(%u:%u), %s - OpenAL out of memory\n", obj.id, obj.alid, prefix);
        },
        else => {
            arcan_warning("(%u:%u), %s - undefined error\n", obj.id, obj.alid, prefix);
        },
    }
    return false;
}

// Internal helper: find aobj from OpenAL source id

fn get_aobj_from_alid(alid: c.ALuint) ?*arcan_aobj {
    var current = current_acontext.first;
    while (current) |cur| {
        if (cur.alid == alid)
            return cur;
        current = cur.next;
    }
    return null;
}

// Internal: allocate a new audio object

fn arcan_audio_alloc(dst: ?*?*arcan_aobj, defer_src: bool) arcan_aobj_id {
    var rv: arcan_aobj_id = c.ARCAN_EID;
    var alid: c.ALuint = c.AL_NONE;
    if (dst) |d| d.* = null;

    if (!defer_src) {
        c.alGenSources(1, &alid);
        c.alSourcef(alid, c.AL_GAIN, current_acontext.def_gain);
        c.alSourcei(@intCast(alid), AL_SOURCE_SPATIALIZE_SOFT, c.AL_TRUE);
        _ = _wrap_alError(null, "audio_alloc(genSources)");
        if (alid == c.AL_NONE)
            return rv;
    }

    const raw_ptr = arcan_alloc_mem(
        @sizeOf(arcan_aobj),
        ARCAN_MEM_ATAG,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return rv;
    const newcell: *arcan_aobj = @ptrCast(@alignCast(raw_ptr));
    newcell.* = arcan_aobj{};

    newcell.alid = alid;
    newcell.gain = current_acontext.def_gain;
    newcell.refobj = c.ARCAN_VIDEO_WORLDID;

    // unlikely event of wrap-around
    newcell.id = current_acontext.lastid;
    current_acontext.lastid += 1;
    if (newcell.id == c.ARCAN_EID)
        newcell.id = 1;

    if (dst) |d| d.* = newcell;

    if (current_acontext.first) |first| {
        var cur = first;
        while (cur.next) |nxt| {
            cur = nxt;
        }
        cur.next = newcell;
    } else {
        current_acontext.first = newcell;
    }

    rv = newcell.id;
    return rv;
}

// Internal: free an audio object by id

fn arcan_audio_free(id: arcan_aobj_id) arcan_errc {
    var rv: arcan_errc = c.ARCAN_ERRC_NO_SUCH_OBJECT;
    var owner: *?*arcan_aobj = &current_acontext.first;
    var current = current_acontext.first;

    // find
    while (current) |cur| {
        if (cur.id == id) break;
        owner = &cur.next;
        current = cur.next;
    }

    // if found, unlink
    if (current) |cur| {
        owner.* = cur.next;

        if (cur.alid != c.AL_NONE) {
            c.alSourceStop(cur.alid);
            c.alDeleteSources(1, &cur.alid);

            if (cur.n_streambuf > 0)
                c.alDeleteBuffers(@intCast(cur.n_streambuf), &cur.streambuf);

            _ = _wrap_alError(null, "audio_free(DeleteBuffers/sources)");
        }
        cur.next = undefined;
        cur.tag = undefined;
        cur.feed = null;
        arcan_mem_free(@ptrCast(cur));

        rv = c.ARCAN_OK;
    }

    return rv;
}

// Internal: load a RIFF/WAVE file

fn arcan_load_wave(fname: [*c]const u8) c.ALuint {
    var rv: c.ALuint = 0;

    var inres = arcan_open_resource(fname);
    if (inres.fd == c.BADFD)
        return rv;

    var inmem = arcan_map_resource(&inres, false);
    if (inmem.unnamed_0.ptr == null) {
        arcan_release_resource(&inres);
        return rv;
    }

    const result = load_wave_inner(&inmem, &rv);
    _ = result;

    _ = arcan_release_map(inmem);
    arcan_release_resource(&inres);

    return rv;
}

fn load_wave_inner(inmem: *c.map_region, rv: *c.ALuint) bool {
    const ptr: [*]const u8 = @ptrCast(inmem.unnamed_0.ptr orelse return false);
    const sz = inmem.sz;

    // only accept well-formed headers
    if (sz < 44) return false;

    if (!mem_eq(ptr, "RIFF", 4)) {
        arcan_warning("load_wave() -- missing RIFF header identifier\n");
        return false;
    }

    if (!mem_eq(ptr + 8, "WAVE", 4)) {
        arcan_warning("load_wave() -- missing WAVE format identifier\n");
        return false;
    }

    // Endianness check (we only support little-endian)
    const kv: u16 = 0x1234;
    const le = @as(*const u8, @ptrCast(&kv)).* == 0x34;
    if (!le) {
        arcan_warning("load_wave(BE) -- big endian swap unimplemented\n");
        return false;
    }

    if (!mem_eq(ptr + 12, "fmt ", 4)) {
        arcan_warning("load_wave() -- missing format chuck ID\n");
        return false;
    }

    var fmt: i16 = undefined;
    var nch: i16 = undefined;
    var bits_ps: u16 = undefined;
    var smplrte: u16 = undefined;
    var nofs: i32 = undefined;

    @memcpy(std.mem.asBytes(&fmt), (ptr + 20)[0..2]);
    @memcpy(std.mem.asBytes(&nch), (ptr + 22)[0..2]);
    @memcpy(std.mem.asBytes(&smplrte), (ptr + 24)[0..2]);
    @memcpy(std.mem.asBytes(&bits_ps), (ptr + 34)[0..2]);
    @memcpy(std.mem.asBytes(&nofs), (ptr + 16)[0..4]);
    nofs += 20;

    if (fmt != 0x001) {
        arcan_warning("load_wave() -- unsupported encoding (%d),only PCM accepted.\n", @as(c_int, fmt));
        return false;
    }

    if (nch != 1 and nch != 2) {
        arcan_warning("load_wave() -- unexpected number of channels (%d).\n", @as(c_int, nch));
        return false;
    }

    if (bits_ps != 8 and bits_ps != 16) {
        arcan_warning("load_wave() -- unsupported bitdepth (%d)\n", @as(c_uint, bits_ps));
        return false;
    }

    if (smplrte != 48000 and smplrte != 44100 and smplrte != 22050 and smplrte != 11025) {
        arcan_warning("load_wave() -- unconventional samplerate (%d).\n", @as(c_uint, smplrte));
    }

    const nofs_u: usize = @intCast(nofs);
    if (nofs_u + 8 > sz) return false;

    if (!mem_eq(ptr + nofs_u, "data", 4)) {
        arcan_warning("load_wave() -- data chunk not found\n");
        return false;
    }

    var nb: i32 = undefined;
    @memcpy(std.mem.asBytes(&nb), (ptr + nofs_u + 4)[0..4]);

    if (nb > @as(i32, CONST_MAX_ASAMPLESZ)) {
        arcan_warning("load_wave() -- sample exceeds compile time limit  (CONST_MAX_ASAMPLESZ %d), truncating.\n", @as(c_int, CONST_MAX_ASAMPLESZ));
        nb = @intCast(CONST_MAX_ASAMPLESZ);
    }

    const nb_u: usize = @intCast(nb);
    if (nb_u > (sz - nofs_u - 4)) {
        arcan_warning("load wave() -- total sample size is larger than the mapped input.\n");
        return false;
    }

    var alfmt: c_int = 0;
    const ofs_start: usize = nofs_u + 8;
    const innb: usize = nb_u;

    const samplebuf_raw = arcan_alloc_mem(nb_u, ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE) orelse return false;
    const samplebuf: [*]u8 = @ptrCast(samplebuf_raw);

    if (bits_ps == 8) {
        alfmt = if (nch == 1) c.AL_FORMAT_MONO8 else c.AL_FORMAT_STEREO8;
        @memcpy(samplebuf[0..nb_u], (ptr + ofs_start)[0..nb_u]);
    } else if (bits_ps == 16) {
        alfmt = if (nch == 1) c.AL_FORMAT_MONO16 else c.AL_FORMAT_STEREO16;
        var remaining = nb;
        var ofs = ofs_start;
        var dst_idx: usize = 0;
        while (remaining > 0) {
            samplebuf[dst_idx] = ptr[ofs];
            samplebuf[dst_idx + 1] = ptr[ofs + 1];
            ofs += 2;
            dst_idx += 2;
            remaining -= 2;
        }
    }

    c.alGenBuffers(1, rv);
    c.alBufferData(rv.*, alfmt, samplebuf, @intCast(innb), @intCast(smplrte));
    _ = _wrap_alError(null, "load_wave(bufferData)");
    arcan_mem_free(samplebuf_raw);

    return true;
}

fn mem_eq(a: [*]const u8, b: [*]const u8, len: usize) bool {
    for (0..len) |i| {
        if (a[i] != b[i]) return false;
    }
    return true;
}

// Internal: get audio object by id

fn arcan_audio_getobj(id: arcan_aobj_id) ?*arcan_aobj {
    var current = current_acontext.first;
    while (current) |cur| {
        if (cur.id == id)
            return cur;
        current = cur.next;
    }
    return null;
}

// Internal: capture feed callback

var capturebuf: ?[*]i16 = null;

fn capturefeed(aobjopaq: ?*anyopaque, id: arcan_aobj_id, buffer: isize, cont: bool, tag_arg: ?*anyopaque) callconv(.c) arcan_errc {
    _ = id;
    _ = cont;
    const aobj: *arcan_aobj = @ptrCast(@alignCast(aobjopaq orelse return c.ARCAN_ERRC_NOTREADY));

    if (buffer < 0)
        return c.ARCAN_ERRC_NOTREADY;

    if (capturebuf == null) {
        const raw = arcan_alloc_mem(1024 * 4, ARCAN_MEM_ABUFFER, ARCAN_MEM_SENSITIVE, ARCAN_MEMALIGN_PAGE) orelse return c.ARCAN_ERRC_NOTREADY;
        capturebuf = @ptrCast(@alignCast(raw));
    }

    var sample: c.ALCint = 0;
    const dev: ?*ALCdevice = @ptrCast(@alignCast(tag_arg));
    c.alcGetIntegerv(dev, c.ALC_CAPTURE_SAMPLES, @sizeOf(c.ALint), &sample);
    if (sample > 1024) sample = 1024;

    if (sample <= 0)
        return c.ARCAN_ERRC_NOTREADY;

    c.alcCaptureSamples(dev, @ptrCast(capturebuf.?), sample);

    if (aobj.monitor) |mon| {
        mon(aobj.id, @ptrCast(capturebuf.?), @intCast(@as(c_uint, @intCast(sample)) << 2),
            c.ARCAN_SHMIF_ACHANNELS, c.ARCAN_SHMIF_SAMPLERATE, aobj.monitortag);
    }

    if (current_acontext.globalhook) |hook| {
        hook(aobj.id, @ptrCast(capturebuf.?), @intCast(@as(c_uint, @intCast(sample)) << 2),
            c.ARCAN_SHMIF_ACHANNELS, c.ARCAN_SHMIF_SAMPLERATE, current_acontext.global_hooktag);
    }

    return c.ARCAN_OK;
}

// Internal: reset gain transform chain

fn reset_chain(dobj: *arcan_aobj) void {
    var current = dobj.transform;
    while (current) |cur| {
        const next = cur.next;
        arcan_mem_free(@ptrCast(cur));
        current = next;
    }
    dobj.transform = null;
}

// Internal: find buffer index

fn find_bufferind(cur: *arcan_aobj, bufnum: c_uint) isize {
    for (0..@as(usize, cur.n_streambuf)) |i| {
        if (cur.streambuf[i] == bufnum)
            return @intCast(i);
    }
    return -1;
}

// Internal: find free buffer index

fn find_freebufferind(cur: *arcan_aobj, tag_it: bool) isize {
    for (0..@as(usize, cur.n_streambuf)) |i| {
        if (cur.streambufmask[i] == false) {
            if (tag_it) {
                cur.used += 1;
                cur.streambufmask[i] = true;
            }
            return @intCast(i);
        }
    }
    return -1;
}

// Internal: refill streaming audio buffers

fn astream_refill(current: *arcan_aobj) void {
    var state: c.ALenum = 0;
    var processed: c.ALint = 0;

    if (current.alid == c.AL_NONE) {
        if (current.feed) |feed| {
            _ = feed(current, @intCast(current.alid), 0, false, current.tag);
        }
        return;
    }

    // stopped or not, dequeue and requeue as many buffers as possible
    c.alGetSourcei(@intCast(current.alid), c.AL_SOURCE_STATE, &state);
    c.alGetSourcei(@intCast(current.alid), c.AL_BUFFERS_PROCESSED, &processed);

    {
        var i: usize = 0;
        while (i < @as(usize, @intCast(processed))) : (i += 1) {
            var buffer: c_uint = 1;
            c.alSourceUnqueueBuffers(current.alid, 1, &buffer);
            const bufferind = find_bufferind(current, buffer);
            if (bufferind == -1) {
                arcan_warning("(audio) unqueue returned unknown buffer, processed (%d)\n", @as(c_int, @intCast(bufferind)));
                continue;
            }

            current.streambufmask[@intCast(bufferind)] = false;
            _ = _wrap_alError(current, "audio_refill(refill:dequeue)");
            current.used -= 1;

            // try to refill the buffer via callback
            if (current.feed) |feed| {
                const rv = feed(current, @intCast(current.alid), @intCast(buffer), i < @as(usize, @intCast(processed)) - 1, current.tag);
                _ = _wrap_alError(current, "audio_refill(refill:buffer)");

                if (rv == c.ARCAN_OK) {
                    c.alSourceQueueBuffers(current.alid, 1, &buffer);
                    current.streambufmask[@intCast(bufferind)] = true;
                    _ = _wrap_alError(current, "audio_refill(refill:queue)");
                    current.used += 1;
                } else if (rv == c.ARCAN_ERRC_NOTREADY) {
                    // goto playback
                    astream_refill_playback(current, state);
                    return;
                } else {
                    // goto cleanup
                    astream_refill_cleanup(current);
                    return;
                }
            }
        }
    }

    // if we're totally empty, try to fill all buffers
    if (current.used < 0) {
        arcan_warning("arcan_audio(), astream_refill: inconsistency with\tinternal vs openAL buffers.\n");
    }

    if (current.used < current.n_streambuf) {
        if (current.feed) |feed| {
            const lim = ARCAN_ASTREAMBUF_LIMIT;
            var i: usize = @intCast(@max(0, current.used));
            while (i < lim) : (i += 1) {
                const ind = find_freebufferind(current, false);
                if (ind == -1) break;
                const ind_u: usize = @intCast(ind);

                const rv = feed(current, @intCast(current.alid), @intCast(current.streambuf[ind_u]),
                    find_freebufferind(current, false) != -1, current.tag);

                if (rv == c.ARCAN_OK) {
                    c.alSourceQueueBuffers(current.alid, 1, &current.streambuf[ind_u]);
                    current.streambufmask[ind_u] = true;
                    current.used += 1;
                } else if (rv == c.ARCAN_ERRC_NOTREADY) {
                    astream_refill_playback(current, state);
                    return;
                } else {
                    astream_refill_cleanup(current);
                    return;
                }
            }
        }
    }

    astream_refill_playback(current, state);
}

fn astream_refill_playback(current: *arcan_aobj, state: c.ALenum) void {
    if (current.used > 0 and state != c.AL_PLAYING) {
        c.alSourcePlay(current.alid);
        _ = _wrap_alError(current, "audio_restart(astream_refill)");
    }
}

fn astream_refill_cleanup(current: *arcan_aobj) void {
    var newevent: c.struct_arcan_event = undefined; @memset(std.mem.asBytes(&newevent), 0);
    newevent.unnamed_0.unnamed_0.category = c.EVENT_AUDIO;
    newevent.unnamed_0.unnamed_0.unnamed_0.aud.kind = c.EVENT_AUDIO_PLAYBACK_FINISHED;
    newevent.unnamed_0.unnamed_0.unnamed_0.aud.source = current.id;
    _ = arcan_event_denqueue(arcan_event_defaultctx(), &newevent);
}

// Internal: update audio source position and orientation from video object

fn aud_pos_orient(v: arcan_vobj_id, listener: bool, alid: c_uint) void {
    if (v == c.ARCAN_VIDEO_WORLDID) return;
    const vobj = arcan_video_getobject(v) orelse return;

    var cur: SurfProps = undefined;
    arcan_resolve_vidprop(vobj, 0.0, &cur);
    const step = arcan_video_properties_at(v, 1);

    // build rotation matrix from quaternion and apply to up and forward
    var fwdv: [4]f32 = undefined;
    var upv: [4]f32 = undefined;
    var orientm: [16]f32 = undefined;

    _ = matr_quatf(cur.rotation.quaternion, &orientm);

    var fwd_in = [4]f32{ 0.0, 0.0, 1.0, 1.0 };
    var up_in = [4]f32{ 0.0, 1.0, 0.0, 1.0 };
    mult_matrix_vecf(&orientm, &fwd_in, &fwdv);
    mult_matrix_vecf(&orientm, &up_in, &upv);

    const dx = step.position.x;
    const dy = step.position.y;
    const dz = step.position.z;
    const px = cur.position.x;
    const py = cur.position.y;
    const pz = cur.position.z;

    if (listener) {
        c.alListener3f(c.AL_POSITION, px, py, pz);
        c.alListener3f(c.AL_VELOCITY, dx, dy, dz);
        var orient_arr = [6]f32{ fwdv[0], fwdv[1], fwdv[2], upv[0], upv[1], upv[2] };
        c.alListenerfv(c.AL_ORIENTATION, &orient_arr);
        return;
    }

    c.alSource3f(alid, c.AL_POSITION, px, py, pz);
    c.alSource3f(alid, c.AL_VELOCITY, dx, dy, dz);
    var orient_arr2 = [6]f32{ fwdv[0], fwdv[1], fwdv[2], upv[0], upv[1], upv[2] };
    c.alSourcefv(alid, c.AL_ORIENTATION, &orient_arr2);
}

// Internal: step a gain transform

fn step_transform(obj: *arcan_aobj) bool {
    if (obj.alid != 0)
        aud_pos_orient(obj.refobj, false, obj.alid);

    const transform = obj.transform orelse return false;

    // OpenAL maps dB to linear
    obj.gain += (transform.d_gain - obj.gain) / @as(f32, @floatFromInt(transform.t_gain));

    transform.t_gain -= 1;
    if (transform.t_gain == 0) {
        obj.gain = transform.d_gain;
        const next = transform.next;
        arcan_mem_free(@ptrCast(transform));
        obj.transform = next;
    }

    return true;
}

// Internal: float to signed 16-bit

fn float_s16(val: f32) i16 {
    if (val < 0.0) {
        return @intFromFloat(-val * -32768.0);
    } else {
        return @intFromFloat(val * 32767.0);
    }
}

// Exported platform_audio_* functions

export fn platform_audio_preinit() void {}

export fn platform_audio_reassign(id: arcan_aobj_id, device: c_int) void {
    _ = id;
    _ = device;
}

const struct_platform_audio_cfg = if (is_freestanding) extern struct { out: ?*anyopaque = null, hrtf: bool = false } else c.struct_platform_audio_cfg;

export fn platform_audio_reconfigure(cfg: struct_platform_audio_cfg, device: c_int) void {
    if (is_freestanding) return;
    _ = device;
    if ((cfg.out != null and extensions.alc_device_reopen_soft != null) or
        (c.alcIsExtensionPresent(current_acontext.device, "ALC_SOFT_HRTF") != 0 and
        cfg.hrtf != current_acontext.hrtf and extensions.alc_device_reopen_soft != null))
    {
        current_acontext.hrtf = cfg.hrtf;
        var attrs = [_]c.ALCint{
            c.ALC_FREQUENCY,       c.ARCAN_SHMIF_SAMPLERATE,
            c.ALC_HRTF_SOFT,       if (cfg.hrtf) c.ALC_TRUE else c.ALC_FALSE,
            0,
        };
        _ = extensions.alc_device_reopen_soft.?(current_acontext.device, cfg.out, &attrs);
    }
}

export fn platform_audio_init(noaudio: bool) bool {
    if (is_freestanding) return false;
    var rv = false;

    // don't support repeated calls without shutting down in between
    if (current_acontext.context == null) {
        var attrs = [_]c.ALCint{
            c.ALC_FREQUENCY, c.ARCAN_SHMIF_SAMPLERATE,
            0,
        };

        if (platform_is_lwa_mode()) {
            current_acontext.device = c.alcOpenDevice("arcan");
            // No arcan OpenAL backend — fall back to default device
            if (current_acontext.device == null)
                current_acontext.device = c.alcOpenDevice(null);
        } else {
            current_acontext.device = c.alcOpenDevice(null);
        }

        if (current_acontext.device == null) return false;

        current_acontext.context = c.alcCreateContext(current_acontext.device, &attrs);
        _ = c.alcMakeContextCurrent(current_acontext.context);

        if (noaudio) {
            c.alListenerf(c.AL_GAIN, 0.0);
        }

        if (c.alcIsExtensionPresent(current_acontext.device, "ALC_SOFT_pause_device") != 0) {
            extensions.alc_device_pause_soft = @alignCast(@ptrCast(
                c.alcGetProcAddress(current_acontext.device, "alcDevicePauseSOFT"),
            ));
            extensions.alc_device_resume_soft = @alignCast(@ptrCast(
                c.alcGetProcAddress(current_acontext.device, "alcDeviceResumeSOFT"),
            ));
        }

        if (c.alcIsExtensionPresent(current_acontext.device, "ALC_SOFT_reopen_device") != 0) {
            extensions.alc_device_reopen_soft = @alignCast(@ptrCast(
                c.alcGetProcAddress(current_acontext.device, "alcReopenDeviceSOFT"),
            ));
        }

        current_acontext.al_active = true;
        rv = true;

        // just give a slightly "random" base so that
        // user scripts don't get locked into hard-coded ids ..
        arcan_random(@ptrCast(std.mem.asBytes(&current_acontext.lastid)), @sizeOf(arcan_aobj_id));
    }

    return rv;
}

export fn platform_audio_suspend() void {
    if (is_freestanding) return;
    var current = current_acontext.first;

    while (current) |cur| {
        if (cur.id != c.AL_NONE)
            _ = platform_audio_pause(cur.id);
        current = cur.next;
    }

    current_acontext.al_active = false;
    if (extensions.alc_device_pause_soft) |pause_fn| {
        pause_fn(current_acontext.device);
    }
}

export fn platform_audio_resume() void {
    if (is_freestanding) return;
    var current = current_acontext.first;

    if (extensions.alc_device_resume_soft) |resume_fn| {
        resume_fn(current_acontext.device);
    }

    while (current) |cur| {
        if (cur.id != c.AL_NONE)
            _ = platform_audio_play(cur.id, false, 1.0, -2);
        current = cur.next;
    }

    current_acontext.al_active = true;
}

export fn platform_audio_tick(ntt: u8) void {
    if (is_freestanding) return;
    if (current_acontext.context == null or !current_acontext.al_active)
        return;

    if (@intFromPtr(c.alcGetCurrentContext()) != @intFromPtr(current_acontext.context))
        _ = c.alcMakeContextCurrent(current_acontext.context);

    _ = platform_audio_refresh();
    aud_pos_orient(current_acontext.listener, true, 0);

    // update time-dependent transformations
    var remaining = ntt;
    while (remaining > 0) : (remaining -= 1) {
        var current = current_acontext.first;

        while (current) |cur| {
            if (step_transform(cur)) {
                if (cur.gproxy) |proxy| {
                    _ = proxy(cur.gain, cur.tag);
                } else if (cur.alid != 0) {
                    c.alSourcef(cur.alid, c.AL_GAIN, cur.gain);
                    _ = _wrap_alError(cur, "audio_tick(source/gain)");
                }
            }
            current = cur.next;
        }

        current_acontext.atick_counter += 1;
    }

    // scan all streaming buffers and free up those no-longer needed
    for (0..ARCAN_AUDIO_SLIMIT) |i| {
        const src = current_acontext.sample_sources[i];
        if (src == 0)
            continue;

        var al_state: c.ALint = 0;
        c.alGetSourcei(@intCast(current_acontext.sample_sources[i]), c.AL_SOURCE_STATE, &al_state);
        if (al_state == c.AL_PLAYING)
            continue;

        // disassociate from the source and then free it
        if (get_aobj_from_alid(src)) |obj| {
            obj.alid = 0;
        }

        var src_copy = src;
        c.alDeleteSources(1, &src_copy);
        current_acontext.sample_sources[i] = 0;

        // when finished playing the sample, fire the tag into an event
        if (current_acontext.sample_tags[i] != 0) {
            const tag_val = current_acontext.sample_tags[i];
            current_acontext.sample_tags[i] = 0;

            var newevent: c.struct_arcan_event = undefined; @memset(std.mem.asBytes(&newevent), 0);
            newevent.unnamed_0.unnamed_0.category = c.EVENT_AUDIO;
            newevent.unnamed_0.unnamed_0.unnamed_0.aud.kind = c.EVENT_AUDIO_PLAYBACK_FINISHED;
            newevent.unnamed_0.unnamed_0.unnamed_0.aud.unnamed_0.otag = tag_val;
            _ = arcan_event_denqueue(arcan_event_defaultctx(), &newevent);
        }
    }
}

export fn platform_audio_refresh() usize {
    if (is_freestanding) return 0;
    if (current_acontext.context == null or !current_acontext.al_active)
        return 0;

    var current = current_acontext.first;
    var rv: usize = 0;

    while (current) |cur| {
        if (cur.kind == c.AOBJ_STREAM or
            cur.kind == c.AOBJ_FRAMESTREAM or
            cur.kind == c.AOBJ_CAPTUREFEED)
        {
            astream_refill(cur);
        }

        _ = _wrap_alError(cur, "audio_refresh()");
        if (cur.used > 0)
            rv += 1;

        current = cur.next;
    }

    return rv;
}

export fn platform_audio_outputs() [*c]const u8 {
    if (is_freestanding) return null;
    if (@hasDecl(c, "ALC_ALL_DEVICES_SPECIFIER")) {
        return c.alcGetString(null, c.ALC_ALL_DEVICES_SPECIFIER);
    }
    return null;
}

export fn platform_audio_shutdown() void {
    if (is_freestanding) return;
    const ctx = current_acontext.context;
    if (ctx == null)
        return;

    c.alcDestroyContext(ctx);
    current_acontext.al_active = false;
    current_acontext.context = null;
    @memset(&current_acontext.sample_sources, 0);
}

export fn platform_audio_rebuild(id: arcan_aobj_id) bool {
    if (is_freestanding) return false;
    const aobj = arcan_audio_getobj(id) orelse return false;
    if (aobj.alid == c.AL_NONE) return false;

    c.alSourceStop(aobj.alid);
    _ = _wrap_alError(null, "audio_rebuild(stop)");

    // drain processed buffers
    while (true) {
        var n: c_int = 0;
        c.alGetSourcei(@intCast(aobj.alid), c.AL_BUFFERS_PROCESSED, &n);
        if (n <= 0) break;

        var buffer: c_uint = 0;
        c.alSourceUnqueueBuffers(aobj.alid, 1, &buffer);
        const bufferind = find_bufferind(aobj, buffer);
        if (bufferind >= 0) {
            aobj.streambufmask[@intCast(bufferind)] = false;
            aobj.used -= 1;
        }
    }

    c.alDeleteSources(1, &aobj.alid);
    c.alGenSources(1, &aobj.alid);
    c.alSourcei(@intCast(aobj.alid), AL_SOURCE_SPATIALIZE_SOFT, c.AL_TRUE);
    c.alSourcef(aobj.alid, c.AL_GAIN, aobj.gain);

    _ = _wrap_alError(null, "audio_rebuild(recreate)");

    return true;
}

export fn platform_audio_hookfeed(id: arcan_aobj_id, tag: ?*anyopaque, hookfun: arcan_monafunc_cb, oldtag: ?*?*anyopaque) bool {
    const aobj = arcan_audio_getobj(id) orelse return false;

    if (oldtag) |ot| {
        ot.* = aobj.monitortag;
    }

    aobj.monitor = hookfun;
    aobj.monitortag = tag;

    return true;
}

export fn platform_audio_load_sample(fname: [*c]const u8, gain: f32, err: ?*arcan_errc) arcan_aobj_id {
    if (is_freestanding) return 0;
    var aobj: ?*arcan_aobj = null;
    const rid = arcan_audio_alloc(&aobj, true);

    if (rid == c.ARCAN_EID) {
        if (err) |e| e.* = c.ARCAN_ERRC_OUT_OF_SPACE;
        return c.ARCAN_EID;
    }

    const al_id = arcan_load_wave(fname);
    if (al_id == c.AL_NONE) {
        if (err) |e| e.* = c.ARCAN_ERRC_BAD_RESOURCE;
        _ = arcan_audio_free(rid);
        return c.ARCAN_EID;
    }

    const obj = aobj.?;
    obj.kind = c.AOBJ_SAMPLE;
    obj.gain = gain;
    obj.n_streambuf = 1;
    obj.streambuf[0] = al_id;
    obj.used = 1;

    if (err) |e| e.* = c.ARCAN_OK;

    return rid;
}

export fn platform_audio_sample_buffer(buffer: [*c]f32, elems: usize, channels: c_int, samplerate: c_int, fmt_specifier: [*c]const u8) arcan_aobj_id {
    if (is_freestanding) return 0;
    _ = fmt_specifier;
    var aobj: ?*arcan_aobj = null;
    const rid = arcan_audio_alloc(&aobj, true);
    var al_id: c.ALuint = 0;

    if (rid == c.ARCAN_EID)
        return c.ARCAN_EID;

    c.alGenBuffers(1, &al_id);
    if (c.alcIsExtensionPresent(current_acontext.device, "AL_EXT_float32") == 0) {
        const samplebuf_raw = arcan_alloc_mem(
            elems * 2,
            ARCAN_MEM_ABUFFER,
            0,
            ARCAN_MEMALIGN_PAGE,
        ) orelse return c.ARCAN_EID;
        const samplebuf: [*]i16 = @ptrCast(@alignCast(samplebuf_raw));

        for (0..elems) |i| {
            samplebuf[i] = float_s16(buffer[i]);
        }

        c.alBufferData(al_id, if (channels == 1) c.AL_FORMAT_MONO16 else c.AL_FORMAT_STEREO16,
            @ptrCast(samplebuf), @intCast(elems * 2), samplerate);
        arcan_mem_free(samplebuf_raw);
    } else {
        const fmt = c.alGetEnumValue(
            if (channels == 1) "AL_FORMAT_MONO_FLOAT32" else "AL_FORMAT_STEREO_FLOAT32",
        );
        c.alBufferData(al_id, fmt, @ptrCast(buffer), @intCast(elems * @sizeOf(f32)), samplerate);
    }

    const obj = aobj.?;
    obj.kind = c.AOBJ_SAMPLE;
    obj.gain = 1.0;
    obj.n_streambuf = 1;
    obj.streambuf[0] = al_id;
    obj.used = 1;

    return rid;
}

export fn platform_audio_alterfeed(id: arcan_aobj_id, cb: arcan_afunc_cb) bool {
    const obj = arcan_audio_getobj(id) orelse return false;

    if (cb == null)
        return false;

    obj.feed = cb;
    return true;
}

export fn platform_audio_feed(feed: arcan_afunc_cb, tag: ?*anyopaque, errc: ?*arcan_errc) arcan_aobj_id {
    if (is_freestanding) return 0;
    var aobj: ?*arcan_aobj = null;
    const rid = arcan_audio_alloc(&aobj, true);

    const obj = aobj orelse {
        if (errc) |e| e.* = c.ARCAN_ERRC_OUT_OF_SPACE;
        return c.ARCAN_EID;
    };

    obj.alid = c.AL_NONE;
    obj.streaming = true;
    obj.tag = tag;
    obj.n_streambuf = @intCast(ARCAN_ASTREAMBUF_LIMIT);
    obj.feed = feed;
    obj.gain = 1.0;
    obj.kind = c.AOBJ_STREAM;

    if (errc) |e| e.* = c.ARCAN_OK;
    return rid;
}

export fn platform_audio_kind(id: arcan_aobj_id) c_int {
    if (is_freestanding) return 0;
    const aobj = arcan_audio_getobj(id);
    return if (aobj) |obj| obj.kind else c.AOBJ_INVALID;
}

export fn platform_audio_stop(id: arcan_aobj_id) bool {
    if (is_freestanding) return false;
    const dobj = arcan_audio_getobj(id) orelse return false;

    dobj.kind = c.AOBJ_INVALID;
    dobj.feed = null;

    _ = arcan_audio_free(id);

    var newevent: c.struct_arcan_event = undefined; @memset(std.mem.asBytes(&newevent), 0);
    newevent.unnamed_0.unnamed_0.category = c.EVENT_AUDIO;
    newevent.unnamed_0.unnamed_0.unnamed_0.aud.kind = c.EVENT_AUDIO_OBJECT_GONE;
    newevent.unnamed_0.unnamed_0.unnamed_0.aud.source = id;

    _ = arcan_event_enqueue(arcan_event_defaultctx(), &newevent);
    return true;
}

export fn platform_audio_play(id: arcan_aobj_id, gain_override: bool, gain: f32, tag: isize) bool {
    if (is_freestanding) return false;
    const aobj = arcan_audio_getobj(id) orelse return false;

    // for aobj sample, just find a free sample slot (if any) and
    // attach the buffer already part of the aobj
    if (aobj.kind == c.AOBJ_SAMPLE) {
        for (0..ARCAN_AUDIO_SLIMIT) |i| {
            if (current_acontext.sample_sources[i] == 0) {
                c.alGenSources(1, &current_acontext.sample_sources[i]);
                aobj.alid = current_acontext.sample_sources[i];
                c.alSourcef(aobj.alid, c.AL_GAIN, if (gain_override) gain else aobj.gain);
                c.alSourcei(@intCast(aobj.alid), AL_SOURCE_SPATIALIZE_SOFT, c.AL_TRUE);

                // make sure any positioner is applied immediately
                aud_pos_orient(aobj.refobj, false, aobj.alid);

                // remember any scripting hook backreference tag
                current_acontext.sample_tags[i] = tag;
                _ = _wrap_alError(aobj, "load_sample(alSource)");

                // queue for playback and mark as playing
                c.alSourceQueueBuffers(aobj.alid, 1, &aobj.streambuf[0]);
                _ = _wrap_alError(aobj, "load_sample(alQueue)");
                c.alSourcePlay(aobj.alid);
                break;
            }
        }
    }
    // some kind of streaming source, can't play if it is already active
    else if (aobj.active == false and aobj.alid != c.AL_NONE) {
        c.alSourcePlay(aobj.alid);
        _ = _wrap_alError(aobj, "play(alSourcePlay)");
        aobj.active = true;
    }

    return true;
}

export fn platform_audio_pause(id: arcan_aobj_id) bool {
    if (is_freestanding) return false;
    const dobj = arcan_audio_getobj(id) orelse return false;

    if (dobj.alid != c.AL_NONE) {
        c.alSourceStop(dobj.alid);
        _ = _wrap_alError(dobj, "audio_pause(get/unqueue/stop)");
        dobj.active = false;
        return true;
    }

    return false;
}

export fn platform_audio_rewind(id: arcan_aobj_id) bool {
    if (is_freestanding) return false;
    const aobj = arcan_audio_getobj(id) orelse return false;

    if (aobj.alid != c.AL_NONE) {
        // TODO Implement OpenAL rewind
        return true;
    }

    return false;
}

export fn platform_audio_capturelist(capturelist_ptr: [*c][*c]u8) void {
    if (is_freestanding) return;
    _ = capturelist_ptr;
    // convert from ALs list format to NULL terminated array of strings
    var list: [*c]const u8 = c.alcGetString(null, c.ALC_CAPTURE_DEVICE_SPECIFIER);
    if (list == null) return;
    const base = list;

    var elemc: usize = 0;
    while (list[0] != 0) {
        var len: usize = 0;
        while (list[len] != 0) : (len += 1) {}
        if (len > 0) elemc += 1;
        list += len + 1;
    }

    const raw = arcan_alloc_mem(
        @sizeOf([*c]u8) * (elemc + 1),
        ARCAN_MEM_STRINGBUF,
        0,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return;
    const cl: [*][*c]u8 = @ptrCast(@alignCast(raw));

    elemc = 0;
    list = base;
    while (list[0] != 0) {
        var len: usize = 0;
        while (list[len] != 0) : (len += 1) {}
        if (len > 0) {
            cl[elemc] = c.strdup(list);
            elemc += 1;
        }
        list += len + 1;
    }
    cl[elemc] = null;
}

export fn platform_audio_capturefeed(identifier: [*c]const u8) arcan_aobj_id {
    if (is_freestanding) return 0;
    var dstobj: ?*arcan_aobj = null;
    const capture: ?*ALCdevice = c.alcCaptureOpenDevice(
        identifier,
        c.ARCAN_SHMIF_SAMPLERATE,
        c.AL_FORMAT_STEREO16,
        65536,
    );
    _ = arcan_audio_alloc(&dstobj, false);

    if (_wrap_alError(dstobj, "capture-device")) {
        if (dstobj) |obj| {
            obj.streaming = true;
            obj.gain = 1.0;
            obj.kind = c.AOBJ_CAPTUREFEED;
            obj.n_streambuf = @intCast(ARCAN_ASTREAMBUF_LIMIT);
            obj.feed = capturefeed;
            obj.tag = @ptrCast(capture);

            c.alGenBuffers(@intCast(obj.n_streambuf), &obj.streambuf);
            c.alcCaptureStart(capture);
            return obj.id;
        }
    }

    arcan_warning("arcan_audio_capturefeed() - could get audio lock\n");
    if (capture) |cap| {
        c.alcCaptureStop(cap);
        _ = c.alcCaptureCloseDevice(cap);
    }

    if (dstobj) |obj| {
        _ = arcan_audio_free(obj.id);
    }

    return c.ARCAN_EID;
}

export fn platform_audio_setgain(id: arcan_aobj_id, gain: f32, time: u16) bool {
    if (is_freestanding) return false;
    if (id == c.ARCAN_EID) {
        current_acontext.def_gain = gain;
        return true;
    }

    const dobj = arcan_audio_getobj(id) orelse return false;

    // immediately
    if (time == 0) {
        reset_chain(dobj);
        dobj.gain = gain;

        if (dobj.gproxy) |proxy| {
            _ = proxy(dobj.gain, dobj.tag);
        } else if (dobj.alid != 0) {
            c.alSourcef(dobj.alid, c.AL_GAIN, gain);
            _ = _wrap_alError(dobj, "audio_setgain(getSource/source)");
        }
    } else {
        // walk to end of transform chain
        var dptr: *?*arcan_achain = &dobj.transform;
        while (dptr.*) |chain| {
            dptr = &chain.next;
        }

        const raw = arcan_alloc_mem(
            @sizeOf(arcan_achain),
            ARCAN_MEM_ATAG,
            0,
            ARCAN_MEMALIGN_NATURAL,
        ) orelse return false;
        const new_chain: *arcan_achain = @ptrCast(@alignCast(raw));
        new_chain.* = arcan_achain{};
        new_chain.next = null;
        new_chain.t_gain = time;
        new_chain.d_gain = gain;
        dptr.* = new_chain;
    }

    return true;
}

export fn platform_audio_getgain(id: arcan_aobj_id, gain: ?*f32) bool {
    if (is_freestanding) return false;
    if (id == c.ARCAN_EID) {
        if (gain) |g| g.* = current_acontext.def_gain;
        return true;
    }

    const dobj = arcan_audio_getobj(id) orelse return false;

    if (gain) |g| g.* = dobj.gain;

    return true;
}

export fn platform_audio_buffer(aobjopaq: ?*anyopaque, buffer: isize, audbuf: ?*anyopaque, abufs: usize, channels: c_uint, samplerate: c_uint, tag: ?*anyopaque) void {
    if (is_freestanding) return;
    _ = tag;
    const aobj: *arcan_aobj = @ptrCast(@alignCast(aobjopaq orelse return));

    // even if the AL subsystem should fail, our monitors and globalhook
    // can still work (so record, streaming etc. doesn't cascade)
    if (aobj.monitor) |mon| {
        mon(aobj.id, @ptrCast(audbuf), abufs, channels, samplerate, aobj.monitortag);
    }

    if (current_acontext.globalhook) |hook| {
        hook(aobj.id, @ptrCast(audbuf), abufs, channels, samplerate, current_acontext.global_hooktag);
    }

    // the audio system can bounce back in the case of many allocations
    // exceeding what can be mixed internally
    if (aobj.alid == c.AL_NONE) {
        c.alGenSources(1, &aobj.alid);
        c.alGenBuffers(@intCast(aobj.n_streambuf), &aobj.streambuf);
        c.alSourcef(aobj.alid, c.AL_GAIN, aobj.gain);

        c.alSourcei(@intCast(aobj.alid), AL_SOURCE_SPATIALIZE_SOFT, c.AL_TRUE);

        c.alSourceQueueBuffers(aobj.alid, 1, &aobj.streambuf[0]);
        aobj.streambufmask[0] = true;
        aobj.used += 1;
        c.alSourcePlay(aobj.alid);

        _ = _wrap_alError(null, "audio_feed(genBuffers)");
    } else if (aobj.gproxy == null) {
        aobj.last_used = current_acontext.atick_counter;
        c.alBufferData(@intCast(buffer), if (channels == 2) c.AL_FORMAT_STEREO16 else c.AL_FORMAT_MONO16,
            audbuf, @intCast(abufs), @intCast(samplerate));
    }
}

export fn platform_audio_aid_refresh(aid: arcan_aobj_id) void {
    if (arcan_audio_getobj(aid)) |obj| {
        astream_refill(obj);
    }
}

// very inefficient, but the set of IDs to delete is reasonably small
export fn platform_audio_purge(save: [*c]arcan_aobj_id, save_count: usize) void {
    if (is_freestanding) return;
    var previous: *?*arcan_aobj = &_current_acontext.first;
    var current = _current_acontext.first;

    while (current) |cur| {
        var match = false;

        for (0..save_count) |i| {
            if (save[i] == cur.id) {
                match = true;
                break;
            }
        }

        const next = cur.next;
        if (!match) {
            previous.* = next;
            if (cur.feed) |feed| {
                _ = feed(cur, cur.id, -1, false, cur.tag);
            }

            _ = _wrap_alError(cur, "audio_stop(stop)");

            if (cur.alid != c.AL_NONE) {
                c.alSourceStop(cur.alid);
                c.alDeleteSources(1, &cur.alid);

                if (cur.n_streambuf > 0)
                    c.alDeleteBuffers(@intCast(cur.n_streambuf), &cur.streambuf);
            }

            arcan_mem_free(@ptrCast(cur));
        } else {
            previous = &cur.next;
        }

        current = next;
    }
}

export fn platform_audio_listener(vid: arcan_vobj_id) void {
    if (is_freestanding) return;
    current_acontext.listener = vid;
    if (vid == c.ARCAN_VIDEO_WORLDID) {
        c.alListener3f(c.AL_POSITION, 0.0, 0.0, 0.0);
        c.alListener3f(c.AL_VELOCITY, 0.0, 0.0, 0.0);
    }
}

export fn platform_audio_position(id: arcan_aobj_id, vid: arcan_vobj_id) void {
    if (is_freestanding) return;
    const aobj = arcan_audio_getobj(id) orelse return;

    if (vid == c.ARCAN_VIDEO_WORLDID) {
        c.alSource3f(aobj.alid, c.AL_POSITION, 0.0, 0.0, 0.0);
        c.alListener3f(c.AL_VELOCITY, 0.0, 0.0, 0.0);
    }

    aobj.refobj = vid;
}
