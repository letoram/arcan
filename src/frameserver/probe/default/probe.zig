// afsrv_probe — minimal shmif app that drives a12 coverage probes
//
// Modes (pick via ARCAN_ARG=mode=…; default = all):
//   audio        emit an audio chunk + SIGAUD                (→ aframe_encode)
//   subseg       request a subsegment via EXTERNAL_SEGREQ    (→ newchannel)
//   state        advertise STATESIZE so durian sends         (→ bstream + blob_recv)
//                 a STORE BCHUNK_OUT with an fd we handle
//   all          run audio → state → subseg, then idle so the
//                durian side has time to respond
//
// The app resizes to 320x200, pushes one solid-colour video frame so the
// parent grants a window slot, then drives the selected mode(s). It does
// not exit on its own — the matrix harness kills it after its measurement
// window.

const std = @import("std");
const c = @import("shmif_types");

extern "c" var stdout: *anyopaque;
extern "c" var stderr: *anyopaque;

extern "c" fn arcan_shmif_signal(ctx: *c.arcan_shmif_cont, mask: c_int) c_uint;
extern "c" fn arcan_shmif_resize(ctx: *c.arcan_shmif_cont, w: usize, h: usize) bool;
extern "c" fn arcan_shmif_resize_ext(ctx: *c.arcan_shmif_cont, w: c_uint, h: c_uint, ext: c.struct_shmif_resize_ext) bool;
extern "c" fn arcan_shmif_wait(ctx: *c.arcan_shmif_cont, ev: *c.arcan_event) c_int;

fn push_vframe(shms: *c.arcan_shmif_cont, rgba: u32) void {
    var p: [*c]u32 = shms.unnamed_0.vidp;
    const n: usize = shms.w * shms.h;
    for (0..n) |_| {
        p.* = rgba;
        p += 1;
    }
    _ = arcan_shmif_signal(shms, c.SHMIF_SIGVID);
}

// Fill a short square wave (up to 1024 stereo s16 samples ≈ 21ms at
// 48kHz) and signal SIGAUD.
fn push_audio(shms: *c.arcan_shmif_cont) void {
    if (shms.unnamed_1.audp == null) return;
    const audp: [*c]i16 = @ptrCast(@alignCast(shms.unnamed_1.audp));
    const byte_cap: usize = @intCast(shms.abufsize);
    const sample_cap: usize = byte_cap / @sizeOf(i16);
    if (sample_cap == 0) {
        _ = arcan_shmif_signal(shms, c.SHMIF_SIGAUD);
        return;
    }

    const n = @min(sample_cap, 2048);
    var i: usize = 0;
    var phase: u32 = 0;
    while (i + 1 < n) : (i += 2) {
        const amp: i16 = if (phase < 128) 8000 else -8000;
        audp[i] = amp;
        audp[i + 1] = amp;
        phase = (phase + 1) & 255;
    }
    shms.abufpos = @intCast(i);
    _ = arcan_shmif_signal(shms, c.SHMIF_SIGAUD);
}

fn request_subseg(shms: *c.arcan_shmif_cont) void {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_EXTERNAL))));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_EXTERNAL_SEGREQ))));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.kind = @as(c_uint, @bitCast(c.SEGID_CLIPBOARD));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.width = 128;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.segreq.height = 32;
    _ = c.arcan_shmif_enqueue(shms, &ev);
}

// Tell the parent we have a non-zero state-size. Durian responds by
// sending a STORE BCHUNK_OUT event with an fd to write into — that's the
// blob_recv trigger on the Zig-client decode side (when C-server echoes
// the STORE back down as a12 blob).
fn advertise_statesize(shms: *c.arcan_shmif_cont) void {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_EXTERNAL))));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(u8, @bitCast(@as(i8, @truncate(c.EVENT_EXTERNAL_STATESIZE))));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.stateinf.size = 4096;
    _ = c.arcan_shmif_enqueue(shms, &ev);
}

fn arg_match(haystack: [*c]const u8, needle: []const u8) bool {
    if (haystack == null) return false;
    const slice = std.mem.sliceTo(haystack, 0);
    var it = std.mem.splitScalar(u8, slice, ':');
    while (it.next()) |token| {
        if (std.mem.startsWith(u8, token, "mode=")) {
            const mode = token[5..];
            if (std.mem.eql(u8, mode, needle) or std.mem.eql(u8, mode, "all")) return true;
        }
    }
    return false;
}

fn arg_any(haystack: [*c]const u8) bool {
    // Default to "all" when no mode= arg is present.
    if (haystack == null) return true;
    const slice = std.mem.sliceTo(haystack, 0);
    var it = std.mem.splitScalar(u8, slice, ':');
    while (it.next()) |token| {
        if (std.mem.startsWith(u8, token, "mode=")) return false;
    }
    return true;
}

export fn afsrv_probe(con: ?*c.arcan_shmif_cont, args: ?*c.arg_arr) callconv(.c) c_int {
    _ = args;
    const con_ptr = con orelse {
        _ = c.fprintf(stdout, "afsrv_probe: ARCAN_CONNPATH missing\n");
        return 1;
    };
    var shms: c.arcan_shmif_cont = con_ptr.*;

    // Ask for 2 audio buffers up front so abufcount > 0. Plain
    // arcan_shmif_resize doesn't allocate audio slots; resize_ext with
    // abuf_sz > 0 and abuf_cnt > 0 does.
    var ext: c.struct_shmif_resize_ext = std.mem.zeroes(c.struct_shmif_resize_ext);
    ext.abuf_sz = 4096;
    ext.abuf_cnt = 2;
    ext.samplerate = 48000;
    ext.vbuf_cnt = 1;
    if (!arcan_shmif_resize_ext(&shms, 320, 200, ext)) {
        _ = c.fprintf(stderr, "afsrv_probe: resize_ext failed\n");
        return 1;
    }

    // Initial video frame so durian opens the window.
    push_vframe(&shms, c.SHMIF_RGBA(0x20, 0x20, 0x40, 0xff));

    const arg_raw: [*c]const u8 = c.getenv("ARCAN_ARG");
    const run_all = arg_any(arg_raw);
    const want_audio = run_all or arg_match(arg_raw, "audio");
    const want_subseg = run_all or arg_match(arg_raw, "subseg");
    const want_state = run_all or arg_match(arg_raw, "state");

    if (want_audio) push_audio(&shms);
    if (want_state) advertise_statesize(&shms);
    if (want_subseg) request_subseg(&shms);

    // Nudge a second video frame so any pending signal paths flush.
    push_vframe(&shms, c.SHMIF_RGBA(0x40, 0x40, 0x80, 0xff));

    // Main loop: respond to events AND re-emit audio+video every turn so
    // the a12 encoder has buffers to flush.
    var ev: c.arcan_event = undefined;
    var tick: u32 = 0;
    while (arcan_shmif_wait(&shms, &ev) != 0) {
        const cat = ev.unnamed_0.unnamed_0.category;
        if (cat == c.EVENT_TARGET) {
            const kind = ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind;
            if (kind == c.TARGET_COMMAND_EXIT) return 0;
            if (kind == c.TARGET_COMMAND_STORE) {
                // Write a tiny payload so the STORE round-trip actually ships
                // bytes back through the a12 blob stream.
                const fd = ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv;
                if (fd >= 0) {
                    const payload: []const u8 = "probe-state-v1\n";
                    _ = std.posix.write(fd, payload) catch {};
                    _ = std.posix.close(fd);
                }
            }
        }
        tick += 1;
        // Emit audio on every even tick so a12 has a continuous stream.
        if (want_audio and tick % 2 == 0) push_audio(&shms);
        // Nudge video on every tick so we keep traffic flowing.
        push_vframe(&shms, c.SHMIF_RGBA(
            @as(u8, @truncate(tick * 4)), 0x20, 0x20, 0xff));
    }
    return 0;
}
