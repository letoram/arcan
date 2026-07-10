// Pure Zig port of engine/arcan_conductor.c — frame scheduling / synchronization.
// Opaque struct field access (vobj->owner->msc, fsrv->desc.recovery_tick,
// fsrv->flags.locked) handled via engine_offsets.zig / shmif_offsets.zig.

const std = @import("std");
const arcan = @import("arcan");

const arcan_event = arcan.arcan_event;
const arcan_tgtevent = arcan.arcan_tgtevent;

const Fsrv = @import("shmif_offsets").Fsrv;
const Vobj = @import("engine_offsets").Vobj;
const RenderTarget = @import("engine_offsets").RenderTarget;

// Constants
const EVENT_TARGET: u8 = arcan.EVENT_TARGET;
const TARGET_COMMAND_STEPFRAME: c_int = 4;

const EXIT_FAILURE: c_int = 1;

// Trace levels (from arcan_trace.h enum trace_level)
const TRACE_SYS_DEFAULT: u8 = 0;
const TRACE_SYS_SLOW: u8 = 1;
const TRACE_SYS_FAST: u8 = 2;
const TRACE_SYS_ERROR: u8 = 4;

// Lua entrypoint triggers (from arcan_lua.h)
const EP_TRIGGER_PREFRAME: u64 = 1 << 4;
const EP_TRIGGER_POSTFRAME: u64 = 1 << 5;

// arcan_benchdata (from arcan_event.zig)
const arcan_benchdata = extern struct {
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

// platform_timing (from platform_types.h)
const platform_timing = extern struct {
    tickless: bool,
    cost_us: c_uint,
};

// Extern C functions
extern fn arcan_timemillis() c_longlong;
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, align_hint: c_int) ?*anyopaque;

extern fn arcan_video_pollfeed() void;
extern fn arcan_vint_pollfeed(vid: i64, step: bool) c_int;
extern fn arcan_audio_refresh() usize;
extern fn arcan_video_tick(nticks: c_uint, njobs: *c_uint) c_uint;
extern fn arcan_audio_tick(ntt: u8) void;
extern fn arcan_mem_tick() void;

extern fn arcan_frameserver_lock_buffers(state: c_int) void;
extern fn arcan_frameserver_releaselock(tgt: *anyopaque) c_int;
extern fn platform_fsrv_pushevent(fsrv: *anyopaque, ev: *const arcan_event) c_int;

extern fn agp_status_ok(msg: ?*[*c]const u8) bool;
extern fn platform_video_reset(cardid: c_int, swap_primary: bool) void;
extern fn platform_video_synch(tick: u64, fract: f32, pre: ?*anyopaque, post: ?*anyopaque) void;
extern fn platform_hardware_clockcfg() platform_timing;

extern fn arcan_event_defaultctx() *anyopaque;
extern fn arcan_event_poll_sources(ctx: *anyopaque, timeout: c_int) void;
extern fn arcan_event_process(ctx: *anyopaque, cb: *const fn (c_int) callconv(.c) void) f32;
extern fn arcan_event_feed(
    ctx: *anyopaque,
    hnd: *const fn (*arcan_event, c_int) callconv(.c) bool,
    exit_code: ?*c_int,
) bool;
extern fn arcan_event_setdrain(ctx: *anyopaque, drain: ?*const fn (*arcan_event, c_int) callconv(.c) bool) void;

extern fn arcan_bench_register_frame() void;
extern fn arcan_bench_data() *arcan_benchdata;

extern fn arcan_trace_mark(
    sys: [*c]const u8,
    subsys: [*c]const u8,
    trigger: u8,
    tracelevel: u8,
    identifier: u64,
    quant: u32,
    message: [*c]const u8,
    file_name: [*c]const u8,
    func_name: [*c]const u8,
    line: u32,
) void;
extern var arcan_trace_enabled: bool;

// Lua VM functions
const arcan_luactx = anyopaque;
extern fn arcan_lua_pushevent(ctx: *arcan_luactx, ev: ?*arcan_event) bool;
extern fn arcan_lua_callvoidfun(
    ctx: *arcan_luactx,
    fun: [*c]const u8,
    masksrc: u64,
    warn: bool,
    argv: ?*[*c]const u8,
) bool;
extern fn arcan_lua_tick(ctx: *arcan_luactx, nticks: usize, tick_count: usize) void;

// Pure Zig replacements for former C helpers (arcan_conductor_helpers.c)
extern fn arcan_video_getobject(id: c_longlong) ?*anyopaque;

fn getOwnerMsc(vid: i64) u64 {
    const vobj = arcan_video_getobject(vid) orelse return 0;
    const owner = Vobj.getOwner(vobj) orelse return 0;
    return RenderTarget.getMsc(owner);
}

// TRACE macros as inline functions

const SRC_FILE: [*c]const u8 = "arcan_conductor.zig";

inline fn TRACE_MARK_ONESHOT(
    comptime sys: [*c]const u8,
    comptime subsys: [*c]const u8,
    tracelevel: u8,
    identifier: u64,
    quant: u32,
    message: [*c]const u8,
    comptime func: [*c]const u8,
    comptime line: u32,
) void {
    if (arcan_trace_enabled)
        arcan_trace_mark(sys, subsys, 0, tracelevel, identifier, quant, message, SRC_FILE, func, line);
}

inline fn TRACE_MARK_ENTER(
    comptime sys: [*c]const u8,
    comptime subsys: [*c]const u8,
    tracelevel: u8,
    identifier: u64,
    quant: u32,
    message: [*c]const u8,
    comptime func: [*c]const u8,
    comptime line: u32,
) void {
    if (arcan_trace_enabled)
        arcan_trace_mark(sys, subsys, 1, tracelevel, identifier, quant, message, SRC_FILE, func, line);
}

inline fn TRACE_MARK_EXIT(
    comptime sys: [*c]const u8,
    comptime subsys: [*c]const u8,
    tracelevel: u8,
    identifier: u64,
    quant: u32,
    message: [*c]const u8,
    comptime func: [*c]const u8,
    comptime line: u32,
) void {
    if (arcan_trace_enabled)
        arcan_trace_mark(sys, subsys, 2, tracelevel, identifier, quant, message, SRC_FILE, func, line);
}

// Atomic helpers for volatile watchdog pointer

fn watchdogPtr(ping: *volatile u64) *u64 {
    return @constCast(@volatileCast(@as(*const volatile u64, ping)));
}

fn atomicStoreWatchdog(ping: *volatile u64, val: u64) void {
    @atomicStore(u64, watchdogPtr(ping), val, .seq_cst);
}

fn atomicLoadWatchdog(ping: *volatile u64) u64 {
    return @atomicLoad(u64, watchdogPtr(ping), .seq_cst);
}

// Global state

// defined in platform.h, used in psep open, shared memory
// In C: `_Atomic uint64_t* volatile arcan_watchdog_ping`
// We model this as a pointer to a u64 that we access atomically.
export var arcan_watchdog_ping: ?*volatile u64 = null;

var gpu_lock_bitmap: usize = 0;
var reset_counter: c_int = 0;

// Memory allocation enums (from arcan_mem.h)
const ARCAN_MEM_SHARED: c_int = 6; // from enum arcan_memtypes
const ARCAN_MEM_VSTRUCT: c_int = 2;
const ARCAN_MEM_BZERO: c_int = 1; // from enum arcan_memhint
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

extern var system_page_size: c_int;

// Conductor state

const ConductorState = struct {
    tick_count: u64,
    set_deadline: i64,
    render_cost: f64,
    transfer_cost: f64,
    timestep: u8,
    in_frame: bool,
};

var conductor: ConductorState = .{
    .tick_count = 0,
    .set_deadline = 0,
    .render_cost = 4.0,
    .transfer_cost = 1.0,
    .timestep = 2,
    .in_frame = false,
};

// Synch options

const SYNCH_VSYNCH: c_int = 0;
const SYNCH_IMMEDIATE: c_int = 1;
const SYNCH_PROCESSING: c_int = 2;
const SYNCH_POWERSAVE: c_int = 3;
const SYNCH_ADAPTIVE: c_int = 4;
const SYNCH_TIGHT: c_int = 5;

const synchopts_strings = [_][*c]const u8{
    "vsynch",     "release clients on vsynch",
    "immediate",  "release clients as soon as buffers are synched",
    "processing", "synch to ready displays, 100% CPU",
    "powersave",  "synch to clock tick (~25Hz)",
    "adaptive",   "defer composition",
    "tight",      "defer composition, delay client-wake",
    null,
};

var synchopt: c_int = SYNCH_IMMEDIATE;

// Frameserver tracking

const FrameserverSet = struct {
    ref: ?[*]?*anyopaque,
    count: usize,
    used: usize,
    focus: ?*anyopaque,
};

var frameservers: FrameserverSet = .{
    .ref = null,
    .count = 0,
    .used = 0,
    .focus = null,
};

// Lua context (extern from arcan_main.c)
extern var main_lua_context: *arcan_luactx;

// Static state for process_event
var event_count: usize = 0;

// valid_cycle flag
var valid_cycle: bool = false;

// outcb for conductor_cycle
var outcb: ?*const fn (c_int) callconv(.c) void = null;

// Internal helpers

fn unlock_herd() void {
    const ref = frameservers.ref orelse return;
    for (0..frameservers.count) |i| {
        if (ref[i]) |fsrv| {
            TRACE_MARK_ONESHOT(
                "conductor",
                "synchronization",
                TRACE_SYS_DEFAULT,
                @bitCast(Fsrv.getVid(fsrv)),
                0,
                "unlock-herd",
                "unlock_herd",
                @src().line,
            );
            _ = arcan_frameserver_releaselock(fsrv);
        }
    }
}

fn step_herd(mode: c_int) void {
    const start = arcan_timemillis();

    TRACE_MARK_ENTER(
        "conductor",
        "synchronization",
        TRACE_SYS_DEFAULT,
        @intCast(mode),
        0,
        "step-herd",
        "step_herd",
        @src().line,
    );

    arcan_frameserver_lock_buffers(0);
    arcan_video_pollfeed();
    arcan_frameserver_lock_buffers(mode);
    const stop = arcan_timemillis();

    conductor.transfer_cost =
        0.8 * @as(f64, @floatFromInt(stop - start)) +
        0.2 * conductor.transfer_cost;

    TRACE_MARK_EXIT(
        "conductor",
        "synchronization",
        TRACE_SYS_DEFAULT,
        @intCast(mode),
        @intFromFloat(conductor.transfer_cost),
        "step-herd",
        "step_herd",
        @src().line,
    );
}

fn forward_vblank() void {
    const ref = frameservers.ref orelse return;
    for (0..frameservers.count) |i| {
        const fsrv = ref[i] orelse continue;
        if (Fsrv.getClockVblank(fsrv)) {
            const vid = Fsrv.getVid(fsrv);
            const msc = getOwnerMsc(vid);

            var ev = arcan_event.zeroes();
            ev.setCategory(EVENT_TARGET);
            const tgt = ev.asTgtMut();
            tgt.kind = TARGET_COMMAND_STEPFRAME;
            tgt.ioevs[0].iv = 0;
            tgt.ioevs[1].iv = 2;
            tgt.ioevs[2].uiv = @truncate(msc);
            _ = platform_fsrv_pushevent(fsrv, &ev);
        }
    }
}

fn internal_yield() void {
    arcan_event_poll_sources(arcan_event_defaultctx(), conductor.timestep);
    TRACE_MARK_ONESHOT(
        "conductor",
        "yield",
        TRACE_SYS_DEFAULT,
        0,
        conductor.timestep,
        "step",
        "internal_yield",
        @src().line,
    );
}

fn alloc_frameserver_struct() void {
    if (frameservers.ref != null)
        return;

    frameservers.count = 16;
    const buf_sz = @sizeOf(?*anyopaque) * frameservers.count;
    const raw = arcan_alloc_mem(
        buf_sz,
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return;

    const ptr: [*]?*anyopaque = @ptrCast(@alignCast(raw));
    for (0..frameservers.count) |j| {
        ptr[j] = null;
    }
    frameservers.ref = ptr;
}

fn find_frameserver(fsrv: *anyopaque) isize {
    const ref = frameservers.ref orelse return -1;
    for (0..frameservers.count) |i| {
        if (ref[i] == fsrv)
            return @intCast(i);
    }
    return -1;
}

fn estimate_frame_cost() c_int {
    return @as(c_int, @intFromFloat(conductor.render_cost + conductor.transfer_cost)) + @as(c_int, conductor.timestep);
}

fn preframe_synch(next: c_int, elapsed_u64: u64) bool {
    const elapsed: c_int = @intCast(@min(elapsed_u64, @as(u64, @intCast(std.math.maxInt(c_int)))));

    switch (synchopt) {
        SYNCH_ADAPTIVE => {
            const margin = next - estimate_frame_cost();
            if (elapsed > margin) {
                internal_yield();
                return false;
            }
            var buf: [64]u8 = undefined;
            const msg = std.fmt.bufPrintZ(&buf, "adaptive-deadline", .{}) catch "adaptive-deadline";
            TRACE_MARK_ONESHOT(
                "conductor",
                "synchronization",
                TRACE_SYS_DEFAULT,
                0,
                @bitCast(elapsed - margin),
                msg.ptr,
                "preframe_synch",
                @src().line,
            );
            return true;
        },
        SYNCH_TIGHT => {
            const deadline = (next >> 1) - estimate_frame_cost();
            const margin = next - estimate_frame_cost();
            _ = margin;

            if (elapsed < deadline) {
                internal_yield();
                return false;
            } else if (elapsed < next - estimate_frame_cost()) {
                if (!conductor.in_frame) {
                    conductor.in_frame = true;
                    unlock_herd();
                    internal_yield();
                    return false;
                }
                internal_yield();
                return false;
            }

            TRACE_MARK_ONESHOT(
                "conductor",
                "synchronization",
                TRACE_SYS_DEFAULT,
                0,
                @bitCast(elapsed - (next - estimate_frame_cost())),
                "tight-deadline",
                "preframe_synch",
                @src().line,
            );
            return true;
        },
        SYNCH_VSYNCH, SYNCH_PROCESSING, SYNCH_IMMEDIATE, SYNCH_POWERSAVE => {},
        else => {},
    }
    return true;
}

fn postframe_synch(next: u64) u64 {
    switch (synchopt) {
        SYNCH_VSYNCH, SYNCH_ADAPTIVE, SYNCH_POWERSAVE => {
            unlock_herd();
        },
        SYNCH_PROCESSING, SYNCH_IMMEDIATE => {},
        else => {},
    }

    // forward vblank event to frameservers that requested it
    forward_vblank();

    conductor.in_frame = false;
    return next;
}

fn process_event(ev: *arcan_event, drain: c_int) callconv(.c) bool {
    _ = drain;
    event_count += 1;
    _ = arcan_lua_pushevent(main_lua_context, ev);
    return true;
}

fn overflow_drain(ev: *arcan_event, drain: c_int) callconv(.c) bool {
    _ = drain;
    if (arcan_lua_pushevent(main_lua_context, ev)) {
        event_count += 1;
        return true;
    }
    return false;
}

fn trigger_video_synch(frag: f32) c_int {
    conductor.set_deadline = -1;

    TRACE_MARK_ENTER(
        "conductor",
        "platform-frame",
        TRACE_SYS_DEFAULT,
        conductor.tick_count,
        @intFromFloat(frag),
        "",
        "trigger_video_synch",
        @src().line,
    );

    _ = arcan_lua_callvoidfun(
        main_lua_context,
        "preframe_pulse",
        EP_TRIGGER_PREFRAME,
        false,
        null,
    );
    platform_video_synch(conductor.tick_count, frag, null, null);
    _ = arcan_lua_callvoidfun(
        main_lua_context,
        "postframe_pulse",
        EP_TRIGGER_POSTFRAME,
        false,
        null,
    );

    TRACE_MARK_EXIT(
        "conductor",
        "platform-frame",
        TRACE_SYS_DEFAULT,
        conductor.tick_count,
        @intFromFloat(frag),
        "",
        "trigger_video_synch",
        @src().line,
    );

    arcan_bench_register_frame();
    const stats = arcan_bench_data();

    // exponential moving average
    conductor.render_cost =
        0.8 * @as(f64, @floatFromInt(stats.framecost[stats.costofs])) +
        0.2 * conductor.render_cost;

    TRACE_MARK_ONESHOT(
        "conductor",
        "frame-over",
        TRACE_SYS_DEFAULT,
        0,
        @bitCast(@as(u32, @truncate(@as(u64, @bitCast(conductor.set_deadline))))),
        "",
        "trigger_video_synch",
        @src().line,
    );

    valid_cycle = true;
    // if the platform wants us to wait, it'll provide a new deadline at synch
    return if (conductor.set_deadline > 0) @intCast(conductor.set_deadline) else 0;
}

fn conductor_cycle(nticks_arg: c_int) callconv(.c) void {
    var nticks = nticks_arg;
    conductor.tick_count += @intCast(nticks);

    var njobs: c_uint = 0;
    _ = arcan_video_tick(@intCast(nticks), &njobs);
    arcan_audio_tick(@intCast(nticks));

    if (arcan_watchdog_ping) |ping| {
        atomicStoreWatchdog(ping, @intCast(arcan_timemillis()));
    }

    arcan_lua_tick(main_lua_context, @intCast(nticks), @intCast(conductor.tick_count));
    if (outcb) |cb| cb(nticks);

    while (nticks > 0) : (nticks -= 1) {
        arcan_mem_tick();
    }
}

// Exported functions

export fn arcan_conductor_enable_watchdog() void {
    const raw = arcan_alloc_mem(
        @intCast(system_page_size),
        ARCAN_MEM_SHARED,
        ARCAN_MEM_BZERO,
        ARCAN_MEMALIGN_NATURAL,
    );
    if (raw) |ptr| {
        const p: *volatile u64 = @ptrCast(@alignCast(ptr));
        arcan_watchdog_ping = p;
        atomicStoreWatchdog(p, @intCast(arcan_timemillis()));
    }
}

export fn arcan_conductor_toggle_watchdog() void {
    if (arcan_watchdog_ping) |ping| {
        const current = atomicLoadWatchdog(ping);
        if (current != 0) {
            atomicStoreWatchdog(ping, 0);
        } else {
            atomicStoreWatchdog(ping, @intCast(arcan_timemillis()));
        }
    }
}

export fn arcan_conductor_lock_gpu(
    gpu_id: usize,
    fence: c_int,
    lockh: ?*anyopaque,
) void {
    _ = fence;
    _ = lockh;
    gpu_lock_bitmap |= @as(usize, 1) << @intCast(gpu_id);
    TRACE_MARK_ENTER(
        "conductor",
        "gpu",
        TRACE_SYS_DEFAULT,
        gpu_id,
        0,
        "",
        "arcan_conductor_lock_gpu",
        @src().line,
    );
}

export fn arcan_conductor_release_gpu(gpu_id: usize) void {
    gpu_lock_bitmap &= ~(@as(usize, 1) << @intCast(gpu_id));
    TRACE_MARK_EXIT(
        "conductor",
        "gpu",
        TRACE_SYS_DEFAULT,
        gpu_id,
        0,
        "",
        "arcan_conductor_release_gpu",
        @src().line,
    );
}

export fn arcan_conductor_gpus_locked() usize {
    return gpu_lock_bitmap;
}

export fn arcan_conductor_register_display(
    gpu_id: usize,
    disp_id: usize,
    method: c_int,
    rate: f32,
    obj: i64,
) void {
    _ = method;
    _ = rate;
    var buf: [48]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "register:{d}:{d}:{d}", .{ gpu_id, disp_id, @as(usize, @intCast(obj)) }) catch "register:?";
    TRACE_MARK_ONESHOT(
        "conductor",
        "display",
        TRACE_SYS_DEFAULT,
        gpu_id,
        0,
        msg.ptr,
        "arcan_conductor_register_display",
        @src().line,
    );
}

export fn arcan_conductor_release_display(gpu_id: usize, disp_id: usize) void {
    var buf: [24]u8 = undefined;
    const msg = std.fmt.bufPrintZ(&buf, "release:{d}:{d}", .{ gpu_id, disp_id }) catch "release:?";
    TRACE_MARK_ONESHOT(
        "conductor",
        "display",
        TRACE_SYS_DEFAULT,
        gpu_id,
        0,
        msg.ptr,
        "arcan_conductor_release_display",
        @src().line,
    );
}

export fn arcan_conductor_register_frameserver(fsrv: *anyopaque) void {
    alloc_frameserver_struct();
    Fsrv.setDescRecoveryTick(fsrv, @intCast(reset_counter));

    // safeguard: already known?
    const src_i = find_frameserver(fsrv);
    if (src_i != -1) {
        TRACE_MARK_ONESHOT(
            "conductor",
            "frameserver",
            TRACE_SYS_ERROR,
            @bitCast(Fsrv.getVid(fsrv)),
            0,
            "add on known",
            "arcan_conductor_register_frameserver",
            @src().line,
        );
        return;
    }

    const ref = frameservers.ref orelse return;
    var dst_i: usize = 0;

    // check for a gap
    if (frameservers.used < frameservers.count) {
        for (0..frameservers.count) |i| {
            if (ref[i] == null) {
                dst_i = i;
                break;
            }
        }
    } else {
        // grow and add
        const new_count = frameservers.count * 2;
        const nbuf_sz = new_count * @sizeOf(?*anyopaque);
        const raw = arcan_alloc_mem(
            nbuf_sz,
            ARCAN_MEM_VSTRUCT,
            ARCAN_MEM_BZERO,
            ARCAN_MEMALIGN_NATURAL,
        ) orelse return;

        const newref: [*]?*anyopaque = @ptrCast(@alignCast(raw));
        const old_bytes: [*]const u8 = @ptrCast(ref);
        const new_bytes: [*]u8 = @ptrCast(newref);
        const copy_sz = frameservers.count * @sizeOf(?*anyopaque);
        @memcpy(new_bytes[0..copy_sz], old_bytes[0..copy_sz]);
        // zero the new slots
        @memset(new_bytes[copy_sz..nbuf_sz], 0);

        arcan_mem_free(@ptrCast(ref));
        frameservers.ref = newref;
        dst_i = frameservers.count;
        frameservers.count = new_count;
    }

    frameservers.used += 1;
    (frameservers.ref orelse return)[dst_i] = fsrv;
    TRACE_MARK_ONESHOT(
        "conductor",
        "frameserver",
        TRACE_SYS_DEFAULT,
        @bitCast(Fsrv.getVid(fsrv)),
        0,
        "register",
        "arcan_conductor_register_frameserver",
        @src().line,
    );
}

export fn arcan_conductor_yield(disps: ?*anyopaque, pset_count: usize) c_int {
    _ = disps;
    _ = pset_count;

    _ = arcan_audio_refresh();

    // by returning -1 here we tell the platform to not even wait for synch
    if (synchopt == SYNCH_PROCESSING) {
        TRACE_MARK_ONESHOT(
            "conductor",
            "display",
            TRACE_SYS_FAST,
            0,
            @truncate(frameservers.used),
            "synch-processing",
            "arcan_conductor_yield",
            @src().line,
        );
        return -1;
    }

    const ref = frameservers.ref orelse return conductor.timestep;
    var j = frameservers.used;
    for (0..frameservers.count) |i| {
        if (j == 0) break;
        if (ref[i]) |fsrv| {
            _ = arcan_vint_pollfeed(Fsrv.getVid(fsrv), false);
            j -= 1;
        }
    }

    return conductor.timestep;
}

export fn arcan_conductor_synchopts() [*c]const [*c]const u8 {
    return @ptrCast(&synchopts_strings);
}

export fn arcan_conductor_setsynch(arg: [*c]const u8) void {
    var ind: usize = 0;

    while (ind < synchopts_strings.len and synchopts_strings[ind] != null) {
        const opt = synchopts_strings[ind];
        if (opt != null and arg != null) {
            const opt_slice = std.mem.sliceTo(opt.?, 0);
            const arg_slice = std.mem.sliceTo(arg, 0);
            if (std.mem.eql(u8, opt_slice, arg_slice)) {
                synchopt = @intCast(if (ind > 0) ind / 2 else ind);
                break;
            }
        }
        ind += 2;
    }

    TRACE_MARK_ONESHOT(
        "conductor",
        "synchronization",
        TRACE_SYS_DEFAULT,
        0,
        0,
        arg,
        "arcan_conductor_setsynch",
        @src().line,
    );

    switch (synchopt) {
        SYNCH_VSYNCH, SYNCH_ADAPTIVE, SYNCH_POWERSAVE => {
            arcan_frameserver_lock_buffers(2);
        },
        SYNCH_TIGHT => {
            arcan_frameserver_lock_buffers(2);
        },
        SYNCH_IMMEDIATE, SYNCH_PROCESSING => {
            arcan_frameserver_lock_buffers(0);
            unlock_herd();
        },
        else => {},
    }
}

export fn arcan_conductor_focus(fsrv_opt: ?*anyopaque) void {
    // Focus-based strategies might need special flag modification on unset.
    // Currently no strategies use focus-based unset handling.

    const fsrv = fsrv_opt orelse return;
    const dst_i = find_frameserver(fsrv);
    if (dst_i == -1)
        return;

    if (frameservers.focus) |old_focus| {
        Fsrv.setFlagsLocked(old_focus, false);
    }

    TRACE_MARK_ONESHOT(
        "conductor",
        "synchronization",
        TRACE_SYS_DEFAULT,
        @bitCast(Fsrv.getVid(fsrv)),
        0,
        "synch-focus",
        "arcan_conductor_focus",
        @src().line,
    );

    // set new focus
    frameservers.focus = fsrv;

    // Focus-based strategies might need special flag modification on set.
    // Currently no strategies use focus-based set handling.
}

export fn arcan_conductor_frameserver_known(fsrv: *anyopaque) bool {
    return find_frameserver(fsrv) != -1;
}

export fn arcan_conductor_deregister_frameserver(fsrv: *anyopaque) void {
    const dst_i = find_frameserver(fsrv);
    if (frameservers.used == 0 or dst_i == -1) {
        arcan_warning("deregister_frameserver() on unknown fsrv @ %zd\n", dst_i);
        return;
    }

    const ref = frameservers.ref orelse return;
    ref[@intCast(dst_i)] = null;
    frameservers.used -= 1;

    if (frameservers.focus == fsrv) {
        TRACE_MARK_ONESHOT(
            "conductor",
            "frameserver",
            TRACE_SYS_DEFAULT,
            @bitCast(Fsrv.getVid(fsrv)),
            0,
            "lost-focus",
            "arcan_conductor_deregister_frameserver",
            @src().line,
        );
        frameservers.focus = null;
    }

    TRACE_MARK_ONESHOT(
        "conductor",
        "frameserver",
        TRACE_SYS_DEFAULT,
        @bitCast(Fsrv.getVid(fsrv)),
        0,
        "deregister",
        "arcan_conductor_deregister_frameserver",
        @src().line,
    );
}

export fn arcan_conductor_valid_cycle() bool {
    return valid_cycle;
}

export fn arcan_conductor_reset_count(step: bool) c_int {
    if (step)
        reset_counter += 1;
    return reset_counter;
}

export fn arcan_conductor_run(tick: *const fn (c_int) callconv(.c) void) c_int {
    const evctx = arcan_event_defaultctx();
    outcb = tick;
    var exit_code: c_int = EXIT_FAILURE;
    alloc_frameserver_struct();
    var last_tickcount: u64 = 0;
    var last_synch: u64 = @intCast(arcan_timemillis());
    var next_synch: u64 = 0;
    valid_cycle = false;

    arcan_event_setdrain(evctx, overflow_drain);

    while (true) {
        // Check accelerated graphics status
        if (!agp_status_ok(null)) {
            TRACE_MARK_ONESHOT(
                "conductor",
                "platform",
                TRACE_SYS_ERROR,
                0,
                0,
                "accelerated graphics failed",
                "arcan_conductor_run",
                @src().line,
            );
            platform_video_reset(-1, false);
        }

        arcan_video_pollfeed();
        _ = arcan_audio_refresh();

        // let the event-layer polling set interleave up to the next deadline.
        // ARCAN_LWA path: if deadline > 0, sleep up to remaining time
        if (conductor.set_deadline > 0) {
            const step_val = conductor.set_deadline - @as(i64, @intCast(arcan_timemillis()));
            if (step_val > 0)
                arcan_event_poll_sources(evctx, @intCast(step_val));
        } else {
            arcan_event_poll_sources(evctx, 0);
        }

        last_tickcount = conductor.tick_count;

        TRACE_MARK_ENTER(
            "conductor",
            "event",
            TRACE_SYS_DEFAULT,
            0,
            @truncate(last_tickcount),
            "process",
            "arcan_conductor_run",
            @src().line,
        );

        const frag = arcan_event_process(evctx, conductor_cycle);
        const now: u64 = @intCast(arcan_timemillis());
        const elapsed: u64 = now -| last_synch;

        TRACE_MARK_EXIT(
            "conductor",
            "event",
            TRACE_SYS_DEFAULT,
            0,
            @truncate(last_tickcount),
            "process",
            "arcan_conductor_run",
            @src().line,
        );

        // This fails when the event recipient has queued a SHUTDOWN event
        if (!arcan_event_feed(evctx, process_event, &exit_code)) {
            break;
        }
        // Signal end of event batch (equivalent to C's process_event(NULL, 0))
        if (event_count != 0) {
            event_count = 0;
            _ = arcan_lua_pushevent(main_lua_context, null);
        }

        // Powersave: yield at ~25fps
        if (synchopt == SYNCH_POWERSAVE and last_tickcount == conductor.tick_count) {
            internal_yield();
            continue;
        }

        // Other processing modes
        if (next_synch == 0 or preframe_synch(@intCast(next_synch -| last_synch), elapsed)) {
            // Tight mode: if we missed the unlock window, do it now
            if (synchopt == SYNCH_TIGHT and !conductor.in_frame) {
                conductor.in_frame = true;
                unlock_herd();
            }

            next_synch = postframe_synch(@intCast(trigger_video_synch(frag)));
            last_synch = @intCast(arcan_timemillis());
        }
    }

    outcb = null;
    return exit_code;
}

export fn arcan_conductor_fakesynch(left_arg: u8) void {
    var left: c_int = @intCast(left_arg);
    TRACE_MARK_ENTER(
        "conductor",
        "synchronization",
        TRACE_SYS_SLOW,
        0,
        left_arg,
        "fake synch",
        "arcan_conductor_fakesynch",
        @src().line,
    );

    // Some platforms have a high cost for sleep/yield operations
    const timing = platform_hardware_clockcfg();
    const sleep_cost_val: usize = if (!timing.tickless) timing.cost_us / 1000 else 0;
    const sleep_cost: c_int = @intCast(sleep_cost_val);

    while (true) {
        const step = arcan_conductor_yield(null, 0);
        if (step == -1 or left <= step + sleep_cost)
            break;
        arcan_event_poll_sources(arcan_event_defaultctx(), step);
        left -= step;
    }

    TRACE_MARK_EXIT(
        "conductor",
        "synchronization",
        TRACE_SYS_SLOW,
        0,
        @intCast(left),
        "fake synch",
        "arcan_conductor_fakesynch",
        @src().line,
    );
}

export fn arcan_conductor_deadline(deadline: u8) void {
    if (conductor.set_deadline == -1 or @as(i64, deadline) < conductor.set_deadline) {
        conductor.set_deadline = @as(i64, @intCast(arcan_timemillis())) + @as(i64, deadline);
        TRACE_MARK_ONESHOT(
            "conductor",
            "synchronization",
            TRACE_SYS_DEFAULT,
            0,
            deadline,
            "deadline",
            "arcan_conductor_deadline",
            @src().line,
        );
    }
}
