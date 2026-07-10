// Pure Zig port of engine/arcan_vr_helpers.c — VR bridge support.
// Spawns a VR frameserver, tracks limb updates, syncs position/orientation
// to video objects.
//
// Uses byte-offset accessors from shmif_offsets.zig and engine_offsets.zig
// for opaque struct field access. Fully self-contained — no C helpers needed.

const std = @import("std");

// Offset accessor modules
const Fsrv = @import("shmif_offsets").Fsrv;
const Page = @import("shmif_offsets").Page;
const VrLimb = @import("engine_offsets").VrLimb;
const ShmifVr = @import("engine_offsets").ShmifVr;
const Vobj = @import("engine_offsets").Vobj;
const RenderTarget = @import("engine_offsets").RenderTarget;
const VideoDisplay = @import("engine_offsets").VideoDisplay;
const SurfaceProperties = @import("engine_offsets").SurfaceProperties;
const JmpBuf = @import("engine_offsets").JmpBuf;

// Type aliases
const arcan_errc = c_int;
const arcan_vobj_id = i64;
const av_pixel = u32;

// Opaque engine types (accessed only via offset accessors or extern fns)
const arcan_frameserver = anyopaque;
const arcan_vobject = anyopaque;
const arcan_evctx = anyopaque;
const arcan_dbh = anyopaque;

// Error codes (from arcan_general.h enum arcan_error)
const ARCAN_OK: arcan_errc = 0;
const ARCAN_ERRC_NOT_IMPLEMENTED: arcan_errc = -1;
const ARCAN_ERRC_UNACCEPTED_STATE: arcan_errc = -4;
const ARCAN_ERRC_OUT_OF_SPACE: arcan_errc = -6;
const ARCAN_ERRC_NO_SUCH_OBJECT: arcan_errc = -7;

// FFUNC types (matching arcan_ffunc_lut.h)
const arcan_ffunc_rv = enum(c_int) {
    FRV_NOFRAME = 0,
    FRV_GOTFRAME = 1,
    FRV_COPIED = 2,
    FRV_NOUPLOAD = 64,
};

const arcan_ffunc_cmd = enum(c_int) {
    FFUNC_POLL = 0,
    FFUNC_RENDER = 1,
    FFUNC_TICK = 2,
    FFUNC_DESTROY = 3,
    FFUNC_READBACK = 4,
    FFUNC_READBACK_HANDLE = 5,
    FFUNC_ADOPT = 6,
};

const vfunc_state = extern struct {
    tag: c_int,
    ptr: ?*anyopaque,
};

// Memory allocation constants (from arcan_mem.h)
const ARCAN_MEM_VSTRUCT: c_int = 2;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// Limb tracking (private to this file)
const limb_ent = struct {
    map: arcan_vobj_id = 0,
    position: bool = false,
    orientation: bool = false,
    ts: u32 = 0,
};

// Constants from avatar_limbs enum (arcan_shmif_sub.h)
const LIMB_LIM: usize = 49;
const NECK: usize = 2;

// Event layout constants
const EVENT_TARGET: u8 = 16;
const EVENT_FSRV: u8 = 32;
const CATEGORY_OFFSET: usize = 120;
const FSRV_KIND_OFFSET: usize = 0;
const FSRV_LIMB_OFFSET: usize = 8;
const FSRV_VIDEO_OFFSET: usize = 104;
const FSRV_OTAG_OFFSET: usize = 112;
const TGT_KIND_OFFSET: usize = 0;

// Constant values (matching C enums)
const SEGID_SENSOR: c_int = 14;
const FFUNC_VR: c_int = 10;
const ARCAN_TAG_VR: c_int = 3;
const ARCAN_TAG_FRAMESERV: c_int = 1;
const SHMIF_META_VR: c_int = 4;
const TARGET_COMMAND_ACTIVATE: c_int = 2;
const TARGET_COMMAND_RESET: c_int = 3;
const EVENT_FSRV_ADDVRLIMB: c_int = 14;
const EVENT_FSRV_LOSTVRLIMB: c_int = 15;

// VR context (private to this file)
const arcan_vr_ctx = struct {
    ctx: ?*arcan_evctx = null,
    connection: ?*arcan_frameserver = null,
    map: u64 = 0,
    limb_map: [LIMB_LIM + 1]limb_ent = [_]limb_ent{.{}} ** (LIMB_LIM + 1),
};

// arcan_strarr (matches C struct layout)
const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    data: [*c][*c]u8,
};

// frameserver_envp byte-offset accessors (matches launch.zig)
const ENVP = struct {
    const USE_BUILTIN: usize = 0;
    const METAMASK: usize = 48;
    const ARGS_EXTERNAL_FNAME: usize = 56;
    const ARGS_EXTERNAL_ARGV: usize = 64;
    const ARGS_EXTERNAL_ENVV: usize = 72;
    const ARGS_EXTERNAL_RESOURCE: usize = 80;
    const SIZE: usize = 88;

    fn ptr(base: [*]u8, comptime offset: usize, comptime T: type) *T {
        return @ptrCast(@alignCast(base + offset));
    }
};

// Memory management externs
extern fn arcan_mem_growarr(arr: *arcan_strarr) void;
extern fn arcan_mem_freearr(arr: *arcan_strarr) void;
extern fn platform_launch_fork(args: *anyopaque, tag: usize) ?*arcan_frameserver;

// vr_launch_bridge: construct frameserver_envp and launch VR bridge
fn vr_launch_bridge(kv: [*c]const u8, bridge_arg: [*c]const u8, ext_vr_debug: [*c]const u8, tag: usize) ?*arcan_frameserver {
    var arr_argv = std.mem.zeroes(arcan_strarr);
    var arr_env = std.mem.zeroes(arcan_strarr);
    arcan_mem_growarr(&arr_argv);
    arr_argv.data[0] = strdup(kv);
    arr_argv.count = 1;

    if (@intFromPtr(ext_vr_debug) != 0) {
        arcan_mem_growarr(&arr_env);
        arr_env.data[0] = strdup("ARCAN_VR_DEBUGATTACH=1");
        arr_env.count = 1;
    }

    var args: [ENVP.SIZE]u8 align(8) = std.mem.zeroes([ENVP.SIZE]u8);
    ENVP.ptr(&args, ENVP.USE_BUILTIN, bool).* = false;
    ENVP.ptr(&args, ENVP.METAMASK, c_uint).* = @bitCast(@as(c_int, SHMIF_META_VR));
    ENVP.ptr(&args, ENVP.ARGS_EXTERNAL_FNAME, [*c]const u8).* = kv;
    ENVP.ptr(&args, ENVP.ARGS_EXTERNAL_ARGV, *arcan_strarr).* = &arr_argv;
    ENVP.ptr(&args, ENVP.ARGS_EXTERNAL_ENVV, *arcan_strarr).* = &arr_env;
    const resource_dup = strdup(if (@intFromPtr(bridge_arg) != 0) bridge_arg else "");
    ENVP.ptr(&args, ENVP.ARGS_EXTERNAL_RESOURCE, [*c]u8).* = resource_dup;

    const mvctx = platform_launch_fork(@ptrCast(&args), tag);
    arcan_mem_freearr(&arr_argv);
    arcan_mem_freearr(&arr_env);
    free(@ptrCast(resource_dup));

    return mvctx;
}

// Engine extern functions
extern fn arcan_video_getobject(id: arcan_vobj_id) ?*arcan_vobject;
extern fn arcan_event_enqueue(ctx: ?*arcan_evctx, ev: *const anyopaque) c_int;
extern fn arcan_event_defaultctx() ?*arcan_evctx;
extern fn arcan_frameserver_free(fsrv: ?*arcan_frameserver) arcan_errc;
extern fn arcan_frameserver_tick_control(fsrv: *arcan_frameserver, tick: bool, ff: c_int) bool;
extern fn arcan_video_alterfeed(vid: arcan_vobj_id, ffunc: u8, state: vfunc_state) arcan_errc;
extern fn arcan_3d_bindvr(id: arcan_vobj_id, vrref: ?*arcan_vr_ctx) arcan_errc;
extern fn arcan_db_get_shared(appl: *[*c]const u8) ?*arcan_dbh;
extern fn arcan_db_appl_val(dbh: ?*arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;
extern fn arcan_isfile(path: [*c]const u8) bool;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn platform_fsrv_pushevent(fsrv: *arcan_frameserver, ev: *const anyopaque) c_int;
extern fn platform_fsrv_enter(fsrv: *anyopaque, tramp: *anyopaque) void;
extern fn platform_fsrv_leave() void;
extern fn arcan_resolve_vidprop(vobj: *arcan_vobject, lerp: f64, dst: *anyopaque) void;

// arcan_video_display global (for FLAG_DIRTY)
extern var arcan_video_display: anyopaque;

// angle_quat: converts quaternion to euler angles (returns vector by value)
const c_vector = extern struct { x: f32, y: f32, z: f32 };
const c_quat = extern struct { x: f32, y: f32, z: f32, w: f32 };
extern fn angle_quat(q: c_quat) c_vector;

// setjmp
extern fn setjmp(env: *anyopaque) c_int;

// C stdlib
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn free(ptr: ?*anyopaque) void;

// subp_checksum (ported from arcan_shmif_sub.h inline function)
fn subp_checksum(buf: [*]const u8, len: usize) u16 {
    var res: u32 = 0;
    for (0..len) |i| {
        if (res & 1 != 0)
            res |= 0x10000;
        res = ((res >> 1) + buf[i]) & 0xffff;
    }
    return @truncate(res);
}

// FLAG_DIRTY (replicate the C macro)
fn flag_dirty(vobj: *arcan_vobject) void {
    // _int_flag: if vobj->owner, increment owner->transfc
    if (Vobj.getOwner(vobj)) |owner| {
        RenderTarget.incrementTransfc(owner);
    }
    // arcan_video_display.dirty++
    VideoDisplay.incrementDirty(&arcan_video_display);
}

// apply_limb: sync limb orientation/position to vobject
fn apply_limb(limb_buf: [*]const u8, lent: *limb_ent) void {
    const vobj = arcan_video_getobject(lent.map) orelse return;
    flag_dirty(vobj);

    if (lent.orientation) {
        const qx = VrLimb.getOrientationX(limb_buf);
        const qy = VrLimb.getOrientationY(limb_buf);
        const qz = VrLimb.getOrientationZ(limb_buf);
        const qw = VrLimb.getOrientationW(limb_buf);

        // Convert quaternion to euler angles
        const v = angle_quat(.{ .x = qx, .y = qy, .z = qz, .w = qw });

        Vobj.setRotation(vobj, v.x, v.y, v.z, qx, qy, qz, qw);
    }

    if (lent.position) {
        const lx = VrLimb.getPositionX(limb_buf);
        const ly = VrLimb.getPositionY(limb_buf);
        const lz = VrLimb.getPositionZ(limb_buf);

        // Resolve parent position and add
        var dprop: [SurfaceProperties.sizeof_surface_properties]u8 align(8) = undefined;
        arcan_resolve_vidprop(vobj, 0.0, @ptrCast(&dprop));
        const dx = SurfaceProperties.getPositionX(&dprop);
        const dy = SurfaceProperties.getPositionY(&dprop);
        const dz = SurfaceProperties.getPositionZ(&dprop);

        Vobj.setPositionX(vobj, lx + dx);
        Vobj.setPositionY(vobj, ly + dy);
        Vobj.setPositionZ(vobj, lz + dz);
    }
}

// Helper: build a zeroed 128-byte event
fn build_event() [128]u8 {
    return std.mem.zeroes([128]u8);
}

fn set_event_category(ev: *[128]u8, cat: u8) void {
    ev[CATEGORY_OFFSET] = cat;
}

fn set_event_tgt_kind(ev: *[128]u8, kind: c_int) void {
    const p: *align(1) c_int = @ptrCast(&ev[TGT_KIND_OFFSET]);
    p.* = kind;
}

fn set_event_fsrv(ev: *[128]u8, kind: c_int, limb: c_uint, video: i64, otag: isize) void {
    const kind_p: *align(1) c_int = @ptrCast(&ev[FSRV_KIND_OFFSET]);
    kind_p.* = kind;
    const limb_p: *align(1) c_uint = @ptrCast(&ev[FSRV_LIMB_OFFSET]);
    limb_p.* = limb;
    const video_p: *align(1) i64 = @ptrCast(&ev[FSRV_VIDEO_OFFSET]);
    video_p.* = video;
    const otag_p: *align(1) isize = @ptrCast(&ev[FSRV_OTAG_OFFSET]);
    otag_p.* = otag;
}

// Frameserver accessors using Fsrv/Page offsets
fn fsrv_get_vr(fsrv: *arcan_frameserver) ?[*]u8 {
    const vr_ptr = Fsrv.getDescAextVr(fsrv) orelse return null;
    return @ptrCast(vr_ptr);
}

fn fsrv_shm_resized(fsrv: *arcan_frameserver) i8 {
    const shm_ptr = Fsrv.getShmPtr(fsrv) orelse return 0;
    return Page.getResized(shm_ptr);
}

// TRAMP_GUARD helpers (setjmp available from Zig)
fn tramp_enter(fsrv: *arcan_frameserver) bool {
    var tramp: [JmpBuf.sizeof_jmp_buf]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&tramp)) != 0)
        return false;
    platform_fsrv_enter(fsrv, @ptrCast(&tramp));
    return true;
}

fn tramp_set_limb_ignored(fsrv: *arcan_frameserver, vr: [*]u8, ind: usize, val: bool, ok: *bool) void {
    ok.* = true;
    var tramp: [JmpBuf.sizeof_jmp_buf]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&tramp)) != 0) {
        ok.* = false;
        return;
    }
    platform_fsrv_enter(fsrv, @ptrCast(&tramp));
    VrLimb.setIgnored(ShmifVr.getLimbPtr(vr, ind), val);
    platform_fsrv_leave();
}

fn tramp_copy_meta(fsrv: *arcan_frameserver, vr: [*]u8, dst: [*]u8) bool {
    var tramp: [JmpBuf.sizeof_jmp_buf]u8 align(16) = undefined;
    if (setjmp(@ptrCast(&tramp)) != 0)
        return false;
    platform_fsrv_enter(fsrv, @ptrCast(&tramp));
    @memcpy(dst[0..ShmifVr.sizeof_vr_meta], ShmifVr.getMetaPtr(vr)[0..ShmifVr.sizeof_vr_meta]);
    platform_fsrv_leave();
    return true;
}

// arcan_vr_setup_impl
export fn arcan_vr_setup_impl(
    bridge_arg: [*c]const u8,
    evctx: ?*arcan_evctx,
    tag: usize,
) ?*arcan_vr_ctx {
    var appl: [*c]const u8 = undefined;
    const dbh = arcan_db_get_shared(&appl);

    // Look up ext_vr key from database
    var kv: [*c]u8 = arcan_db_appl_val(dbh, appl, "ext_vr");
    if (@intFromPtr(kv) == 0) {
        // Try known default paths
        if (arcan_isfile("/usr/local/bin/arcan_vr")) {
            kv = strdup("/usr/local/bin/arcan_vr");
        } else if (arcan_isfile("/usr/bin/arcan_vr")) {
            kv = strdup("/usr/bin/arcan_vr");
        }
    }
    if (@intFromPtr(kv) == 0) return null;

    // Check for debug setting
    const kvd: [*c]u8 = arcan_db_appl_val(dbh, appl, "ext_vr_debug");
    defer {
        if (@intFromPtr(kvd) != 0) free(kvd);
    }

    // Allocate VR context
    const vrctx_ptr = arcan_alloc_mem(
        @sizeOf(arcan_vr_ctx),
        ARCAN_MEM_VSTRUCT,
        ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return null;
    const vrctx: *arcan_vr_ctx = @ptrCast(@alignCast(vrctx_ptr));

    // Launch the VR bridge frameserver
    const mvctx = vr_launch_bridge(kv, bridge_arg, kvd, tag) orelse {
        arcan_mem_free(vrctx_ptr);
        return null;
    };

    // Initialize context
    vrctx.* = .{
        .ctx = evctx,
        .connection = mvctx,
    };

    Fsrv.setSegid(mvctx, SEGID_SENSOR);
    _ = arcan_video_alterfeed(
        Fsrv.getVid(mvctx),
        @intCast(FFUNC_VR),
        .{ .tag = ARCAN_TAG_VR, .ptr = vrctx_ptr },
    );

    // Send ACTIVATE event
    var ev = build_event();
    set_event_category(&ev, EVENT_TARGET);
    set_event_tgt_kind(&ev, TARGET_COMMAND_ACTIVATE);
    _ = platform_fsrv_pushevent(mvctx, @ptrCast(&ev));

    return vrctx;
}

// arcan_vr_ffunc_impl
export fn arcan_vr_ffunc_impl(
    cmd: arcan_ffunc_cmd,
    _: [*c]av_pixel,
    _: usize,
    _: u16,
    _: u16,
    _: c_uint,
    state: vfunc_state,
    _: arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv {
    const vrctx: *arcan_vr_ctx = @ptrCast(@alignCast(state.ptr orelse return .FRV_NOFRAME));
    const tgt = vrctx.connection orelse return .FRV_NOFRAME;
    if (state.tag != ARCAN_TAG_VR) return .FRV_NOFRAME;

    // TRAMP_GUARD -- enter critical section for shared memory access
    if (!tramp_enter(tgt)) return .FRV_NOFRAME;

    if (cmd == .FFUNC_DESTROY) {
        _ = arcan_frameserver_free(tgt);
        vrctx.connection = null;

        for (0..LIMB_LIM + 1) |i| {
            if (vrctx.limb_map[i].map != 0) {
                _ = arcan_3d_bindvr(vrctx.limb_map[i].map, null);
                vrctx.limb_map[i].map = 0;
            }
        }
        return .FRV_NOFRAME;
    }

    // Target has not yet requested VR subprotocol access
    const vr = fsrv_get_vr(tgt);
    if (vr == null) {
        if (cmd == .FFUNC_TICK or (cmd == .FFUNC_POLL and fsrv_shm_resized(tgt) != 0)) {
            _ = arcan_frameserver_tick_control(tgt, true, FFUNC_VR);
        }
        platform_fsrv_leave();
        return .FRV_NOFRAME;
    }
    const vr_ptr = vr.?;

    if (cmd == .FFUNC_POLL) {
        for (0..LIMB_LIM) |i| {
            if (vrctx.limb_map[i].map == 0) continue;

            // Check for new sample via timestamp
            const limb_ptr = ShmifVr.getLimbPtr(vr_ptr, i);
            const ts = VrLimb.getTimestamp(limb_ptr);
            if (ts == vrctx.limb_map[i].ts) continue;

            // Copy limb data (non-atomic snapshot)
            var vl_buf: [VrLimb.sizeof_vr_limb]u8 align(8) = undefined;
            @memcpy(&vl_buf, limb_ptr[0..VrLimb.sizeof_vr_limb]);

            // Verify checksum (covers all of vr_limb except the last 2 bytes)
            const cs = subp_checksum(&vl_buf, VrLimb.sizeof_vr_limb - 2);
            if (cs != VrLimb.getDataChecksum(limb_ptr)) continue;

            apply_limb(&vl_buf, &vrctx.limb_map[i]);
            if (i == NECK and vrctx.limb_map[LIMB_LIM].map != 0) {
                apply_limb(&vl_buf, &vrctx.limb_map[LIMB_LIM]);
            }
        }
    } else if (cmd == .FFUNC_TICK) {
        // Check allocation masks for new/lost limbs
        const map = ShmifVr.getLimbMask(vr_ptr);
        const new = map & ~vrctx.map;
        const lost = vrctx.map & ~map;
        const tgt_vid = Fsrv.getVid(tgt);
        const tgt_otag = Fsrv.getTag(tgt);

        if (new != 0) {
            for (0..LIMB_LIM) |i| {
                if ((@as(u64, 1) << @intCast(i)) & new != 0) {
                    var ev = build_event();
                    set_event_category(&ev, EVENT_FSRV);
                    set_event_fsrv(&ev, EVENT_FSRV_ADDVRLIMB, @intCast(i), tgt_vid, tgt_otag);
                    _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&ev));
                    // Mark limb as ignored until explicitly mapped
                    var ok: bool = undefined;
                    tramp_set_limb_ignored(tgt, vr_ptr, i, true, &ok);
                }
            }
        }

        if (lost != 0) {
            for (0..LIMB_LIM) |i| {
                if ((@as(u64, 1) << @intCast(i)) & lost != 0) {
                    var ev = build_event();
                    set_event_category(&ev, EVENT_FSRV);
                    set_event_fsrv(&ev, EVENT_FSRV_LOSTVRLIMB, @intCast(i), tgt_vid, tgt_otag);
                    _ = arcan_event_enqueue(arcan_event_defaultctx(), @ptrCast(&ev));
                    if (vrctx.limb_map[i].map != 0)
                        _ = arcan_3d_bindvr(vrctx.limb_map[i].map, null);
                }
            }
        }
        vrctx.map = map;
    }

    platform_fsrv_leave();
    return .FRV_NOFRAME;
}

// arcan_vr_setref_impl
export fn arcan_vr_setref_impl(ctx: ?*arcan_vr_ctx) arcan_errc {
    const vrctx = ctx orelse return ARCAN_ERRC_UNACCEPTED_STATE;
    const conn = vrctx.connection orelse return ARCAN_ERRC_UNACCEPTED_STATE;

    var ev = build_event();
    set_event_category(&ev, EVENT_TARGET);
    set_event_tgt_kind(&ev, TARGET_COMMAND_RESET);
    _ = platform_fsrv_pushevent(conn, @ptrCast(&ev));

    return ARCAN_OK;
}

// arcan_vr_maplimb_impl
export fn arcan_vr_maplimb_impl(
    ctx: ?*arcan_vr_ctx,
    ind: c_uint,
    vid: arcan_vobj_id,
    use_pos: bool,
    use_orient: bool,
) arcan_errc {
    const vrctx = ctx orelse return ARCAN_ERRC_UNACCEPTED_STATE;
    const conn = vrctx.connection orelse return ARCAN_ERRC_UNACCEPTED_STATE;

    if (ind >= LIMB_LIM) return ARCAN_ERRC_OUT_OF_SPACE;

    const ent = limb_ent{
        .map = vid,
        .position = use_pos,
        .orientation = use_orient,
        .ts = 0,
    };

    // Only 1:1 mapping allowed
    for (0..LIMB_LIM) |i| {
        if (vrctx.limb_map[i].map == vid)
            return ARCAN_ERRC_UNACCEPTED_STATE;
    }

    // Neck special case: second mapping goes to LIMB_LIM slot
    if (ind == NECK) {
        if (vrctx.limb_map[NECK].map != 0 and vrctx.limb_map[LIMB_LIM].map != 0) {
            _ = arcan_3d_bindvr(vrctx.limb_map[LIMB_LIM].map, null);
        } else if (vrctx.limb_map[NECK].map != 0) {
            platform_fsrv_leave();
            vrctx.limb_map[LIMB_LIM] = ent;
            return arcan_3d_bindvr(vid, vrctx);
        }
    }

    // Unmap pre-existing mapping
    if (vrctx.limb_map[ind].map != 0)
        _ = arcan_3d_bindvr(vrctx.limb_map[ind].map, null);

    vrctx.limb_map[ind] = ent;

    const vr = fsrv_get_vr(conn) orelse return ARCAN_ERRC_UNACCEPTED_STATE;

    // Enable sampling (set ignored=false) in tramp-guarded context
    var ok: bool = undefined;
    tramp_set_limb_ignored(conn, vr, ind, false, &ok);
    if (!ok) return ARCAN_ERRC_UNACCEPTED_STATE;

    return arcan_3d_bindvr(vid, vrctx);
}

// arcan_vr_release_impl
// Called when 3dbase tells us that vid is dead
export fn arcan_vr_release_impl(ctx: ?*arcan_vr_ctx, vid: arcan_vobj_id) arcan_errc {
    const vrctx = ctx orelse return ARCAN_ERRC_NO_SUCH_OBJECT;
    var rv: arcan_errc = ARCAN_ERRC_NO_SUCH_OBJECT;

    for (0..LIMB_LIM + 1) |i| {
        if (vrctx.limb_map[i].map == vid) {
            vrctx.limb_map[i].map = 0;
            rv = ARCAN_OK;

            // Reset sampling (set ignored=true)
            if (i < LIMB_LIM) {
                if (vrctx.connection) |conn| {
                    if (fsrv_get_vr(conn)) |vr| {
                        var ok: bool = undefined;
                        tramp_set_limb_ignored(conn, vr, i, true, &ok);
                    }
                }
            }
            break;
        }
    }
    return rv;
}

// arcan_vr_displaydata_impl
export fn arcan_vr_displaydata_impl(ctx: ?*arcan_vr_ctx, dst: ?*anyopaque) arcan_errc {
    const vrctx = ctx orelse return ARCAN_ERRC_NO_SUCH_OBJECT;
    const tgt = vrctx.connection orelse return ARCAN_ERRC_NO_SUCH_OBJECT;
    const vr = fsrv_get_vr(tgt) orelse return ARCAN_ERRC_NO_SUCH_OBJECT;
    const dst_ptr: [*]u8 = @ptrCast(dst orelse return ARCAN_ERRC_NO_SUCH_OBJECT);

    if (!tramp_copy_meta(tgt, vr, dst_ptr))
        return ARCAN_ERRC_UNACCEPTED_STATE;

    return ARCAN_OK;
}

// arcan_vr_shutdown_impl
export fn arcan_vr_shutdown_impl(_: ?*arcan_vr_ctx) arcan_errc {
    // TODO: enqueue EXIT command on connection, signal gone on evctx
    return ARCAN_ERRC_NOT_IMPLEMENTED;
}
