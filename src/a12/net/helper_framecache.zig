// Zig port of a12/net/a12_helper_framecache.c — frame cache for multicasting
// video frames to multiple listener clients.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const builtin = @import("builtin");

const shmif = @import("shmif_types");

/// Dispatch struct stitching together every C-namespace symbol the file
/// uses, routed to the right replacement module.
const c = struct {
    pub const tui_context = shmif.struct_tui_context;
    pub const tui_cbcfg = shmif.struct_tui_cbcfg;
    pub const shmifsrv_vbuffer = shmif.struct_shmifsrv_vbuffer;
    pub const arcan_tui_setup = shmif.arcan_tui_setup;
    pub const arcan_tui_tpack = shmif.arcan_tui_tpack;
    pub const arcan_tui_tunpack = shmif.arcan_tui_tunpack;
    pub const arcan_tui_dimensions = shmif.arcan_tui_dimensions;
};

// Build option
// Set -Dframecache_no_tui=true to compile out all TUI code paths, matching the
// C preprocessor define FRAMECACHE_NO_TUI.
const no_tui: bool = false;

// Constants
// Mirror the enum values from arcan_shmif_event.h so we can reference them
// without coercing c_int enumerator types.
const SEGID_MEDIA: c_int = 4;
const SEGID_TUI: c_int = 24;

// FRAME_RAW_SHMIFSRV_VBUFFER is defined in a12_helper.h as the first enumerator
// of the anonymous enum (value 0).
const FRAME_RAW_SHMIFSRV_VBUFFER: c_int = 0;

// TriggerFn type
// Matches: void (*trigger)(uintptr_t, uint8_t* buf, size_t buf_sz, int type)
pub const TriggerFn = *const fn (uintptr_t: usize, buf: [*]u8, buf_sz: usize, frame_type: c_int) callconv(.c) void;

// Listener
// Tracks a single subscriber to the frame cache.  The key field doubles as the
// hashmap key; its address is stable because the struct is heap-allocated.
const Listener = struct {
    key: usize,
    raw: bool,
    wait_keyframe: bool,
    trigger: TriggerFn,
    level: isize,
};

// Channel slot
const Channel = if (no_tui)
    struct {
        w: usize = 0,
        h: usize = 0,
    }
else
    struct {
        w: usize = 0,
        h: usize = 0,
        tui: ?*c.tui_context = null,
    };

// FrameCache
const ClientMap = std.AutoHashMap(usize, *Listener);

pub const FrameCache = struct {
    clients: ClientMap,
    channels: [256]Channel,
};

// Public API

/// Allocate and initialise a new FrameCache.
/// The caller owns the returned pointer; free with std.heap.c_allocator.destroy.
pub export fn a12helper_alloc_cache(capacity: u32) ?*FrameCache {
    const ret = std.heap.c_allocator.create(FrameCache) catch return null;
    ret.* = .{
        .clients = ClientMap.init(std.heap.c_allocator),
        .channels = [_]Channel{.{}} ** 256,
    };
    ret.clients.ensureTotalCapacity(capacity) catch {};
    return ret;
}

/// Feed a raw shmifsrv_vbuffer into the cache and forward to all matching
/// listeners.  If the frame is a tpack (TUI) frame and TUI support is compiled
/// in, the TUI context for that channel is updated so late-joining clients can
/// receive a synthesised I-frame.
pub export fn a12helper_vbuffer_append_raw(
    C: *FrameCache,
    vb: *c.shmifsrv_vbuffer,
    chid: u8,
) void {
    if (vb.flags.tpack) {
        if (comptime !no_tui) {
            if (C.channels[chid].tui == null) {
                var cb = std.mem.zeroes(c.tui_cbcfg);
                C.channels[chid].tui = c.arcan_tui_setup(null, null, &cb, @sizeOf(c.tui_cbcfg));
            }
            C.channels[chid].w = vb.w;
            C.channels[chid].h = vb.h;
            const cap: usize = vb.stride * vb.h;
            _ = c.arcan_tui_tunpack(
                C.channels[chid].tui,
                vb.unnamed_0.buffer_bytes,
                cap,
                0, 0, 0, 0,
            );
        } else {
            // TUI disabled at build time — skip tpack frames entirely.
            return;
        }
    }

    var it = C.clients.valueIterator();
    while (it.next()) |cl_ptr| {
        const cl = cl_ptr.*;
        // tpack frames are treated as "raw"; non-raw clients skip non-tpack frames.
        if (!cl.raw and !vb.flags.tpack) continue;
        cl.trigger(
            cl.key,
            @ptrCast(vb),
            @sizeOf(c.shmifsrv_vbuffer),
            FRAME_RAW_SHMIFSRV_VBUFFER,
        );
    }
}

/// Feed a pre-encoded video buffer into the cache and forward to all non-raw
/// listeners, respecting keyframe gating.
pub export fn a12helper_vbuffer_append_encoded(
    C: *FrameCache,
    buf: [*]u8,
    buf_sz: usize,
    chid: u8,
    keyed: bool,
) void {
    _ = chid; // channel unused in encoding path (mirrors upstream)
    var it = C.clients.valueIterator();
    while (it.next()) |cl_ptr| {
        const cl = cl_ptr.*;
        // Raw clients receive frames via the append_raw path, not here.
        if (cl.raw) continue;
        // Cannot join mid-GOP without a keyframe.
        if (!keyed and cl.wait_keyframe) continue;
        cl.trigger(cl.key, buf, buf_sz, @intFromBool(keyed));
    }
}

/// Return SEGID_TUI if the channel has an active TUI context, SEGID_MEDIA
/// otherwise.
pub export fn a12helper_vbuffer_type(C: *FrameCache, chid: u8) c_int {
    if (comptime !no_tui) {
        return if (C.channels[chid].tui != null) SEGID_TUI else SEGID_MEDIA;
    } else {
        return SEGID_MEDIA;
    }
}

/// Stub — size hints are tracked by the channel slots but no action is taken.
pub export fn a12helper_vbuffer_size_hints(
    C: *FrameCache,
    ref: usize,
    w: usize,
    h: usize,
) void {
    _ = C;
    _ = ref;
    _ = w;
    _ = h;
}

/// Register a new listener.  If a listener for `ref` already exists, returns
/// immediately without replacing it.  If TUI is active on channel 0, an
/// I-frame is synthesised and delivered immediately to the new listener.
pub export fn a12helper_vbuffer_add_listener(
    C: *FrameCache,
    ref: usize,
    raw: bool,
    trigger: TriggerFn,
) void {
    // Bail if the listener is already registered.
    if (C.clients.contains(ref)) return;

    const cl = std.heap.c_allocator.create(Listener) catch return;
    cl.* = .{
        .key = ref,
        .raw = raw,
        .wait_keyframe = !raw,
        .trigger = trigger,
        .level = 5,
    };

    C.clients.put(ref, cl) catch {
        std.heap.c_allocator.destroy(cl);
        return;
    };

    // Deliver a synthesised TUI I-frame to the new listener if one exists.
    if (comptime !no_tui) {
        if (C.channels[0].tui != null) {
            var outb: [*c]u8 = null;
            var outb_sz: usize = 0;
            if (c.arcan_tui_tpack(C.channels[0].tui, &outb, &outb_sz)) {
                var vb = std.mem.zeroes(c.shmifsrv_vbuffer);
                vb.unnamed_0.buffer_bytes = outb;
                vb.flags.tpack = true;
                vb.w = C.channels[0].w;
                vb.h = C.channels[0].h;
                trigger(
                    ref,
                    @ptrCast(&vb),
                    @sizeOf(c.shmifsrv_vbuffer),
                    FRAME_RAW_SHMIFSRV_VBUFFER,
                );
            }
        }
    }
}

/// Query the TUI dimensions (rows, cols) for the given channel.
/// Returns true and writes dimensions on success; false if no TUI context.
pub export fn a12helper_tpack_dimensions(
    C: *FrameCache,
    chid: u8,
    rows: *usize,
    cols: *usize,
) bool {
    if (comptime !no_tui) {
        if (C.channels[chid].tui != null) {
            c.arcan_tui_dimensions(C.channels[chid].tui, rows, cols);
            return true;
        }
    }
    return false;
}

/// Stub — quality stepping is a no-op in this implementation.
pub export fn a12helper_vbuffer_step_quality(
    C: *FrameCache,
    ref: usize,
    steps: isize,
) void {
    _ = C;
    _ = ref;
    _ = steps;
}

/// Remove a listener from the cache and free its storage.
pub export fn a12helper_vbuffer_drop_listener(C: *FrameCache, ref: usize) void {
    const kv = C.clients.fetchRemove(ref) orelse return;
    std.heap.c_allocator.destroy(kv.value);
}
