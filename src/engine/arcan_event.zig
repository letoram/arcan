// Pure Zig port of engine/arcan_event.c — event queue, timing, benchmarks.
// C helper: arcan_event_helpers.c (queuetransfer, append_bufferstream, pull_killswitch)
// These touch opaque arcan_frameserver and cannot be ported to Zig.

const std = @import("std");
const arcan = @import("arcan");
const shmif_monitor = @import("shmif_monitor");

const arcan_event = arcan.arcan_event;
const arcan_ioevent = arcan.arcan_ioevent;

// FORCE_SYNCH (full memory barrier)
var force_synch_dummy: u32 = 0;
inline fn FORCE_SYNCH() void {
    _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);
}

// Constants
const ARCAN_EVENT_QUEUE_LIM: usize = 255;
const PP_QUEUE_SZ: u8 = 127;
const ARCAN_TIMER_TICK: i64 = 25;
const ARCAN_TICK_THRESHOLD: i64 = 100;
const ARCAN_OK: c_int = 0;
const ARCAN_ERRC_OUT_OF_SPACE: c_int = -6;

const EVSTATE_DEAD: u32 = 1;
const EVSTATE_IN_DRAIN: u32 = 2;

const EVENT_IO: u8 = arcan.EVENT_IO;
const EVENT_SYSTEM: u8 = arcan.EVENT_SYSTEM;
const EVENT_VIDEO: u8 = arcan.EVENT_VIDEO;

const EVENT_IO_BUTTON: c_int = 0;
const EVENT_IO_STATUS: c_int = 3;
const EVENT_IDEVKIND_KEYBOARD: c_int = arcan.EVENT_IDEVKIND_KEYBOARD;
const EVENT_IDEVKIND_STATUS: c_int = 64;
const EVENT_IDEVKIND_LEDCTRL: u8 = 16;
const EVENT_IDEV_ADDED: u8 = 0;
const EVENT_IDEV_REMOVED: u8 = 1;

const EVENT_SYSTEM_EXIT: c_int = 0;
const EVENT_SYSTEM_DATA_IN: c_int = 1;
const EVENT_SYSTEM_DATA_OUT: c_int = 2;
const EVENT_VIDEO_EXPIRE: c_int = 0;

const EXIT_SUCCESS: c_int = 0;

// Poll constants
const POLLIN: c_short = 0x001;
const POLLOUT: c_short = 0x004;
const POLLERR: c_short = 0x008;
const POLLHUP: c_short = 0x010;

const O_RDWR: c_uint = 0o2;
const O_WRONLY: c_uint = 0o1;
const O_RDONLY: c_uint = 0o0;

// Event sub-types (local definitions for field access)
const arcan_sevent = extern struct {
    kind: c_int,
    errcode: c_int,
    payload: extern union {
        tagv: extern struct { hitag: u32, lotag: u32 },
        mesg: extern struct { dyneval_msg: [*c]u8 },
        data: extern struct { fd: c_int, otag: isize },
        message: [64]u8,
    },
};

const arcan_vevent = extern struct {
    kind: c_int,
    _pad0: u32,
    source: i64,
};

// arcan_evctx
const arcan_event_handler = ?*const fn (*arcan_event, c_int) callconv(.c) bool;
const arcan_tick_cb = *const fn (c_int) callconv(.c) void;

pub const arcan_evctx = extern struct {
    c_ticks: i32,
    mask_cat_inp: u32,
    state_fl: u32,
    exit_code: c_int,
    drain: arcan_event_handler,
    eventbuf_sz: u8,
    eventbuf: [*c]arcan_event,
    front: *volatile u8,
    back: *volatile u8,
    local: i8,
    synch: extern struct {
        killswitch: ?*u8,
        handle: ?*anyopaque,
        synch_ptr: ?*anyopaque,
        clearval: u32,
    },
};

// arcan_benchdata
pub const arcan_benchdata = extern struct {
    bench_enabled: bool,
    ticktime: [32]c_uint,
    tickcount: c_uint,
    tickofs: u8,
    frametime: [64]c_uint,
    framecount: c_uint,
    frameofs: u8,
    framecost: [64]c_uint,
    costcount: c_uint,
    costofs: u8,
};

// pollfd
const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

// evsrc_meta
const evsrc_meta_t = struct {
    tag: isize,
    mode: c_uint,
    mask: bool,
};

// Extern C functions
extern fn arcan_timemillis() c_longlong;
extern fn arcan_timesleep(ms: c_ulong) void;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_video_deleteobject(id: i64) c_int;
extern fn platform_event_process(ctx: *arcan_evctx) void;
extern fn platform_event_init(ctx: *arcan_evctx) void;
extern fn platform_event_deinit(ctx: *arcan_evctx) void;
extern fn platform_event_reset(ctx: *arcan_evctx) void;
extern fn platform_device_lock(lockdev: c_int, lockstate: bool) void;
extern fn poll(fds: [*]pollfd, nfds: c_ulong, timeout: c_int) c_int;
extern fn getenv(name: [*c]const u8) [*c]u8;

// From arcan_db.zig
const arcan_dbh = anyopaque;
extern fn arcan_db_get_shared(appl: *[*c]const u8) ?*arcan_dbh;
extern fn arcan_db_appl_kv(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8, val: [*c]const u8) bool;
extern fn arcan_db_appl_val(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;

// Offset-based accessors for opaque arcan_frameserver
const Fsrv = @import("shmif_offsets").Fsrv;
const AgpBufPlane = @import("engine_offsets").AgpBufferPlane;

// Extern functions needed by ported helpers
extern fn arcan_fetchhandle(dpipe: c_int, blocking: bool) c_int;
extern fn arcan_frameserver_close_bufferqueues(tgt: *anyopaque, a: bool, b: bool) void;
extern fn arcan_frameserver_free(tgt: *anyopaque) void;
extern fn arcan_frameserver_flush(tgt: *anyopaque) void;
extern fn arcan_frameserver_signal(tgt: *anyopaque, mask: c_int) void;
extern fn arcan_random(buf: [*]u8, len: usize) void;
extern fn arcan_sem_post(handle: ?*anyopaque) c_int;
extern fn platform_fsrv_clock() usize;
extern fn platform_fsrv_enter(fsrv: *anyopaque, tramp: *anyopaque) void;
extern fn platform_fsrv_leave() void;
extern fn setjmp(env: *anyopaque) c_int;

// Constants for queuetransfer
const EVENT_EXTERNAL: u8 = arcan.EVENT_EXTERNAL;
const EVENT_FSRV: u8 = arcan.EVENT_FSRV;
const EVENT_TARGET: u8 = arcan.EVENT_TARGET;
const EVENT_EXTERNAL_SEGREQ: c_int = 10;
const EVENT_EXTERNAL_BUFFERSTREAM: c_int = 4;
const EVENT_EXTERNAL_PRIVDROP: c_int = 20;
const EVENT_EXTERNAL_INPUTMASK: c_int = 21;
const EVENT_EXTERNAL_CLOCKREQ: c_int = 18;
const EVENT_EXTERNAL_REGISTER: c_int = 16;
const EVENT_EXTERNAL_FLUSHAUD: c_int = 9;
const EVENT_FSRV_IONESTED: c_int = 10;
const TARGET_COMMAND_BUFFER_FAIL: c_int = 21;
const SEGID_UNKNOWN: c_int = 0;
const PP_SHMPAGE_MAXW: u16 = 8192;
const PP_SHMPAGE_MAXH: u16 = 8192;

// fsrvevent byte offsets within arcan_event.data[]
const FSRV_KIND: usize = 0; // c_int at offset 0
const FSRV_INPUT: usize = 8; // arcan_ioevent at offset 8
const FSRV_VIDEO: usize = 104; // i64 at offset 104
const FSRV_OTAG: usize = 112; // isize at offset 112

// sizeof jmp_buf for TRAMP_GUARD
// Darwin arm64 sigjmp_buf is 392 bytes (49 longs); linux aarch64 is 312.
const JMPBUF_SIZE: usize = if (@import("builtin").os.tag.isDarwin()) 400 else 312;

// Static state
var eventbuf: [ARCAN_EVENT_QUEUE_LIM]arcan_event = std.mem.zeroes([ARCAN_EVENT_QUEUE_LIM]arcan_event);
var eventfront: u8 = 0;
var eventback: u8 = 0;
var epoch: i64 = 0;

var default_evctx: arcan_evctx = .{
    .c_ticks = 0,
    .mask_cat_inp = 0,
    .state_fl = 0,
    .exit_code = 0,
    .drain = null,
    .eventbuf_sz = ARCAN_EVENT_QUEUE_LIM,
    .eventbuf = &eventbuf,
    .front = &eventfront,
    .back = &eventback,
    .local = 1,
    .synch = .{
        .killswitch = null,
        .handle = null,
        .synch_ptr = null,
        .clearval = 0,
    },
};

var panic_keysym: c_int = -1;
var panic_keymod: c_int = -1;

var evsrc_pollset: [64]pollfd = [_]pollfd{.{ .fd = 0, .events = 0, .revents = 0 }} ** 64;
var evsrc_meta: [64]evsrc_meta_t = [_]evsrc_meta_t{.{ .tag = 0, .mode = 0, .mask = false }} ** 64;
var evsrc_bitmap: u64 = 0;

export var benchdata: arcan_benchdata = std.mem.zeroes(arcan_benchdata);

// bench_register_tick static state
var bench_lasttick: c_longlong = -1;
// bench_register_frame static state
var bench_lastframe: c_longlong = -1;

// Internal helpers

fn queue_full(ctx: *arcan_evctx) bool {
    return ((@as(u16, ctx.front.*) + 1) % @as(u16, ctx.eventbuf_sz)) == @as(u16, ctx.back.*);
}

fn queue_empty(ctx: *arcan_evctx) bool {
    return ctx.front.* == ctx.back.*;
}

fn queue_used(dq: *arcan_evctx) c_int {
    const f = dq.front.*;
    const b = dq.back.*;
    return if (f > b)
        @as(c_int, dq.eventbuf_sz) - @as(c_int, f) + @as(c_int, b)
    else
        @as(c_int, b) - @as(c_int, f);
}

fn cstr(s: [*c]const u8) []const u8 {
    if (s == null) return "";
    return std.mem.sliceTo(s, 0);
}

fn mode_to_poll(mode: c_uint) c_short {
    var result: c_short = 0;
    if (mode == O_RDWR) {
        result = POLLIN | POLLOUT;
    } else if (mode == O_WRONLY) {
        result = POLLOUT;
    } else if (mode == O_RDONLY) {
        result = POLLIN;
    }
    return result | POLLERR | POLLHUP;
}

// pull_killswitch (was in arcan_event_helpers.c)

fn pull_killswitch(ctx: *arcan_evctx) void {
    const ks: ?*anyopaque = @ptrCast(ctx.synch.killswitch);
    _ = arcan_sem_post(ctx.synch.handle);
    arcan_warning("inconsistency while processing shmpage events, pulling killswitch.\n");
    if (ks) |k| arcan_frameserver_free(k);
    ctx.synch.killswitch = null;
}

// append_bufferstream (was in arcan_event_helpers.c)

fn append_bufferstream(tgt: *anyopaque, ev_data: [*]u8) bool {
    const dpipe = Fsrv.getDpipe(tgt);
    const fd = arcan_fetchhandle(dpipe, false);
    if (fd == -1) {
        arcan_warning("fetchhandle-bstream mismatch\n");
        return append_bufferstream_fail(tgt);
    }

    const incoming_used = Fsrv.getVstreamIncomingUsed(tgt);
    if (incoming_used >= 4)
        return append_bufferstream_fail(tgt);

    const plane = Fsrv.getVstreamIncomingPlane(tgt, incoming_used);

    // Read bstream.flags from ext event at byte 49 (offset within ext payload)
    const bstream_flags = ev_data[49];
    if ((bstream_flags & 1) == 1) {
        const fence = arcan_fetchhandle(dpipe, false);
        AgpBufPlane.setFence(plane, fence);
    } else {
        AgpBufPlane.setFence(plane, -1);
    }

    AgpBufPlane.setFd(plane, fd);
    // bstream fields: stride(16), format(20), offset(24), mod_hi(28), mod_lo(32), width(40), height(44), left(48)
    const stride_val = std.mem.readInt(u32, ev_data[16..20], .little);
    const format_val = std.mem.readInt(u32, ev_data[20..24], .little);
    const offset_val = std.mem.readInt(u32, ev_data[24..28], .little);
    const mod_hi_val = std.mem.readInt(u32, ev_data[28..32], .little);
    const mod_lo_val = std.mem.readInt(u32, ev_data[32..36], .little);
    const width_val = std.mem.readInt(u32, ev_data[40..44], .little);
    const height_val = std.mem.readInt(u32, ev_data[44..48], .little);
    const left = ev_data[48];

    AgpBufPlane.setGbmStride(plane, stride_val);
    AgpBufPlane.setGbmOffset(plane, offset_val);
    AgpBufPlane.setGbmModHi(plane, mod_hi_val);
    AgpBufPlane.setGbmModLo(plane, mod_lo_val);
    AgpBufPlane.setGbmFormat(plane, format_val);
    AgpBufPlane.setW(plane, width_val);
    AgpBufPlane.setH(plane, height_val);
    Fsrv.setVstreamIncomingUsed(tgt, incoming_used + 1);

    if (left == 0) {
        arcan_frameserver_close_bufferqueues(tgt, false, true);
        const buf_sz = Fsrv.sizeof_agp_buffer_plane * 4;
        const inc_base = Fsrv.getVstreamIncomingBase(tgt);
        const pend_base = Fsrv.getVstreamPendingBase(tgt);
        @memcpy(pend_base[0..buf_sz], inc_base[0..buf_sz]);
        Fsrv.setVstreamPendingUsed(tgt, Fsrv.getVstreamIncomingUsed(tgt));
        Fsrv.setVstreamIncomingUsed(tgt, 0);
        @memset(inc_base[0..buf_sz], 0);
        return true;
    }

    return false;
}

fn append_bufferstream_fail(tgt: *anyopaque) bool {
    arcan_frameserver_close_bufferqueues(tgt, true, true);
    var fail_ev = arcan_event.zeroes();
    fail_ev.setCategory(EVENT_TARGET);
    // Set tgt.kind = TARGET_COMMAND_BUFFER_FAIL at offset 0 (kind is first field)
    const kind_ptr: *align(1) c_int = @ptrCast(&fail_ev.pad[0]);
    kind_ptr.* = TARGET_COMMAND_BUFFER_FAIL;
    _ = arcan_event_enqueue(@ptrCast(@alignCast(Fsrv.getOutqueuePtr(tgt))), &fail_ev);
    Fsrv.setVstreamDead(tgt, true);
    return true;
}

// arcan_event_queuetransfer (was in arcan_event_helpers.c)

export fn arcan_event_queuetransfer(
    dstqueue_opt: ?*arcan_evctx,
    srcqueue_opt: ?*arcan_evctx,
    allowed: c_int,
    sat_arg: f32,
    tgt_opt: ?*anyopaque,
) c_int {
    const srcqueue = srcqueue_opt orelse return 0;
    const dstqueue = dstqueue_opt orelse return 0;
    if (@intFromPtr(srcqueue.front) == 0 or @intFromPtr(srcqueue.back) == 0)
        return 0;
    const tgt = tgt_opt orelse return 0;

    var wake = false;
    var drain = false;
    var sat = sat_arg;

    if (sat < 0.0) {
        drain = true;
        sat = 1.0;
    }

    const cap: c_int = @intFromFloat(@floor(@as(f32, @floatFromInt(dstqueue.eventbuf_sz)) * sat));

    while (!queue_empty(srcqueue) and queue_used(dstqueue) < cap) {
        var inev: arcan_event = undefined;
        if (arcan_event_poll(srcqueue, &inev) == 0)
            break;

        const cat = inev.getCategory();
        const allowed_u8: u8 = @truncate(@as(u32, @bitCast(allowed)));

        // Env-gated shmif-monitor: record one line per inbound event.
        {
            const kind_byte: c_int = switch (cat) {
                EVENT_EXTERNAL => @intCast(inev.asExt().kind),
                EVENT_IO => @intCast(inev.pad[0]),
                else => -1,
            };
            const tgt_vid: i64 = @bitCast(Fsrv.getVid(tgt));
            shmif_monitor.emit("in", tgt_vid, @intCast(cat), kind_byte);
        }

        if (cat == EVENT_IO) {
            if ((cat & allowed_u8) != 0) {
                // allowed, pass through
            } else {
                // Construct IONESTED event
                const old_io = inev.pad[0..@sizeOf(arcan_ioevent)].*;
                inev = arcan_event.zeroes();
                inev.setCategory(EVENT_FSRV);
                const kind_ptr: *align(1) c_int = @ptrCast(&inev.pad[FSRV_KIND]);
                kind_ptr.* = EVENT_FSRV_IONESTED;
                const otag_ptr: *align(1) isize = @ptrCast(&inev.pad[FSRV_OTAG]);
                otag_ptr.* = Fsrv.getTag(tgt);
                const video_ptr: *align(1) i64 = @ptrCast(&inev.pad[FSRV_VIDEO]);
                video_ptr.* = Fsrv.getVid(tgt);
                @memcpy(inev.pad[FSRV_INPUT..][0..@sizeOf(arcan_ioevent)], &old_io);
            }
        } else if ((cat & allowed_u8) == 0) {
            continue;
        }

        if (cat == EVENT_EXTERNAL) {
            const ext = inev.asExt();
            switch (ext.kind) {
                EVENT_EXTERNAL_SEGREQ => {
                    if (ext.payload.segreq.width > PP_SHMPAGE_MAXW)
                        ext.payload.segreq.width = PP_SHMPAGE_MAXW;
                    if (ext.payload.segreq.height > PP_SHMPAGE_MAXH)
                        ext.payload.segreq.height = PP_SHMPAGE_MAXH;
                },
                EVENT_EXTERNAL_BUFFERSTREAM => {
                    wake = append_bufferstream(tgt, &inev.pad);
                    continue;
                },
                EVENT_EXTERNAL_PRIVDROP => {
                    Fsrv.orFlagsExternal(tgt, ext.payload.privdrop.external != 0);
                    Fsrv.setFlagsNetworked(tgt, ext.payload.privdrop.networked != 0);
                    Fsrv.orFlagsSandboxed(tgt, ext.payload.privdrop.sandboxed != 0);
                    ext.payload.privdrop.external = if (Fsrv.getFlagsExternal(tgt)) 1 else 0;
                    ext.payload.privdrop.networked = if (Fsrv.getFlagsNetworked(tgt)) 1 else 0;
                    ext.payload.privdrop.sandboxed = if (Fsrv.getFlagsSandboxed(tgt)) 1 else 0;
                },
                EVENT_EXTERNAL_INPUTMASK => {
                    Fsrv.setDevicemask(tgt, ext.payload.inputmask.device);
                    Fsrv.setDatamask(tgt, ext.payload.inputmask.types);
                },
                EVENT_EXTERNAL_CLOCKREQ => {
                    if (ext.payload.clock.dynamic == 1) {
                        if (ext.payload.clock.rate != 0) {
                            Fsrv.setClockPresent(tgt, ext.payload.clock.rate);
                            Fsrv.setClockMscFeedback(tgt, true);
                        } else {
                            Fsrv.setClockMscFeedback(tgt, !Fsrv.getClockMscFeedback(tgt));
                        }
                    } else if (ext.payload.clock.dynamic == 2) {
                        Fsrv.setClockVblank(tgt, !Fsrv.getClockVblank(tgt));
                    } else if (Fsrv.getFlagsAutoclock(tgt)) {
                        Fsrv.setClockOnce(tgt, ext.payload.clock.once != 0);
                        Fsrv.setClockFrame(tgt, ext.payload.clock.dynamic != 0);
                        Fsrv.setClockLeft(tgt, ext.payload.clock.rate);
                        Fsrv.setClockStart(tgt, ext.payload.clock.rate);
                        Fsrv.setClockId(tgt, ext.payload.clock.id);
                        Fsrv.setClockOnce(tgt, ext.payload.clock.once != 0);
                    }
                    continue;
                },
                EVENT_EXTERNAL_REGISTER => {
                    if (Fsrv.getSegid(tgt) == SEGID_UNKNOWN) {
                        if (ext.payload.registr.guid[0] == 0 and ext.payload.registr.guid[1] == 0) {
                            arcan_random(Fsrv.getGuidSlice(tgt), 16);
                        } else {
                            const guid_dst = Fsrv.getGuidSlice(tgt);
                            const guid_src: [*]const u8 = @ptrCast(&ext.payload.registr.guid);
                            @memcpy(guid_dst[0..16], guid_src[0..16]);
                        }
                    }
                    // snprintf(tgt->title, 64, "%s", inev.ext.registr.title)
                    const title_dst = Fsrv.getTitleSlice(tgt);
                    const title_src = &ext.payload.registr.title;
                    // Find null terminator or copy up to 63 bytes + null
                    var len: usize = 0;
                    while (len < 63 and title_src[len] != 0) : (len += 1) {}
                    @memcpy(title_dst[0..len], title_src[0..len]);
                    title_dst[len] = 0;
                },
                EVENT_EXTERNAL_FLUSHAUD => {
                    arcan_frameserver_flush(tgt);
                    continue;
                },
                else => {},
            }
            ext.source = Fsrv.getVid(tgt);
        } else if (cat == EVENT_IO) {
            const io = inev.asIoMut();
            io.subid = @truncate(@as(u64, @bitCast(Fsrv.getVid(tgt))));
        }
        wake = true;

        if (drain and dstqueue.drain != null) {
            Fsrv.setFused(tgt, true);
            const last_stamp = platform_fsrv_clock();

            if (dstqueue.drain.?(&inev, 1)) {
                if (last_stamp != platform_fsrv_clock()) {
                    // TRAMP_GUARD: setjmp + platform_fsrv_enter for SIGBUS safety
                    var tramp: [JMPBUF_SIZE]u8 = undefined;
                    if (setjmp(@ptrCast(&tramp)) != 0)
                        return -1;
                    platform_fsrv_enter(tgt, @ptrCast(&tramp));
                }

                Fsrv.setFused(tgt, false);
                if (Fsrv.getFuseBlown(tgt))
                    break;
            }
            Fsrv.setFused(tgt, false);
            continue;
        }

        _ = arcan_event_enqueue(dstqueue, &inev);
    }

    if (wake)
        arcan_frameserver_signal(tgt, 1); // SYNC_EVENT

    return if (Fsrv.getFuseBlown(tgt)) @as(c_int, -2) else @as(c_int, 0);
}

// Exported functions

export fn arcan_event_defaultctx() *arcan_evctx {
    return &default_evctx;
}

export fn arcan_event_poll(ctx: *arcan_evctx, dst: *arcan_event) c_int {
    if (queue_empty(ctx))
        return 0;

    if (ctx.local == 0) {
        FORCE_SYNCH();
        if (ctx.front.* > PP_QUEUE_SZ) {
            pull_killswitch(ctx);
            return 0;
        } else {
            dst.* = ctx.eventbuf[ctx.front.*];
            @memset(&ctx.eventbuf[ctx.front.*].pad, 0xff);
            ctx.front.* = (ctx.front.* +% 1) % PP_QUEUE_SZ;
        }
    } else {
        dst.* = ctx.eventbuf[ctx.front.*];
        ctx.front.* = (ctx.front.* +% 1) % ctx.eventbuf_sz;
    }

    return 1;
}

export fn arcan_event_repl(
    ctx: *arcan_evctx,
    cat: c_int,
    r_ofs: usize,
    r_b: usize,
    cmpbuf: ?*anyopaque,
    w_ofs: usize,
    w_b: usize,
    w_buf: ?*anyopaque,
) void {
    if (ctx.local == 0) return;

    var front: u8 = ctx.front.*;
    while (front != ctx.back.*) {
        if (@as(c_int, @as(*const arcan_event, @ptrCast(&ctx.eventbuf[front])).getCategory()) == cat) {
            const ev_bytes: [*]u8 = @ptrCast(&ctx.eventbuf[front]);
            const cmp_bytes: [*]const u8 = @ptrCast(cmpbuf orelse continue);
            if (std.mem.eql(u8, ev_bytes[r_ofs..][0..r_b], cmp_bytes[0..r_b])) {
                const src_bytes: [*]const u8 = @ptrCast(w_buf orelse continue);
                @memcpy(ev_bytes[w_ofs..][0..w_b], src_bytes[0..w_b]);
            }
        }
        front = (front +% 1) % ctx.eventbuf_sz;
    }
}

export fn arcan_event_maskall(ctx: *arcan_evctx) void {
    ctx.mask_cat_inp = 0xffffffff;
}

export fn arcan_event_clearmask(ctx: *arcan_evctx) void {
    ctx.mask_cat_inp = 0;
}

export fn arcan_event_setmask(ctx: *arcan_evctx, mask: u32) void {
    ctx.mask_cat_inp = mask;
}

export fn arcan_event_denqueue(ctx: *arcan_evctx, src: *const arcan_event) c_int {
    if (ctx.drain) |drain_fn| {
        var ev = src.*;
        if (drain_fn(&ev, 1))
            return ARCAN_OK;
    }
    return arcan_event_enqueue(ctx, src);
}

export fn arcan_event_enqueue(ctx: *arcan_evctx, src_opt: ?*const arcan_event) c_int {
    const src = src_opt orelse return ARCAN_OK;

    // early-out mask-filter
    if ((@as(u32, src.getCategory()) & ctx.mask_cat_inp) != 0 or
        (ctx.state_fl & EVSTATE_DEAD) > 0)
    {
        if (src.getCategory() == EVENT_IO) {
            arcan_warning(
                "EVTRACE enqueue: DROPPED IO event (mask=0x%x state_fl=0x%x)\n",
                ctx.mask_cat_inp,
                ctx.state_fl,
            );
        }
        return ARCAN_OK;
    }

    if (queue_full(ctx)) {
        if (ctx.drain) |drain_fn| {
            if ((ctx.state_fl & EVSTATE_IN_DRAIN) > 0) {
                var ev = src.*;
                if (drain_fn(&ev, 1))
                    return ARCAN_OK;
                return ARCAN_ERRC_OUT_OF_SPACE;
            } else {
                ctx.state_fl |= EVSTATE_IN_DRAIN;
                _ = arcan_event_feed(ctx, drain_fn, null);
                ctx.state_fl &= ~EVSTATE_IN_DRAIN;
            }
        } else {
            return ARCAN_ERRC_OUT_OF_SPACE;
        }
    }

    // panic key check
    if (panic_keysym != -1 and panic_keymod != -1 and
        src.getCategory() == EVENT_IO)
    {
        const io = src.asIo();
        if (io.kind == EVENT_IO_BUTTON and
            io.devkind == EVENT_IDEVKIND_KEYBOARD and
            io.input.translated.modifiers == @as(u16, @bitCast(@as(i16, @truncate(panic_keymod)))) and
            io.input.translated.keysym == @as(u32, @bitCast(panic_keysym)))
        {
            var ev = arcan_event.zeroes();
            ev.setCategory(EVENT_SYSTEM);
            const sys: *arcan_sevent = @ptrCast(@alignCast(&ev.pad));
            sys.kind = EVENT_SYSTEM_EXIT;
            sys.errcode = EXIT_SUCCESS;
            return arcan_event_enqueue(ctx, &ev);
        }
    }

    ctx.eventbuf[ctx.back.* % ctx.eventbuf_sz] = src.*;
    ctx.back.* = (ctx.back.* +% 1) % ctx.eventbuf_sz;

    return ARCAN_OK;
}

export fn arcan_event_blacklist(idstr: [*c]const u8) void {
    const s = cstr(idstr);
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrintZ(&buf, "bl_{s}", .{s}) catch return;
    var appl: [*c]const u8 = null;
    const dbh = arcan_db_get_shared(&appl);
    _ = arcan_db_appl_kv(dbh, appl, key.ptr, "block");
}

export fn arcan_event_blacklisted(idstr: [*c]const u8) bool {
    const s = cstr(idstr);
    var buf: [256]u8 = undefined;
    const key = std.fmt.bufPrintZ(&buf, "bl_{s}", .{s}) catch return false;
    var appl: [*c]const u8 = null;
    const dbh = arcan_db_get_shared(&appl);
    const res: [*c]u8 = arcan_db_appl_val(dbh, appl, key.ptr);
    const rv = (res != null and std.mem.eql(u8, cstr(res), "block"));
    arcan_mem_free(@ptrCast(res));
    return rv;
}

export fn arcan_frametime() i64 {
    const now: i64 = @intCast(arcan_timemillis());
    if (now < epoch)
        epoch = now - (epoch - now);
    return now - epoch;
}

export fn arcan_event_process(ctx: *arcan_evctx, cb: arcan_tick_cb) f32 {
    const base: i64 = @as(i64, ctx.c_ticks) * ARCAN_TIMER_TICK;
    const delta: i64 = arcan_frametime() - base;

    platform_event_process(ctx);

    if (delta > ARCAN_TIMER_TICK) {
        var nticks: i64 = @divFloor(delta, ARCAN_TIMER_TICK);
        if (nticks > ARCAN_TICK_THRESHOLD) {
            epoch += (nticks - 1) * ARCAN_TIMER_TICK;
            nticks = 1;
        } else if (nticks < 0) {
            epoch += delta - ARCAN_TIMER_TICK;
            nticks = 1;
        }

        ctx.c_ticks += @intCast(nticks);
        cb(@intCast(nticks));
        arcan_bench_register_tick(@intCast(nticks));
        return arcan_event_process(ctx, cb);
    }

    return @as(f32, @floatFromInt(delta)) / @as(f32, @floatFromInt(ARCAN_TIMER_TICK));
}

export fn arcan_bench_register_tick(nticks_arg: c_uint) void {
    if (!benchdata.bench_enabled)
        return;

    var nticks = nticks_arg;
    while (nticks > 0) : (nticks -= 1) {
        const ftime = arcan_timemillis();
        benchdata.tickcount += 1;

        if (bench_lasttick > 0 and ftime > bench_lasttick) {
            const delta: c_uint = @intCast(ftime - bench_lasttick);
            benchdata.ticktime[benchdata.tickofs] = delta;
            benchdata.tickofs = @intCast((@as(u32, benchdata.tickofs) + 1) % 32);
        }

        bench_lasttick = ftime;
    }
}

export fn arcan_event_purge() void {
    eventfront = 0;
    eventback = 0;
    platform_event_reset(&default_evctx);
}

export fn arcan_bench_data() *arcan_benchdata {
    return &benchdata;
}

export fn arcan_bench_register_cost(cost: c_uint) void {
    benchdata.framecost[benchdata.costofs] = cost;
    if (!benchdata.bench_enabled)
        return;

    benchdata.costcount += 1;
    benchdata.costofs = @intCast((@as(u32, benchdata.costofs) + 1) % 64);
}

export fn arcan_bench_register_frame() void {
    if (!benchdata.bench_enabled)
        return;

    const ftime = arcan_timemillis();
    if (bench_lastframe > 0 and ftime > bench_lastframe) {
        const delta: c_uint = @intCast(ftime - bench_lastframe);
        benchdata.frametime[benchdata.frameofs] = delta;
        benchdata.framecount += 1;
        benchdata.frameofs = @intCast((@as(u32, benchdata.frameofs) + 1) % 64);
    }

    bench_lastframe = ftime;
}

export fn arcan_event_deinit(ctx: *arcan_evctx, flush: bool) void {
    platform_event_deinit(ctx);

    if (!flush)
        return;

    eventfront = 0;
    eventback = 0;
}

export fn arcan_event_feed(
    ctx: *arcan_evctx,
    hnd: *const fn (*arcan_event, c_int) callconv(.c) bool,
    exit_code: ?*c_int,
) bool {
    // dead from previous call
    if ((ctx.state_fl & EVSTATE_DEAD) != 0) {
        if (exit_code) |ec| ec.* = ctx.exit_code;
        return false;
    }

    // BUG-2 ASSERT: log queue state and event categories
    while (ctx.front.* != ctx.back.*) {
        const ev: *arcan_event = @ptrCast(&ctx.eventbuf[ctx.front.*]);
        ctx.front.* = (ctx.front.* +% 1) % ctx.eventbuf_sz;

        const cat = ev.getCategory();
        if (cat == EVENT_VIDEO) {
            const vid: *const arcan_vevent = @ptrCast(@alignCast(&ev.pad));
            if (vid.kind == EVENT_VIDEO_EXPIRE) {
                _ = arcan_video_deleteobject(vid.source);
            } else {
                _ = hnd(ev, 0);
            }
        } else if (cat == EVENT_SYSTEM) {
            const sys: *const arcan_sevent = @ptrCast(@alignCast(&ev.pad));
            if (sys.kind == EVENT_SYSTEM_EXIT) {
                ctx.state_fl |= EVSTATE_DEAD;
                ctx.exit_code = sys.errcode;
                if (exit_code) |ec| ec.* = sys.errcode;
            } else {
                _ = hnd(ev, 0);
            }
        } else {
            if (cat == EVENT_IO) {
                const io = ev.asIo();
                if (io.devkind == EVENT_IDEVKIND_KEYBOARD) {
                    arcan_warning(
                        "EVTRACE feed: KBD kind=%d dt=%d subid=%d scan=%d sym=%d mod=%d active=%d utf0=%d\n",
                        @as(c_int, io.kind),
                        @as(c_int, io.datatype),
                        @as(c_int, io.subid),
                        @as(c_int, io.input.translated.scancode),
                        @as(c_int, @bitCast(io.input.translated.keysym)),
                        @as(c_int, io.input.translated.modifiers),
                        @as(c_int, io.input.translated.active),
                        @as(c_int, io.input.translated.utf8[0]),
                    );
                }
            }
            _ = hnd(ev, 0);
        }
    }

    if ((ctx.state_fl & EVSTATE_DEAD) != 0)
        return arcan_event_feed(ctx, hnd, exit_code)
    else
        return true;
}

export fn arcan_event_add_source(
    ctx: *arcan_evctx,
    fd: c_int,
    mode_arg: c_uint,
    otag: isize,
    masked: bool,
) bool {
    _ = ctx;
    const mode = mode_to_poll(mode_arg);

    // find first free slot
    const inverted = ~evsrc_bitmap;
    if (inverted == 0) return false;
    const i: u6 = @intCast(@ctz(inverted));

    evsrc_pollset[i].fd = fd;
    evsrc_pollset[i].events = mode;
    evsrc_meta[i].mode = mode_arg;
    evsrc_meta[i].tag = otag;
    evsrc_meta[i].mask = masked;
    evsrc_bitmap |= @as(u64, 1) << i;

    return true;
}

export fn arcan_event_poll_sources(ctx: *arcan_evctx, timeout: c_int) void {
    const nelem = poll(&evsrc_pollset, 64, timeout);
    if (nelem <= 0) {
        if (timeout > 0)
            arcan_timesleep(@intCast(timeout));
        return;
    }

    for (0..64) |i| {
        const ent = &evsrc_pollset[i];
        if (ent.fd <= 0 or ent.revents == 0 or evsrc_meta[i].mask)
            continue;

        var ev = arcan_event.zeroes();
        ev.setCategory(EVENT_SYSTEM);
        const sys: *arcan_sevent = @ptrCast(@alignCast(&ev.pad));
        sys.payload.data.fd = evsrc_pollset[i].fd;
        sys.payload.data.otag = evsrc_meta[i].tag;

        if ((ent.revents & POLLIN) != 0 or
            ((ent.revents & (POLLERR | POLLHUP)) != 0 and (ent.events & POLLIN) != 0))
        {
            sys.kind = EVENT_SYSTEM_DATA_IN;
            _ = arcan_event_denqueue(ctx, &ev);
        }

        if ((ent.revents & POLLOUT) != 0 or
            ((ent.revents & (POLLERR | POLLHUP)) != 0 and (ent.events & POLLOUT) != 0))
        {
            sys.kind = EVENT_SYSTEM_DATA_OUT;
            _ = arcan_event_denqueue(ctx, &ev);
        }
    }
}

export fn arcan_event_del_source(
    ctx: *arcan_evctx,
    fd: c_int,
    mode_arg: c_uint,
    out: ?*isize,
) bool {
    _ = ctx;
    const mode = mode_to_poll(mode_arg);
    for (0..64) |i| {
        if (evsrc_pollset[i].fd == fd and evsrc_pollset[i].events == mode) {
            evsrc_pollset[i].fd = -1;
            evsrc_bitmap &= ~(@as(u64, 1) << @intCast(i));
            if (out) |o| o.* = evsrc_meta[i].tag;
            evsrc_meta[i] = .{ .tag = 0, .mode = 0, .mask = false };
            evsrc_pollset[i] = .{ .fd = 0, .events = 0, .revents = 0 };
            return true;
        }
    }
    return false;
}

export fn arcan_event_setdrain(ctx: *arcan_evctx, drain: arcan_event_handler) void {
    if (ctx.local == 0) return;
    ctx.drain = drain;
}

export fn arcan_evctx_sizeof() usize {
    return @sizeOf(arcan_evctx);
}

export fn arcan_event_init(ctx: *arcan_evctx) void {
    if (ctx.local == 0) return;

    const panicbutton: [*c]u8 = getenv("ARCAN_EVENT_SHUTDOWN");
    if (panicbutton != null) {
        const s = cstr(panicbutton);
        if (std.mem.indexOfScalar(u8, s, ':')) |colon_pos| {
            const keysym_str = s[0..colon_pos];
            const keymod_str = s[colon_pos + 1 ..];
            panic_keysym = std.fmt.parseInt(c_int, keysym_str, 10) catch -1;
            panic_keymod = std.fmt.parseInt(c_int, keymod_str, 10) catch -1;
        } else {
            arcan_warning("ARCAN_EVENT_SHUTDOWN=%s, malformed key "
                ++ "expecting number:number (keysym:modifiers).\n", panicbutton);
        }
    }

    epoch = @intCast(arcan_timemillis() - @as(c_longlong, ctx.c_ticks) * ARCAN_TIMER_TICK);
    platform_event_init(ctx);
}

export fn arcan_led_removed(devid: c_int) void {
    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_IO);
    const io: *arcan_ioevent = @ptrCast(@alignCast(&ev.pad));
    io.kind = EVENT_IO_STATUS;
    io.devkind = EVENT_IDEVKIND_STATUS;
    io.devid = @truncate(@as(u32, @bitCast(devid)));
    io.input.status.domain = 1;
    io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL;
    io.input.status.action = EVENT_IDEV_REMOVED;
    _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

export fn arcan_led_added(devid: c_int, refdev: c_int, label: [*c]const u8) void {
    var ev = arcan_event.zeroes();
    ev.setCategory(EVENT_IO);
    const io: *arcan_ioevent = @ptrCast(@alignCast(&ev.pad));
    io.kind = EVENT_IO_STATUS;
    io.devkind = EVENT_IDEVKIND_STATUS;
    io.devid = @truncate(@as(u32, @bitCast(devid)));
    io.input.status.devref = @truncate(@as(u32, @bitCast(refdev)));
    io.input.status.domain = 1;
    io.input.status.devkind = EVENT_IDEVKIND_LEDCTRL;
    io.input.status.action = EVENT_IDEV_ADDED;

    // Copy label into io.label (16 bytes)
    const src = cstr(label);
    const n = @min(src.len, 15);
    @memcpy(io.label[0..n], src[0..n]);
    io.label[n] = 0;

    _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
}

export fn arcan_device_lock(lockdev: c_int, lockstate: bool) void {
    platform_device_lock(lockdev, lockstate);
}
