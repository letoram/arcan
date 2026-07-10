// Zig port of engine/arcan_ffunc_lut.c
// mmap-based function pointer lookup table for frame functions.

const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);

const c = if (is_freestanding) struct {
    const MAP_FAILED: ?*anyopaque = @ptrFromInt(std.math.maxInt(usize));
    const MAP_ANONYMOUS: c_int = 0x20;
    const MAP_PRIVATE: c_int = 0x02;
    const PROT_READ: c_int = 0x1;
    const PROT_WRITE: c_int = 0x2;
    fn mmap(_: ?*anyopaque, _: usize, _: c_int, _: c_int, _: c_int, _: isize) ?*anyopaque { return MAP_FAILED; }
    fn munmap(_: ?*anyopaque, _: usize) c_int { return -1; }
    fn mprotect(_: ?*anyopaque, _: usize, _: c_int) c_int { return -1; }
} else @import("posix");

const std = @import("std");

// av_pixel = uint32_t, arcan_vobj_id = long long (i64)
const av_pixel = u32;
const arcan_vobj_id = i64;

const vfunc_state = extern struct {
    tag: c_int,
    ptr: ?*anyopaque,
};

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

// arcan_vfunc_cb: function pointer matching FFUNC_HEAD
const arcan_vfunc_cb = *const fn (
    arcan_ffunc_cmd,
    [*c]av_pixel,
    usize,
    u16,
    u16,
    c_uint,
    vfunc_state,
    arcan_vobj_id,
) callconv(.c) arcan_ffunc_rv;

const ffunc_ind = u8;

// Enum indices for the LUT slots
const FFUNC_NULL: usize = 1;
const FFUNC_AVFEED: usize = 2;
const FFUNC_NULLFEED: usize = 3;
const FFUNC_FEEDCOPY: usize = 4;
const FFUNC_VFRAME: usize = 5;
const FFUNC_NULLFRAME: usize = 6;
const FFUNC_WRAPPED: usize = 7;
const FFUNC_LUA_PROC: usize = 8;
const FFUNC_3DOBJ: usize = 9;
const FFUNC_LWA: usize = 10;
const FFUNC_VR: usize = 11;
const FFUNC_SOCKVER: usize = 12;
const FFUNC_SOCKPOLL: usize = 13;

// Extern engine function pointers
extern fn arcan_frameserver_avfeedframe(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_feedcopy(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_emptyframe(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_vdirect(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_nullfeed(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_lua_proctarget(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_ffunc_3dobj(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_verifyffunc(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_pollffunc(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_vr_ffunc(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_frameserver_wrapped(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;

extern fn arcan_fatal(msg: [*c]const u8, ...) callconv(.c) void;

extern var system_page_size: c_int;

// The mmap'd LUT — stored as raw pointer to function pointer array
var f_lut: [*c]arcan_vfunc_cb = null;

fn fatal_ffunc(cmd: arcan_ffunc_cmd, _: [*c]av_pixel, _: usize, _: u16, _: u16, _: c_uint, _: vfunc_state, vid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv {
    // Upstream C `arcan_fatal`s here, which is why intensive test-driven
    // connect/disconnect cycles (tests/a12_interop/tier_media_matrix.sh)
    // would coredump durian on the first RT teardown race where a vobj's
    // feed.ffunc still points at an unregistered slot.
    //
    // The triggering chain, from a captured log:
    //     ffunc_lut(), invalid index used in ffunc CB
    //     arcan_video_deleteobject(reference-pass) -- remove rendertarget
    //     luaL_checkvid() failed, invalid vid (N)
    //
    // i.e. deleteobject on a rendertarget fires this CB on a child vobj
    // whose ffunc slot was already cleared by an earlier cleanup pass.
    // Fatal is the wrong response — we degrade to "no frame produced"
    // and emit a one-shot warning so the condition is still visible.
    const S = struct {
        var warned: bool = false;
    };
    if (!S.warned) {
        S.warned = true;
        arcan_warning(
            "ffunc_lut: invalid ffunc index used in CB (vid=%d cmd=%d); " ++
                "degraded to FRV_NOFRAME. Further occurrences silenced.\n",
            @as(c_int, @intCast(vid)), @as(c_int, @intFromEnum(cmd)),
        );
    }
    return .FRV_NOFRAME;
}

extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;

fn null_ffunc(_: arcan_ffunc_cmd, _: [*c]av_pixel, _: usize, _: u16, _: u16, _: c_uint, _: vfunc_state, _: arcan_vobj_id) callconv(.c) arcan_ffunc_rv {
    return .FRV_NOFRAME;
}

export fn arcan_ffunc_initlut() void {
    const page_sz: usize = @intCast(system_page_size);

    // recovery scripts might force this to be called multiple times
    if (f_lut != null) {
        _ = c.munmap(@ptrCast(f_lut), page_sz);
        f_lut = null;
    }

    const ptr = c.mmap(null, page_sz, c.PROT_READ | c.PROT_WRITE, c.MAP_ANONYMOUS | c.MAP_PRIVATE, -1, 0);
    if (ptr == c.MAP_FAILED) {
        arcan_fatal("ffunc_lut() investigate memory issues");
        return;
    }

    f_lut = @ptrCast(@alignCast(ptr));

    const n_entries = page_sz / @sizeOf(arcan_vfunc_cb);
    for (0..n_entries) |i| {
        f_lut[i] = &fatal_ffunc;
    }

    f_lut[FFUNC_NULL] = &null_ffunc;
    f_lut[FFUNC_AVFEED] = &arcan_frameserver_avfeedframe;
    f_lut[FFUNC_FEEDCOPY] = &arcan_frameserver_feedcopy;
    f_lut[FFUNC_NULLFRAME] = &arcan_frameserver_emptyframe;
    f_lut[FFUNC_VFRAME] = &arcan_frameserver_vdirect;
    f_lut[FFUNC_NULLFEED] = &arcan_frameserver_nullfeed;
    f_lut[FFUNC_LUA_PROC] = &arcan_lua_proctarget;
    f_lut[FFUNC_3DOBJ] = &arcan_ffunc_3dobj;
    f_lut[FFUNC_SOCKVER] = &arcan_frameserver_verifyffunc;
    f_lut[FFUNC_SOCKPOLL] = &arcan_frameserver_pollffunc;
    f_lut[FFUNC_VR] = &arcan_vr_ffunc;
    f_lut[FFUNC_WRAPPED] = &arcan_frameserver_wrapped;
    f_lut[FFUNC_LWA] = &fatal_ffunc;

    _ = c.mprotect(@ptrCast(f_lut), page_sz, c.PROT_READ);
}

export fn arcan_ffunc_register(cb: arcan_vfunc_cb) c_int {
    const page_sz: usize = @intCast(system_page_size);

    // sweep for a free slot (one referencing fatal_ffunc, not LWA)
    var found: c_int = -1;
    for (1..256) |i| {
        if (f_lut[i] == &fatal_ffunc and i != FFUNC_LWA) {
            found = @intCast(i);
            break;
        }
    }

    if (found == -1)
        return -1;

    // protect against duplicate registration
    for (0..256) |i| {
        if (f_lut[i] == cb)
            return @intCast(i);
    }

    // unprotect, register, re-protect
    _ = c.mprotect(@ptrCast(f_lut), page_sz, c.PROT_READ | c.PROT_WRITE);
    f_lut[@intCast(found)] = cb;
    _ = c.mprotect(@ptrCast(f_lut), page_sz, c.PROT_READ);

    return found;
}

export fn arcan_ffunc_lookup(ind: ffunc_ind) arcan_vfunc_cb {
    return f_lut[ind];
}
