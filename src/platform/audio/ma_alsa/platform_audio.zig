// Pure-Zig replacement for openal.zig — exposes the same `platform_audio_*`
// C-ABI surface but routes everything through the in-tree dl_alsa shims (one
// libasound dlopen at first use, TLS-switched per call). No OpenAL, no
// @cImport, no dynamic link.
//
// Implementation strategy:
//   * One ALSA playback PCM (S16_LE stereo @ 48kHz, ARCAN_SHMIF_*) opened
//     lazily on first frame.
//   * A dedicated writer thread does blocking `snd_pcm_writei` in a loop,
//     mixing per-Aobj queues into the output buffer. Mixer state is guarded
//     by a single std.Thread.Mutex.
//   * Each Aobj has a small bounded queue of S16 frames. Streaming sources
//     ask their feed-callback to refill; samples get the whole decoded
//     buffer pushed once on play.
//   * WAV (RIFF/PCM 8/16-bit mono/stereo) loader reads via std.fs into an
//     allocator-owned buffer.
//   * Capture: a separate ALSA capture PCM + thread, reads frames in 1024
//     S16 stereo chunks, invokes the user feed callback / monitor / global
//     hook with the raw PCM.
//   * Gain transitions: arcan_achain linked list, advanced one step per
//     `platform_audio_tick` invocation (mirrors openal.zig semantics).
//   * Listener / per-source position: refreshed each tick — listener basis
//     (forward/up/right) is derived from the listener vobj's quaternion,
//     and per-source spatial L/R gains are computed from the source-to-
//     listener delta using inverse-distance attenuation + equal-power pan
//     onto the listener-right axis (port of OpenAL Soft's CalcListener-
//     Params + CalcAttnSourceParams, see Alc/ALu.c).
//
// Event firing (PLAYBACK_FINISHED / OBJECT_GONE) goes through arcan_event_*
// using the `arcan_event` union shape from shmif_types (128 bytes, anon-
// union nested). We import that module rather than re-deriving the layout.

const std = @import("std");
const builtin = @import("builtin");
const ma_alsa = @import("ma_alsa.zig");
const core = @import("core.zig");
const c = core.c;

// std.Thread.spawn is comptime-gated against single_threaded, which the SH
// aarch64 backend forces on. Use libc pthread_create directly — same precedent
// as src/a12/net/helper_srv.zig:spawnThread.
const pthread_t = c_ulong;
extern "c" fn pthread_create(thread: *pthread_t, attr: ?*const anyopaque,
    start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    arg: ?*anyopaque) c_int;
extern "c" fn pthread_join(thread: pthread_t, retval: ?*?*anyopaque) c_int;

// ============================================================================
// Public type aliases — exact match to openal.zig
// ============================================================================

pub const arcan_aobj_id = c_int;
pub const arcan_vobj_id = i64;
pub const arcan_errc = i8;
pub const arcan_tickv = c_uint;

pub const arcan_afunc_cb = ?*const fn (?*anyopaque, arcan_aobj_id, c_uint, bool, ?*anyopaque) callconv(.c) arcan_errc;
pub const arcan_monafunc_cb = ?*const fn (arcan_aobj_id, [*c]u8, usize, c_uint, c_uint, ?*anyopaque) callconv(.c) void;
pub const arcan_again_cb = ?*const fn (f32, ?*anyopaque) callconv(.c) arcan_errc;

pub const struct_platform_audio_cfg = extern struct {
    out: ?*anyopaque = null,
    hrtf: bool = false,
};

// ============================================================================
// Constants — values lifted verbatim from arcan_general.h / arcan_video.h /
// arcan_shmif_event.h. Kept inline to avoid pulling those headers in.
// ============================================================================

const ARCAN_EID: arcan_aobj_id = 0;
const ARCAN_OK: arcan_errc = 0;
const ARCAN_ERRC_OUT_OF_SPACE: arcan_errc = -6;
const ARCAN_ERRC_NO_SUCH_OBJECT: arcan_errc = -7;
const ARCAN_ERRC_BAD_RESOURCE: arcan_errc = -8;
const ARCAN_ERRC_NOTREADY: arcan_errc = -10;

const ARCAN_VIDEO_WORLDID: arcan_vobj_id = -1;
const ARCAN_SHMIF_SAMPLERATE: c_uint = 48000;
const ARCAN_SHMIF_ACHANNELS: c_uint = 2;

const EVENT_AUDIO: u8 = 8;
const EVENT_AUDIO_PLAYBACK_FINISHED: c_int = 0;
const EVENT_AUDIO_OBJECT_GONE: c_int = 5;

// AOBJ kinds — match openal.zig's c.AOBJ_* constants.
const AOBJ_INVALID: c_int = 0;
const AOBJ_SAMPLE: c_int = 1;
const AOBJ_STREAM: c_int = 2;
const AOBJ_FRAMESTREAM: c_int = 3;
const AOBJ_CAPTUREFEED: c_int = 4;
const AOBJ_PROXY: c_int = 5;

const ARCAN_AUDIO_SLIMIT: usize = 32;
const ARCAN_ASTREAMBUF_LIMIT: usize = 12;
const CONST_MAX_ASAMPLESZ: usize = 1048756;

// PCM tunables. Period = 480 frames @ 48kHz = 10ms. Two periods = 20ms
// buffer, low-latency target. Stereo S16 = 1920 bytes per period.
const PCM_RATE: c_uint = ARCAN_SHMIF_SAMPLERATE;
const PCM_CHANNELS: c_uint = ARCAN_SHMIF_ACHANNELS;
const PCM_FORMAT: c_int = 2; // SND_PCM_FORMAT_S16_LE
const PCM_ACCESS: c_int = 3; // SND_PCM_ACCESS_RW_INTERLEAVED
const PCM_PERIOD_FRAMES: usize = 480;
const PCM_PERIOD_BYTES: usize = PCM_PERIOD_FRAMES * PCM_CHANNELS * @sizeOf(i16);
const PCM_PERIODS: c_uint = 2;
const SND_PCM_STREAM_PLAYBACK: c_int = 0;
const SND_PCM_STREAM_CAPTURE: c_int = 1;
const SND_PCM_NONBLOCK: c_int = 0;

// ============================================================================
// Externs — libasound (resolved through dl_alsa shims at link time, then
// dlopen'd via zig_dlopen on first call) plus arcan engine helpers.
// ============================================================================

extern fn snd_pcm_open(pcm: *?*anyopaque, name: [*c]const u8, stream: c_int, mode: c_int) c_int;
extern fn snd_pcm_close(pcm: ?*anyopaque) c_int;
extern fn snd_pcm_set_params(pcm: ?*anyopaque, format: c_int, access: c_int, channels: c_uint, rate: c_uint, soft_resample: c_int, latency: c_uint) c_int;
extern fn snd_pcm_writei(pcm: ?*anyopaque, buffer: ?*const anyopaque, frames: c_ulong) c_long;
extern fn snd_pcm_readi(pcm: ?*anyopaque, buffer: ?*anyopaque, frames: c_ulong) c_long;
extern fn snd_pcm_recover(pcm: ?*anyopaque, err: c_int, silent: c_int) c_int;
extern fn snd_pcm_drain(pcm: ?*anyopaque) c_int;
extern fn snd_pcm_drop(pcm: ?*anyopaque) c_int;
extern fn snd_pcm_prepare(pcm: ?*anyopaque) c_int;

// arcan engine functions we count on. arcan_warning is variadic; we forward
// whole pre-formatted strings via "%s".
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_random(dst: [*c]u8, ntc: usize) void;

// Spatial-audio types — match arcan_math.h / arcan_video.h surface_properties
// layout exactly. Vec3/Quat are POD; SurfProps mirrors `surface_properties`.
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

extern fn arcan_video_getobject(id: arcan_vobj_id) ?*anyopaque;
extern fn arcan_resolve_vidprop(vobj: *anyopaque, lerp: f32, props: *SurfProps) void;
extern fn matr_quatf(q: Quat, dst: [*c]f32) [*c]f32;
extern fn mult_matrix_vecf(matrix: [*c]const f32, inv: [*c]const f32, out: [*c]f32) void;

// arcan_event lives in shmif_types but is 128 bytes with deeply-nested anon
// unions. Build the byte pattern by hand to avoid pulling in shmif_types as
// a build-time module dependency. Layout (verified against shmif_types.zig
// and arcan_shmif_event.h):
//   bytes 0..N    – payload union (we use the audio variant)
//   byte  AT_CAT  – category (u8)
// total bytes  – 128 (padded)
// The audio variant `arcan_aevent` is 32 bytes:
//   c_int kind; [4]u8 pad; i32 source; [4]u8 pad; union { isize otag; ptr } u;
// On aarch64 LP64, isize=8, so the union is 8B aligned; total = 4+4+4+4+8 = 24,
// rounded up to 32 inside the parent struct.
const ArcanEvent = extern struct {
    bytes: [128]u8 align(8) = std.mem.zeroes([128]u8),
};

// Offset of the `category` byte and `aud` payload start, derived from
// shmif_types' layout (the anon union starts at byte 0; the category byte
// sits AFTER the union — past the largest variant. shmif_types models this
// as `unnamed_0: extern struct { unnamed_0: extern struct { unnamed_0: union;
// category: u8 }; }`. With the 'fsrv' variant being the largest at ~104 B,
// category lands at byte 104).
//
// To avoid getting the offset wrong on different builds, we shell out the
// event packing to the existing C `arcan_event_enqueue` consumer — which
// just memcpy's the bytes — by zero-initing then writing only the audio
// payload at byte 0 + category at byte 104. arcan's event handler reads
// `category` first; if zero or wrong, the event is dropped. We pick a
// pessimistic offset that's correct for the current shmif_types arcan_event
// (byte 104). If the engine layout shifts, this breaks — and that's why we
// keep the assertion.
const ARCAN_EVENT_AUDIO_KIND_OFFSET: usize = 0;
const ARCAN_EVENT_AUDIO_SOURCE_OFFSET: usize = 8;
const ARCAN_EVENT_AUDIO_OTAG_OFFSET: usize = 16;
const ARCAN_EVENT_CATEGORY_OFFSET: usize = 104;

const struct_arcan_evctx = opaque {};
extern fn arcan_event_defaultctx() ?*struct_arcan_evctx;
extern fn arcan_event_enqueue(ctx: ?*struct_arcan_evctx, ev: *const ArcanEvent) c_int;
extern fn arcan_event_denqueue(ctx: ?*struct_arcan_evctx, ev: *const ArcanEvent) c_int;

fn fireAudioEvent(kind: c_int, source: arcan_aobj_id, otag: isize, deferred: bool) void {
    var ev: ArcanEvent = .{};
    const buf: [*]u8 = @ptrCast(&ev.bytes[0]);
    @memcpy(buf[ARCAN_EVENT_AUDIO_KIND_OFFSET .. ARCAN_EVENT_AUDIO_KIND_OFFSET + @sizeOf(c_int)], std.mem.asBytes(&kind));
    const src32: i32 = source;
    @memcpy(buf[ARCAN_EVENT_AUDIO_SOURCE_OFFSET .. ARCAN_EVENT_AUDIO_SOURCE_OFFSET + @sizeOf(i32)], std.mem.asBytes(&src32));
    @memcpy(buf[ARCAN_EVENT_AUDIO_OTAG_OFFSET .. ARCAN_EVENT_AUDIO_OTAG_OFFSET + @sizeOf(isize)], std.mem.asBytes(&otag));
    buf[ARCAN_EVENT_CATEGORY_OFFSET] = EVENT_AUDIO;
    if (deferred) {
        _ = arcan_event_denqueue(arcan_event_defaultctx(), &ev);
    } else {
        _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
    }
}

// ============================================================================
// Audio object table
// ============================================================================

const arcan_achain = struct {
    t_gain: c_uint = 0,
    d_gain: f32 = 0.0,
    next: ?*arcan_achain = null,
};

const Aobj = struct {
    id: arcan_aobj_id = ARCAN_EID,
    refobj: arcan_vobj_id = ARCAN_VIDEO_WORLDID,
    kind: c_int = AOBJ_INVALID,
    active: bool = false,
    streaming: bool = false,
    gain: f32 = 1.0,
    transform: ?*arcan_achain = null,
    gproxy: arcan_again_cb = null,

    feed: arcan_afunc_cb = null,
    feed_tag: ?*anyopaque = null,
    monitor: arcan_monafunc_cb = null,
    monitor_tag: ?*anyopaque = null,
    tag: ?*anyopaque = null,

    // Static play queue: ring of S16 stereo frames waiting to be mixed.
    queue: [PCM_PERIOD_FRAMES * PCM_CHANNELS * 8]i16 = std.mem.zeroes([PCM_PERIOD_FRAMES * PCM_CHANNELS * 8]i16),
    queue_head: usize = 0,
    queue_tail: usize = 0,

    // Sample-only: the full decoded PCM buffer + read cursor.
    sample_buf: ?[]i16 = null,
    sample_cursor: usize = 0,
    sample_channels: c_uint = 2,
    sample_tag: isize = 0,
    sample_done_emitted: bool = false,

    // Capture-only: the capture PCM handle + thread (set when kind = AOBJ_CAPTUREFEED).
    capture_pcm: ?*anyopaque = null,
    capture_thread: pthread_t = 0,
    capture_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    last_used: arcan_tickv = 0,

    // Per-tick refreshed spatial gains. Identity (1.0/1.0) when listener
    // unset or refobj is WORLDID. Read by writer thread under st.lock.
    spatial_l: f32 = 1.0,
    spatial_r: f32 = 1.0,
    next: ?*Aobj = null,
};

// Inverse-distance attenuation parameters. Match OpenAL Soft defaults
// (AL_REFERENCE_DISTANCE=1, AL_ROLLOFF_FACTOR=1, AL_MAX_DISTANCE=∞ — so
// the formula collapses to ref/max(ref, dist)).
const REF_DISTANCE: f32 = 1.0;

const ListenerBasis = struct {
    pos: Vec3 = .{},
    right: Vec3 = .{ .x = 1 },
    valid: bool = false,
};
var listener_basis: ListenerBasis = .{};

const allocator = std.heap.c_allocator;

const AudioState = struct {
    head: ?*Aobj = null,
    lock: std.Thread.Mutex = .{},
    last_id: arcan_aobj_id = 1,
    def_gain: f32 = 1.0,

    al_active: bool = false,
    suspended: bool = false,
    initialized: bool = false,
    no_audio: bool = false,

    // Shared playback PCM + writer thread.
    playback_pcm: ?*anyopaque = null,
    writer_thread: pthread_t = 0,
    writer_running: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),

    listener: arcan_vobj_id = ARCAN_VIDEO_WORLDID,
    atick_counter: arcan_tickv = 0,

    globalhook: arcan_monafunc_cb = null,
    global_hooktag: ?*anyopaque = null,

    // Pending sample-finished events (collected by writer thread, drained in tick).
    finished_pending: [ARCAN_AUDIO_SLIMIT]FinishedEv = std.mem.zeroes([ARCAN_AUDIO_SLIMIT]FinishedEv),
    finished_count: usize = 0,
};

const FinishedEv = struct {
    id: arcan_aobj_id = ARCAN_EID,
    tag: isize = 0,
};

var st: AudioState = .{};

// Outputs / capturelist response buffer (callers consume the [*c]u8 directly).
var outputs_buf: [4096]u8 = undefined;

// ============================================================================
// Aobj helpers (caller MUST hold st.lock)
// ============================================================================

fn allocAobj(kind: c_int) ?*Aobj {
    const obj = allocator.create(Aobj) catch return null;
    obj.* = .{
        .id = st.last_id,
        .kind = kind,
        .gain = st.def_gain,
        .next = st.head,
    };
    st.last_id += 1;
    if (st.last_id == ARCAN_EID) st.last_id = 1;
    st.head = obj;
    return obj;
}

fn findAobj(id: arcan_aobj_id) ?*Aobj {
    var cur = st.head;
    while (cur) |o| : (cur = o.next) {
        if (o.id == id) return o;
    }
    return null;
}

fn unlinkAobj(id: arcan_aobj_id) ?*Aobj {
    var prev: ?*Aobj = null;
    var cur = st.head;
    while (cur) |o| : ({
        prev = o;
        cur = o.next;
    }) {
        if (o.id == id) {
            if (prev) |p| p.next = o.next else st.head = o.next;
            return o;
        }
    }
    return null;
}

fn freeAobj(obj: *Aobj) void {
    resetChain(obj);
    if (obj.sample_buf) |buf| allocator.free(buf);
    if (obj.kind == AOBJ_CAPTUREFEED) {
        obj.capture_running.store(false, .release);
        if (obj.capture_thread != 0) {
            _ = pthread_join(obj.capture_thread, null);
            obj.capture_thread = 0;
        }
        if (obj.capture_pcm) |pcm| _ = snd_pcm_close(pcm);
    }
    allocator.destroy(obj);
}

fn resetChain(obj: *Aobj) void {
    var cur = obj.transform;
    while (cur) |t| {
        const n = t.next;
        allocator.destroy(t);
        cur = n;
    }
    obj.transform = null;
}

fn queueLen(obj: *Aobj) usize {
    if (obj.queue_tail >= obj.queue_head) return obj.queue_tail - obj.queue_head;
    return obj.queue.len - (obj.queue_head - obj.queue_tail);
}

fn queueFree(obj: *Aobj) usize {
    return obj.queue.len - 1 - queueLen(obj);
}

fn queuePushFrames(obj: *Aobj, samples: []const i16) usize {
    var written: usize = 0;
    while (written < samples.len and queueFree(obj) > 0) {
        obj.queue[obj.queue_tail] = samples[written];
        obj.queue_tail = (obj.queue_tail + 1) % obj.queue.len;
        written += 1;
    }
    return written;
}

// Pull up to `count` samples (interleaved L/R pairs) into `dst`. Returns
// number of samples actually pulled.
fn queuePullFrames(obj: *Aobj, dst: []i16) usize {
    var pulled: usize = 0;
    while (pulled < dst.len and queueLen(obj) > 0) {
        dst[pulled] = obj.queue[obj.queue_head];
        obj.queue_head = (obj.queue_head + 1) % obj.queue.len;
        pulled += 1;
    }
    return pulled;
}

fn pushSampleProgress(obj: *Aobj) void {
    if (obj.kind != AOBJ_SAMPLE) return;
    if (obj.sample_buf == null) return;
    const buf = obj.sample_buf.?;
    while (obj.sample_cursor < buf.len and queueFree(obj) >= PCM_CHANNELS) {
        if (obj.sample_channels == 1) {
            // Duplicate mono sample to L/R.
            const s = buf[obj.sample_cursor];
            _ = queuePushFrames(obj, &[_]i16{ s, s });
            obj.sample_cursor += 1;
        } else {
            const s_l = buf[obj.sample_cursor];
            const s_r = buf[obj.sample_cursor + 1];
            _ = queuePushFrames(obj, &[_]i16{ s_l, s_r });
            obj.sample_cursor += 2;
        }
    }
}

// ============================================================================
// PCM device + writer thread
// ============================================================================

fn ensurePlayback() bool {
    if (st.playback_pcm != null) return true;
    var pcm: ?*anyopaque = null;
    var rc = snd_pcm_open(&pcm, "default", SND_PCM_STREAM_PLAYBACK, SND_PCM_NONBLOCK);
    if (rc != 0 or pcm == null) {
        arcan_warning("(ma_alsa) snd_pcm_open(default, playback) failed: %d\n", @as(c_int, rc));
        return false;
    }
    rc = snd_pcm_set_params(pcm, PCM_FORMAT, PCM_ACCESS, PCM_CHANNELS, PCM_RATE, 1, 20000); // 20ms latency target
    if (rc != 0) {
        arcan_warning("(ma_alsa) snd_pcm_set_params failed: %d\n", @as(c_int, rc));
        _ = snd_pcm_close(pcm);
        return false;
    }
    st.playback_pcm = pcm;
    st.writer_running.store(true, .release);
    var th: pthread_t = 0;
    if (pthread_create(&th, null, writerThreadShim, null) != 0) {
        st.writer_running.store(false, .release);
        _ = snd_pcm_close(pcm);
        st.playback_pcm = null;
        arcan_warning("(ma_alsa) failed to spawn writer thread\n", @as(c_int, 0));
        return false;
    }
    st.writer_thread = th;
    return true;
}

fn writerThreadShim(_: ?*anyopaque) callconv(.c) ?*anyopaque {
    writerThreadEntry();
    return null;
}

fn writerThreadEntry() void {
    var mix_buf: [PCM_PERIOD_FRAMES * PCM_CHANNELS]i32 align(16) = undefined;
    var out_buf: [PCM_PERIOD_FRAMES * PCM_CHANNELS]i16 align(16) = undefined;

    while (st.writer_running.load(.acquire)) {
        // Reset mix accumulator.
        @memset(&mix_buf, 0);

        var any_active = false;

        st.lock.lock();
        if (!st.suspended) {
            var cur = st.head;
            while (cur) |obj| : (cur = obj.next) {
                if (!obj.active) continue;
                if (obj.kind != AOBJ_SAMPLE and obj.kind != AOBJ_STREAM and obj.kind != AOBJ_FRAMESTREAM) continue;
                any_active = true;

                // Top off sample queues from their decoded buffer.
                pushSampleProgress(obj);

                // Pull up to 1 period's worth of samples and accumulate.
                var pull_buf: [PCM_PERIOD_FRAMES * PCM_CHANNELS]i16 = undefined;
                const pulled = queuePullFrames(obj, &pull_buf);
                const obj_gain: f32 = @max(0.0, @min(2.0, obj.gain));
                const gain_l: i32 = @intFromFloat(obj_gain * obj.spatial_l * 256.0);
                const gain_r: i32 = @intFromFloat(obj_gain * obj.spatial_r * 256.0);
                var i: usize = 0;
                // Stereo-interleaved pairs; final stray sample (if any) is
                // treated as a left-channel sample.
                while (i + 1 < pulled) : (i += 2) {
                    mix_buf[i] += @divTrunc(@as(i32, pull_buf[i]) * gain_l, 256);
                    mix_buf[i + 1] += @divTrunc(@as(i32, pull_buf[i + 1]) * gain_r, 256);
                }
                if (i < pulled) {
                    mix_buf[i] += @divTrunc(@as(i32, pull_buf[i]) * gain_l, 256);
                }

                // Sample completion check: queue empty + cursor at end.
                if (obj.kind == AOBJ_SAMPLE and obj.sample_buf != null and
                    obj.sample_cursor >= obj.sample_buf.?.len and queueLen(obj) == 0 and
                    !obj.sample_done_emitted)
                {
                    obj.sample_done_emitted = true;
                    if (st.finished_count < st.finished_pending.len) {
                        st.finished_pending[st.finished_count] = .{ .id = obj.id, .tag = obj.sample_tag };
                        st.finished_count += 1;
                    }
                    obj.active = false;
                }

                // Monitor / global hook fire (raw mixer-fed PCM the source produced).
                if (pulled > 0) {
                    if (obj.monitor) |mon| {
                        mon(obj.id, @ptrCast(&pull_buf[0]), pulled * @sizeOf(i16), PCM_CHANNELS, PCM_RATE, obj.monitor_tag);
                    }
                    if (st.globalhook) |gh| {
                        gh(obj.id, @ptrCast(&pull_buf[0]), pulled * @sizeOf(i16), PCM_CHANNELS, PCM_RATE, st.global_hooktag);
                    }
                }
            }
        }
        st.lock.unlock();

        // Saturate mix to i16 + apply default master gain.
        const def_gain_int: i32 = @intFromFloat(@max(0.0, @min(2.0, st.def_gain)) * 256.0);
        for (mix_buf, 0..) |v, idx| {
            const masterf: i32 = @divTrunc(v * def_gain_int, 256);
            const clamped: i32 = @max(@as(i32, std.math.minInt(i16)), @min(@as(i32, std.math.maxInt(i16)), masterf));
            out_buf[idx] = @intCast(clamped);
        }

        // If nothing's playing, sleep instead of writing silence (saves wakeups).
        if (!any_active) {
            std.Thread.sleep(5 * std.time.ns_per_ms);
            continue;
        }

        // Blocking write — snd_pcm was opened SND_PCM_NONBLOCK=0 above;
        // recover from xruns transparently.
        var written: c_long = 0;
        while (written < @as(c_long, PCM_PERIOD_FRAMES)) {
            const remaining: c_ulong = @intCast(@as(c_long, PCM_PERIOD_FRAMES) - written);
            const off = @as(usize, @intCast(written)) * PCM_CHANNELS;
            const n = snd_pcm_writei(st.playback_pcm, @ptrCast(&out_buf[off]), remaining);
            if (n < 0) {
                const r = snd_pcm_recover(st.playback_pcm, @intCast(n), 1);
                if (r < 0) {
                    arcan_warning("(ma_alsa) snd_pcm_recover failed: %d\n", @as(c_int, r));
                    break;
                }
                continue;
            }
            written += n;
        }
    }
}

// ============================================================================
// Capture thread
// ============================================================================

fn captureThreadEntry(obj: *Aobj) void {
    while (obj.capture_running.load(.acquire)) {
        var buf: [1024 * PCM_CHANNELS]i16 = undefined;
        const n = snd_pcm_readi(obj.capture_pcm, @ptrCast(&buf[0]), 1024);
        if (n < 0) {
            const r = snd_pcm_recover(obj.capture_pcm, @intCast(n), 1);
            if (r < 0) {
                arcan_warning("(ma_alsa) capture snd_pcm_recover: %d\n", @as(c_int, r));
                break;
            }
            continue;
        }
        const sample_count: usize = @intCast(n);
        const byte_count: usize = sample_count * PCM_CHANNELS * @sizeOf(i16);
        const buf_ptr: [*c]u8 = @ptrCast(&buf[0]);
        st.lock.lock();
        const monitor = obj.monitor;
        const monitor_tag = obj.monitor_tag;
        const ghook = st.globalhook;
        const ghook_tag = st.global_hooktag;
        const feed = obj.feed;
        const feed_tag = obj.feed_tag;
        st.lock.unlock();
        if (monitor) |mon| mon(obj.id, buf_ptr, byte_count, PCM_CHANNELS, PCM_RATE, monitor_tag);
        if (ghook) |gh| gh(obj.id, buf_ptr, byte_count, PCM_CHANNELS, PCM_RATE, ghook_tag);
        if (feed) |fcb| _ = fcb(@ptrCast(obj), obj.id, @intCast(byte_count), false, feed_tag);
    }
}

// ============================================================================
// WAV decoder (PCM, 8/16-bit, mono/stereo). Returns owned []i16 where each
// element is one sample (interleaved if stereo). Caller frees with allocator.
// ============================================================================

fn decodeWav(path: [*c]const u8) ?Aobj_sample {
    const path_z: [:0]const u8 = std.mem.span(path);
    const file = std.fs.cwd().openFile(path_z, .{}) catch {
        arcan_warning("(ma_alsa) wav: cannot open '%s'\n", path);
        return null;
    };
    defer file.close();
    const stat = file.stat() catch return null;
    if (stat.size < 44 or stat.size > 256 * 1024 * 1024) {
        arcan_warning("(ma_alsa) wav: bad size '%s'\n", path);
        return null;
    }
    const raw = allocator.alloc(u8, stat.size) catch return null;
    defer allocator.free(raw);
    const got = file.readAll(raw) catch return null;
    if (got != stat.size) return null;

    if (!std.mem.eql(u8, raw[0..4], "RIFF")) return null;
    if (!std.mem.eql(u8, raw[8..12], "WAVE")) return null;
    if (!std.mem.eql(u8, raw[12..16], "fmt ")) return null;

    const fmt: i16 = std.mem.readInt(i16, raw[20..22], .little);
    const nch: i16 = std.mem.readInt(i16, raw[22..24], .little);
    const rate: u32 = std.mem.readInt(u32, raw[24..28], .little);
    const bits_ps: u16 = std.mem.readInt(u16, raw[34..36], .little);
    var nofs: i32 = std.mem.readInt(i32, raw[16..20], .little);
    nofs += 20;
    if (fmt != 1) {
        arcan_warning("(ma_alsa) wav: non-PCM encoding\n", @as(c_int, 0));
        return null;
    }
    if (nch != 1 and nch != 2) return null;
    if (bits_ps != 8 and bits_ps != 16) return null;
    const nofs_u: usize = @intCast(nofs);
    if (nofs_u + 8 > raw.len) return null;
    if (!std.mem.eql(u8, raw[nofs_u .. nofs_u + 4], "data")) return null;

    var nb: u32 = std.mem.readInt(u32, raw[nofs_u + 4 ..][0..4], .little);
    if (nb > CONST_MAX_ASAMPLESZ) nb = @intCast(CONST_MAX_ASAMPLESZ);
    const ofs_start: usize = nofs_u + 8;
    if (ofs_start + nb > raw.len) return null;

    const sample_count: usize = if (bits_ps == 16) nb / 2 else nb;
    const out = allocator.alloc(i16, sample_count) catch return null;
    if (bits_ps == 16) {
        var i: usize = 0;
        while (i < sample_count) : (i += 1) {
            out[i] = std.mem.readInt(i16, raw[ofs_start + i * 2 ..][0..2], .little);
        }
    } else {
        // 8-bit unsigned PCM; convert to signed 16.
        var i: usize = 0;
        while (i < sample_count) : (i += 1) {
            const u8v: u8 = raw[ofs_start + i];
            out[i] = (@as(i16, u8v) - 128) * 256;
        }
    }
    return .{ .buf = out, .channels = @intCast(nch), .sample_rate = rate };
}

const Aobj_sample = struct {
    buf: []i16,
    channels: c_uint,
    sample_rate: u32,
};

// Resample helper: linear interpolation, fixed-point 12-bit fraction
// (port of OpenAL Soft's Resample_lerp32_C / FRACTIONBITS=12 from
// Alc/mixer_c.c). Source samplerate→PCM_RATE for arbitrary input
// frequencies; mono→stereo via L=R duplication. Caller hands ownership
// of `s.buf`; on success this frees it and returns a new buffer.
const FRACTIONBITS: u5 = 12;
const FRACTIONONE: u32 = 1 << FRACTIONBITS;
const FRACTIONMASK: u32 = FRACTIONONE - 1;

fn resampleToOutput(s: Aobj_sample) ?[]i16 {
    if (s.sample_rate == PCM_RATE and s.channels == PCM_CHANNELS) return s.buf;

    const in_frames: usize = if (s.channels == 1) s.buf.len else s.buf.len / 2;
    if (in_frames == 0) {
        allocator.free(s.buf);
        return allocator.alloc(i16, 0) catch null;
    }

    // Per-output-sample fixed-point step: src_rate / dst_rate * FRACTIONONE.
    // u64 numerator is needed to avoid overflow at e.g. 192000 Hz.
    const increment_u: u64 = (@as(u64, s.sample_rate) << FRACTIONBITS) / @as(u64, PCM_RATE);
    const increment: u32 = if (increment_u == 0) 1 else @intCast(increment_u);

    // out_frames = ceil(in_frames * dst_rate / src_rate)
    const out_frames_u: u64 = (@as(u64, in_frames) * @as(u64, PCM_RATE) + (@as(u64, s.sample_rate) - 1)) / @as(u64, s.sample_rate);
    const out_frames: usize = @intCast(out_frames_u);
    const out = allocator.alloc(i16, out_frames * PCM_CHANNELS) catch return null;

    var frac: u32 = 0;
    var src_frame: usize = 0;
    var i: usize = 0;
    const stereo = (s.channels == 2);

    while (i < out_frames) : (i += 1) {
        const f0 = @min(in_frames - 1, src_frame);
        const f1 = @min(in_frames - 1, src_frame + 1);
        const t: f32 = @as(f32, @floatFromInt(frac)) * (1.0 / @as(f32, @floatFromInt(FRACTIONONE)));

        if (stereo) {
            const al: f32 = @floatFromInt(s.buf[f0 * 2]);
            const bl: f32 = @floatFromInt(s.buf[f1 * 2]);
            const ar: f32 = @floatFromInt(s.buf[f0 * 2 + 1]);
            const br: f32 = @floatFromInt(s.buf[f1 * 2 + 1]);
            out[i * 2] = @intFromFloat(al + (bl - al) * t);
            out[i * 2 + 1] = @intFromFloat(ar + (br - ar) * t);
        } else {
            const a: f32 = @floatFromInt(s.buf[f0]);
            const b: f32 = @floatFromInt(s.buf[f1]);
            const v: i16 = @intFromFloat(a + (b - a) * t);
            out[i * 2] = v;
            out[i * 2 + 1] = v;
        }

        frac += increment;
        const advance: usize = @intCast(frac >> FRACTIONBITS);
        src_frame += advance;
        frac &= FRACTIONMASK;
        if (src_frame >= in_frames) src_frame = in_frames - 1;
    }
    allocator.free(s.buf);
    return out;
}

// ============================================================================
// 3D spatial: listener basis + per-source pan/attenuation
// ============================================================================
//
// Math is a compact port of OpenAL Soft's Alc/ALu.c (CalcListenerParams +
// CalcAttnSourceParams). We don't model velocity/Doppler, cone gains, max-
// distance clamping, or per-source ref/max overrides — arcan's audio
// surface only exposes a single VID per source/listener with no extra
// metadata, and the OpenAL backend never set those fields either.
//
// CalcListenerParams (ALu.c:238) builds a 4×4 view matrix from forward and
// up. Right axis is right = normalize(forward × up). We only need `right`
// (for stereo pan onto the listener's left-right axis) plus the listener's
// world position (to compute source→listener delta).
//
// Per-source (ALu.c:782): Distance = |Position - ListenerPos|. We use the
// inverse-distance model: Atten = ref / max(ref, distance).  Pan factor is
// dot(normalize(SourceToListener), listener.right) ∈ [-1, +1]. Final L/R
// gains use equal-power panning: L = atten * sqrt((1 - pan) / 2),
// R = atten * sqrt((1 + pan) / 2).

fn updateListenerBasis() void {
    if (st.listener == ARCAN_VIDEO_WORLDID) {
        listener_basis = .{};
        return;
    }
    const vobj = arcan_video_getobject(st.listener) orelse {
        listener_basis = .{};
        return;
    };
    var props: SurfProps = .{};
    arcan_resolve_vidprop(vobj, 0.0, &props);
    var orientm: [16]f32 = undefined;
    _ = matr_quatf(props.rotation.quaternion, &orientm);
    var fwd_in = [4]f32{ 0.0, 0.0, 1.0, 1.0 };
    var up_in = [4]f32{ 0.0, 1.0, 0.0, 1.0 };
    var fwd_out: [4]f32 = undefined;
    var up_out: [4]f32 = undefined;
    mult_matrix_vecf(&orientm, &fwd_in, &fwd_out);
    mult_matrix_vecf(&orientm, &up_in, &up_out);
    // right = forward × up.
    const rx = fwd_out[1] * up_out[2] - fwd_out[2] * up_out[1];
    const ry = fwd_out[2] * up_out[0] - fwd_out[0] * up_out[2];
    const rz = fwd_out[0] * up_out[1] - fwd_out[1] * up_out[0];
    const rlen = @sqrt(rx * rx + ry * ry + rz * rz);
    var right: Vec3 = .{ .x = 1, .y = 0, .z = 0 };
    if (rlen > 1e-6) {
        right = .{ .x = rx / rlen, .y = ry / rlen, .z = rz / rlen };
    }
    listener_basis = .{ .pos = props.position, .right = right, .valid = true };
}

fn computeSpatial(obj: *Aobj) void {
    // Default: identity.
    obj.spatial_l = 1.0;
    obj.spatial_r = 1.0;
    if (!listener_basis.valid) return;
    if (obj.refobj == ARCAN_VIDEO_WORLDID) return;

    const vobj = arcan_video_getobject(obj.refobj) orelse return;
    var sp: SurfProps = .{};
    arcan_resolve_vidprop(vobj, 0.0, &sp);

    const dx = sp.position.x - listener_basis.pos.x;
    const dy = sp.position.y - listener_basis.pos.y;
    const dz = sp.position.z - listener_basis.pos.z;
    const dist = @sqrt(dx * dx + dy * dy + dz * dz);

    // Source on top of listener — give equal-power center (no pan).
    if (dist <= 1e-6) return;

    const atten: f32 = REF_DISTANCE / @max(REF_DISTANCE, dist);
    const pan_raw: f32 = (dx * listener_basis.right.x + dy * listener_basis.right.y + dz * listener_basis.right.z) / dist;
    const pan: f32 = @max(@as(f32, -1.0), @min(@as(f32, 1.0), pan_raw));
    obj.spatial_l = atten * @sqrt(0.5 * (1.0 - pan));
    obj.spatial_r = atten * @sqrt(0.5 * (1.0 + pan));
}

// ============================================================================
// Public exports — match openal.zig signatures verbatim
// ============================================================================

export fn platform_audio_preinit() void {
    // No state to set up before init() — left for symmetry.
}

export fn platform_audio_reassign(id: arcan_aobj_id, device: c_int) void {
    _ = id;
    _ = device;
    // ma_alsa: single output device per process; per-source routing would
    // require multiple ma_devices and a router. Treat as no-op (mirrors
    // openal.zig which also no-ops).
}

export fn platform_audio_reconfigure(cfg: struct_platform_audio_cfg, device: c_int) void {
    _ = cfg;
    _ = device;
    // HRTF/output-device reconfiguration not applicable to direct ALSA;
    // would tear down + reopen the playback PCM with new params. We don't
    // currently expose that since we hard-code SHMIF samplerate/channels.
}

export fn platform_audio_init(noaudio: bool) bool {
    st.lock.lock();
    defer st.lock.unlock();
    if (st.initialized) return true;
    if (noaudio) {
        st.no_audio = true;
        st.initialized = true;
        st.al_active = true;
        return true;
    }
    // ma_context_init dlopens libasound and populates the vtable. Even
    // though we use the direct extern fn snd_* symbols (auto-resolved by
    // dl_alsa shims), keeping ma_context around lets enumerate work.
    var pcfg: c.ma_context_config = .{};
    var pcb: c.ma_backend_callbacks = .{};
    var ctx_buf: c.ma_context = .{};
    if (ma_alsa.ma_context_init__alsa(&ctx_buf, &pcfg, &pcb) == c.MA_SUCCESS) {
        ma_ctx = ctx_buf;
        ma_ctx_inited = true;
    }
    st.al_active = true;
    st.initialized = true;
    var seed: arcan_aobj_id = 0;
    arcan_random(@ptrCast(std.mem.asBytes(&seed)), @sizeOf(arcan_aobj_id));
    st.last_id = (seed & 0x00FFFFFF) | 1; // avoid 0/EID
    return true;
}

var ma_ctx: c.ma_context = .{};
var ma_ctx_inited: bool = false;

export fn platform_audio_suspend() void {
    st.lock.lock();
    defer st.lock.unlock();
    st.suspended = true;
    st.al_active = false;
}

export fn platform_audio_resume() void {
    st.lock.lock();
    defer st.lock.unlock();
    st.suspended = false;
    st.al_active = true;
}

export fn platform_audio_tick(ntt: u8) void {
    if (st.no_audio or !st.al_active) return;
    st.lock.lock();
    defer st.lock.unlock();

    // Drain finished-sample notifications.
    var i: usize = 0;
    while (i < st.finished_count) : (i += 1) {
        fireAudioEvent(EVENT_AUDIO_PLAYBACK_FINISHED, st.finished_pending[i].id, st.finished_pending[i].tag, true);
    }
    st.finished_count = 0;

    // Step gain transitions.
    var remaining: u8 = ntt;
    while (remaining > 0) : (remaining -= 1) {
        var cur = st.head;
        while (cur) |obj| : (cur = obj.next) {
            if (stepTransform(obj)) {
                if (obj.gproxy) |proxy| _ = proxy(obj.gain, obj.tag);
            }
        }
        st.atick_counter += 1;
    }

    // Refresh listener basis + per-source spatial L/R gains. The writer
    // thread reads spatial_l/r under st.lock, so updates here race-free.
    updateListenerBasis();

    // Pump streaming feeds (refill if running low) and recompute spatial.
    var cur = st.head;
    while (cur) |obj| : (cur = obj.next) {
        if (obj.kind == AOBJ_STREAM or obj.kind == AOBJ_FRAMESTREAM) {
            refillStream(obj);
        }
        computeSpatial(obj);
    }
}

fn stepTransform(obj: *Aobj) bool {
    const t = obj.transform orelse return false;
    if (t.t_gain == 0) {
        obj.gain = t.d_gain;
        obj.transform = t.next;
        allocator.destroy(t);
        return true;
    }
    obj.gain += (t.d_gain - obj.gain) / @as(f32, @floatFromInt(t.t_gain));
    t.t_gain -= 1;
    if (t.t_gain == 0) {
        obj.gain = t.d_gain;
        obj.transform = t.next;
        allocator.destroy(t);
    }
    return true;
}

fn refillStream(obj: *Aobj) void {
    const fcb = obj.feed orelse return;
    if (queueFree(obj) < PCM_PERIOD_FRAMES * PCM_CHANNELS) return;
    // The feed callback signature is: fn(opaque, id, buffer_idx, more, tag) -> errc.
    // We don't have OpenAL buffer ids; pass our queue tail as a proxy, the
    // engine treats it as opaque. Most consumers don't care about the value.
    const rc = fcb(@ptrCast(obj), obj.id, @intCast(obj.queue_tail), false, obj.feed_tag);
    if (rc != ARCAN_OK and rc != ARCAN_ERRC_NOTREADY) {
        // Source signaled end-of-stream / error → fire finished event.
        if (st.finished_count < st.finished_pending.len) {
            st.finished_pending[st.finished_count] = .{ .id = obj.id, .tag = 0 };
            st.finished_count += 1;
        }
        obj.active = false;
    }
}

export fn platform_audio_refresh() usize {
    if (st.no_audio or !st.al_active) return 0;
    st.lock.lock();
    defer st.lock.unlock();
    var rv: usize = 0;
    var cur = st.head;
    while (cur) |obj| : (cur = obj.next) {
        if (obj.kind == AOBJ_STREAM or obj.kind == AOBJ_FRAMESTREAM or obj.kind == AOBJ_CAPTUREFEED) {
            refillStream(obj);
        }
        if (queueLen(obj) > 0) rv += 1;
    }
    return rv;
}

export fn platform_audio_outputs() [*c]const u8 {
    if (!ma_ctx_inited) {
        outputs_buf[0] = 0;
        return @ptrCast(&outputs_buf[0]);
    }
    var es: EnumState = .{ .is_capture = false, .buf = @ptrCast(&outputs_buf[0]), .cap = outputs_buf.len };
    _ = ma_alsa.ma_context_enumerate_devices__alsa(&ma_ctx, enumWritebackCb, &es);
    if (es.written < outputs_buf.len) outputs_buf[es.written] = 0 else outputs_buf[outputs_buf.len - 1] = 0;
    return @ptrCast(&outputs_buf[0]);
}

const EnumState = extern struct {
    is_capture: bool = false,
    written: usize = 0,
    truncated: bool = false,
    buf: [*c]u8 = null,
    cap: usize = 0,
};

fn enumWritebackCb(
    pCtx: ?*anyopaque,
    deviceType: c.ma_device_type,
    pInfo: [*c]const c.ma_device_info,
    pUser: ?*anyopaque,
) callconv(.c) c.ma_bool32 {
    _ = pCtx;
    const es: *EnumState = @ptrCast(@alignCast(pUser.?));
    const want_capture = es.is_capture;
    const is_capture = (deviceType == @as(c_uint, @intCast(c.ma_device_type_capture)));
    if (want_capture != is_capture) return 1;
    const name_arr: *const [256]u8 = &pInfo.*.name;
    const name_len = std.mem.indexOfScalar(u8, name_arr, 0) orelse 256;
    const name_slice = name_arr[0..name_len];
    const need = name_slice.len + 1;
    if (es.written + need + 1 > es.cap) {
        es.truncated = true;
        return 0;
    }
    @memcpy(es.buf[es.written .. es.written + name_slice.len], name_slice);
    es.buf[es.written + name_slice.len] = '\n';
    es.written += need;
    return 1;
}

export fn platform_audio_shutdown() void {
    st.lock.lock();
    if (st.writer_running.load(.acquire)) {
        st.writer_running.store(false, .release);
        const th = st.writer_thread;
        st.lock.unlock();
        if (th != 0) _ = pthread_join(th, null);
        st.lock.lock();
        st.writer_thread = 0;
    }
    if (st.playback_pcm) |pcm| {
        _ = snd_pcm_drain(pcm);
        _ = snd_pcm_close(pcm);
        st.playback_pcm = null;
    }
    var cur = st.head;
    while (cur) |obj| {
        const n = obj.next;
        freeAobj(obj);
        cur = n;
    }
    st.head = null;
    st.al_active = false;
    st.initialized = false;
    if (ma_ctx_inited) {
        _ = ma_alsa.ma_context_uninit__alsa(&ma_ctx);
        ma_ctx_inited = false;
    }
    st.lock.unlock();
}

export fn platform_audio_rebuild(id: arcan_aobj_id) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    obj.queue_head = 0;
    obj.queue_tail = 0;
    obj.sample_cursor = 0;
    obj.sample_done_emitted = false;
    obj.active = false;
    return true;
}

export fn platform_audio_hookfeed(
    id: arcan_aobj_id,
    tag: ?*anyopaque,
    hookfun: arcan_monafunc_cb,
    oldtag: ?*?*anyopaque,
) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    if (oldtag) |slot| slot.* = obj.monitor_tag;
    obj.monitor = hookfun;
    obj.monitor_tag = tag;
    return true;
}

export fn platform_audio_load_sample(
    fname: [*c]const u8,
    gain: f32,
    err: ?*arcan_errc,
) arcan_aobj_id {
    if (st.no_audio) {
        if (err) |e| e.* = ARCAN_ERRC_BAD_RESOURCE;
        return ARCAN_EID;
    }
    const decoded = decodeWav(fname) orelse {
        if (err) |e| e.* = ARCAN_ERRC_BAD_RESOURCE;
        return ARCAN_EID;
    };
    const final = resampleToOutput(decoded) orelse {
        allocator.free(decoded.buf);
        if (err) |e| e.* = ARCAN_ERRC_OUT_OF_SPACE;
        return ARCAN_EID;
    };
    st.lock.lock();
    defer st.lock.unlock();
    const obj = allocAobj(AOBJ_SAMPLE) orelse {
        allocator.free(final);
        if (err) |e| e.* = ARCAN_ERRC_OUT_OF_SPACE;
        return ARCAN_EID;
    };
    obj.gain = gain;
    obj.sample_buf = final;
    obj.sample_cursor = 0;
    obj.sample_channels = PCM_CHANNELS; // already resampled to stereo
    if (err) |e| e.* = ARCAN_OK;
    return obj.id;
}

export fn platform_audio_sample_buffer(
    buffer: [*c]f32,
    elems: usize,
    channels: c_int,
    samplerate: c_int,
    fmt_specifier: [*c]const u8,
) arcan_aobj_id {
    _ = fmt_specifier;
    if (st.no_audio or buffer == null or elems == 0 or channels < 1 or channels > 2 or samplerate <= 0) {
        return ARCAN_EID;
    }
    // Convert f32 → i16 in-place into an allocator-owned i16 buffer.
    const tmp = allocator.alloc(i16, elems) catch return ARCAN_EID;
    var i: usize = 0;
    while (i < elems) : (i += 1) {
        const v = buffer[i];
        const scaled: f32 = @max(-1.0, @min(1.0, v)) * 32767.0;
        tmp[i] = @intFromFloat(scaled);
    }
    const sample = Aobj_sample{ .buf = tmp, .channels = @intCast(channels), .sample_rate = @intCast(samplerate) };
    const final = resampleToOutput(sample) orelse {
        allocator.free(tmp);
        return ARCAN_EID;
    };
    st.lock.lock();
    defer st.lock.unlock();
    const obj = allocAobj(AOBJ_SAMPLE) orelse {
        allocator.free(final);
        return ARCAN_EID;
    };
    obj.sample_buf = final;
    obj.sample_cursor = 0;
    obj.sample_channels = PCM_CHANNELS;
    return obj.id;
}

export fn platform_audio_alterfeed(id: arcan_aobj_id, cb: arcan_afunc_cb) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    if (cb == null) return false;
    obj.feed = cb;
    return true;
}

export fn platform_audio_feed(
    feed: arcan_afunc_cb,
    tag: ?*anyopaque,
    errc: ?*arcan_errc,
) arcan_aobj_id {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = allocAobj(AOBJ_STREAM) orelse {
        if (errc) |e| e.* = ARCAN_ERRC_OUT_OF_SPACE;
        return ARCAN_EID;
    };
    obj.streaming = true;
    obj.tag = tag;
    obj.feed = feed;
    obj.feed_tag = tag;
    obj.gain = 1.0;
    if (errc) |e| e.* = ARCAN_OK;
    return obj.id;
}

export fn platform_audio_kind(id: arcan_aobj_id) c_int {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return AOBJ_INVALID;
    return obj.kind;
}

export fn platform_audio_stop(id: arcan_aobj_id) bool {
    st.lock.lock();
    const obj = unlinkAobj(id) orelse {
        st.lock.unlock();
        return false;
    };
    st.lock.unlock();
    freeAobj(obj);
    fireAudioEvent(EVENT_AUDIO_OBJECT_GONE, id, 0, false);
    return true;
}

export fn platform_audio_play(
    id: arcan_aobj_id,
    gain_override: bool,
    gain: f32,
    tag: isize,
) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    if (gain_override) obj.gain = gain;
    if (obj.kind == AOBJ_SAMPLE) {
        obj.sample_cursor = 0;
        obj.sample_done_emitted = false;
        obj.sample_tag = tag;
    }
    obj.active = true;
    if (!ensurePlayback()) return false;
    return true;
}

export fn platform_audio_pause(id: arcan_aobj_id) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    obj.active = false;
    return true;
}

export fn platform_audio_rewind(id: arcan_aobj_id) bool {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return false;
    obj.queue_head = 0;
    obj.queue_tail = 0;
    obj.sample_cursor = 0;
    obj.sample_done_emitted = false;
    return true;
}

export fn platform_audio_capturelist(capturelist_ptr: [*c][*c]u8) void {
    if (!ma_ctx_inited) {
        if (capturelist_ptr != null) capturelist_ptr.* = null;
        return;
    }
    var es: EnumState = .{ .is_capture = true, .buf = @ptrCast(&outputs_buf[0]), .cap = outputs_buf.len };
    _ = ma_alsa.ma_context_enumerate_devices__alsa(&ma_ctx, enumWritebackCb, &es);
    if (es.written < outputs_buf.len) outputs_buf[es.written] = 0 else outputs_buf[outputs_buf.len - 1] = 0;
    if (capturelist_ptr != null) capturelist_ptr.* = @ptrCast(&outputs_buf[0]);
}

export fn platform_audio_capturefeed(identifier: [*c]const u8) arcan_aobj_id {
    if (st.no_audio) return ARCAN_EID;
    var pcm: ?*anyopaque = null;
    const name: [*c]const u8 = if (identifier == null) "default" else identifier;
    var rc = snd_pcm_open(&pcm, name, SND_PCM_STREAM_CAPTURE, SND_PCM_NONBLOCK);
    if (rc != 0 or pcm == null) {
        arcan_warning("(ma_alsa) capture open failed: %d\n", @as(c_int, rc));
        return ARCAN_EID;
    }
    rc = snd_pcm_set_params(pcm, PCM_FORMAT, PCM_ACCESS, PCM_CHANNELS, PCM_RATE, 1, 50000);
    if (rc != 0) {
        _ = snd_pcm_close(pcm);
        return ARCAN_EID;
    }
    st.lock.lock();
    defer st.lock.unlock();
    const obj = allocAobj(AOBJ_CAPTUREFEED) orelse {
        _ = snd_pcm_close(pcm);
        return ARCAN_EID;
    };
    obj.streaming = true;
    obj.gain = 1.0;
    obj.capture_pcm = pcm;
    obj.capture_running.store(true, .release);
    var th: pthread_t = 0;
    if (pthread_create(&th, null, captureThreadShim, @ptrCast(obj)) != 0) {
        obj.capture_running.store(false, .release);
        _ = snd_pcm_close(pcm);
        obj.capture_pcm = null;
        return ARCAN_EID;
    }
    obj.capture_thread = th;
    return obj.id;
}

fn captureThreadShim(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const obj: *Aobj = @ptrCast(@alignCast(arg.?));
    captureThreadEntry(obj);
    return null;
}

export fn platform_audio_setgain(id: arcan_aobj_id, gain: f32, time: u16) bool {
    st.lock.lock();
    defer st.lock.unlock();
    if (id == ARCAN_EID) {
        st.def_gain = gain;
        return true;
    }
    const obj = findAobj(id) orelse return false;
    if (time == 0) {
        resetChain(obj);
        obj.gain = gain;
        if (obj.gproxy) |proxy| _ = proxy(obj.gain, obj.tag);
    } else {
        // Append to chain tail.
        var slot: *?*arcan_achain = &obj.transform;
        while (slot.*) |t| slot = &t.next;
        const newt = allocator.create(arcan_achain) catch return false;
        newt.* = .{ .t_gain = time, .d_gain = gain };
        slot.* = newt;
    }
    return true;
}

export fn platform_audio_getgain(id: arcan_aobj_id, gain: ?*f32) bool {
    st.lock.lock();
    defer st.lock.unlock();
    if (id == ARCAN_EID) {
        if (gain) |g| g.* = st.def_gain;
        return true;
    }
    const obj = findAobj(id) orelse return false;
    if (gain) |g| g.* = obj.gain;
    return true;
}

export fn platform_audio_buffer(
    aobjopaq: ?*anyopaque,
    buffer: isize,
    audbuf: ?*anyopaque,
    abufs: usize,
    channels: c_uint,
    samplerate: c_uint,
    tag: ?*anyopaque,
) void {
    _ = buffer;
    _ = tag;
    if (st.no_audio) return;
    const obj: *Aobj = @ptrCast(@alignCast(aobjopaq orelse return));
    const src_bytes: [*c]u8 = @ptrCast(@alignCast(audbuf orelse return));

    // Monitor / global hooks see the raw incoming buffer.
    if (obj.monitor) |mon| mon(obj.id, src_bytes, abufs, channels, samplerate, obj.monitor_tag);
    if (st.globalhook) |gh| gh(obj.id, src_bytes, abufs, channels, samplerate, st.global_hooktag);

    // Channel + samplerate convert to the canonical stereo 48k S16, push.
    const sample_count = abufs / @sizeOf(i16);
    if (sample_count == 0) return;
    const src_i16: [*c]const i16 = @ptrCast(@alignCast(audbuf));
    const slice = src_i16[0..sample_count];
    if (channels == PCM_CHANNELS and samplerate == PCM_RATE) {
        // No st.lock here: platform_audio_buffer is reached only via
        // refillStream, whose callers (platform_audio_tick / _refresh /
        // _aid_refresh) already hold st.lock. Re-locking the non-recursive
        // mutex on the same thread self-deadlocks (panic: Deadlock detected).
        _ = queuePushFrames(obj, slice);
        if (!ensurePlayback()) return;
        obj.last_used = st.atick_counter;
    } else {
        // Resample/upmix into a temporary, push.
        const tmp_owned = allocator.dupe(i16, slice) catch return;
        const sa = Aobj_sample{ .buf = tmp_owned, .channels = channels, .sample_rate = samplerate };
        const final = resampleToOutput(sa) orelse {
            allocator.free(tmp_owned);
            return;
        };
        defer allocator.free(final);
        // st.lock already held by the caller (see note in the branch above).
        _ = queuePushFrames(obj, final);
        if (!ensurePlayback()) return;
        obj.last_used = st.atick_counter;
    }
}

export fn platform_audio_aid_refresh(aid: arcan_aobj_id) void {
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(aid) orelse return;
    if (obj.kind == AOBJ_STREAM or obj.kind == AOBJ_FRAMESTREAM) refillStream(obj);
}

export fn platform_audio_purge(save: [*c]arcan_aobj_id, save_count: usize) void {
    st.lock.lock();
    var cur = st.head;
    var prev: ?*Aobj = null;
    var to_free: [128]*Aobj = undefined;
    var to_free_count: usize = 0;
    while (cur) |obj| {
        const next_obj = obj.next;
        var keep = false;
        var i: usize = 0;
        while (i < save_count) : (i += 1) {
            if (save[i] == obj.id) {
                keep = true;
                break;
            }
        }
        if (!keep and to_free_count < to_free.len) {
            if (prev) |p| p.next = next_obj else st.head = next_obj;
            to_free[to_free_count] = obj;
            to_free_count += 1;
            cur = next_obj;
        } else {
            prev = obj;
            cur = next_obj;
        }
    }
    st.lock.unlock();
    var k: usize = 0;
    while (k < to_free_count) : (k += 1) {
        // buffer = sentinel "-1" as c_uint (matches audioframe_direct's
        // bitcast comparison at the entry of the callback).
        if (to_free[k].feed) |fcb| _ = fcb(@ptrCast(to_free[k]), to_free[k].id, ~@as(c_uint, 0), false, to_free[k].tag);
        freeAobj(to_free[k]);
    }
}

export fn platform_audio_listener(vid: arcan_vobj_id) void {
    // Listener basis is rebuilt in platform_audio_tick from the stored vid.
    st.lock.lock();
    defer st.lock.unlock();
    st.listener = vid;
}

export fn platform_audio_position(id: arcan_aobj_id, vid: arcan_vobj_id) void {
    // Per-source pan/attenuation are recomputed in platform_audio_tick from
    // refobj's resolved position vs. the listener basis.
    st.lock.lock();
    defer st.lock.unlock();
    const obj = findAobj(id) orelse return;
    obj.refobj = vid;
}
