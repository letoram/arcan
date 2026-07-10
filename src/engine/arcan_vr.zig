// Zig port of engine/arcan_vr.c
// VR subsystem: setup, limb mapping, ffunc callback.
// Heavy lifting in arcan_vr_helpers.c

const arcan_errc = c_int;
const arcan_vobj_id = i64;
const av_pixel = u32;

const arcan_vr_ctx = opaque {};
const arcan_evctx = opaque {};
const vr_meta = anyopaque;

// FFUNC_HEAD types for arcan_vr_ffunc
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

extern fn arcan_vr_setup_impl(bridge_arg: [*c]const u8, evctx: ?*arcan_evctx, tag: usize) ?*arcan_vr_ctx;
extern fn arcan_vr_ffunc_impl(arcan_ffunc_cmd, [*c]av_pixel, usize, u16, u16, c_uint, vfunc_state, arcan_vobj_id) callconv(.c) arcan_ffunc_rv;
extern fn arcan_vr_setref_impl(ctx: ?*arcan_vr_ctx) arcan_errc;
extern fn arcan_vr_maplimb_impl(ctx: ?*arcan_vr_ctx, ind: c_uint, vid: arcan_vobj_id, use_pos: bool, use_orient: bool) arcan_errc;
extern fn arcan_vr_release_impl(ctx: ?*arcan_vr_ctx, vid: arcan_vobj_id) arcan_errc;
extern fn arcan_vr_displaydata_impl(ctx: ?*arcan_vr_ctx, dst: ?*vr_meta) arcan_errc;
extern fn arcan_vr_shutdown_impl(ctx: ?*arcan_vr_ctx) arcan_errc;

export fn arcan_vr_setup(bridge_arg: [*c]const u8, evctx: ?*arcan_evctx, tag: usize) ?*arcan_vr_ctx {
    return arcan_vr_setup_impl(bridge_arg, evctx, tag);
}

export fn arcan_vr_ffunc(cmd: arcan_ffunc_cmd, buf: [*c]av_pixel, buf_sz: usize, w: u16, h: u16, mode: c_uint, state: vfunc_state, srcid: arcan_vobj_id) callconv(.c) arcan_ffunc_rv {
    return arcan_vr_ffunc_impl(cmd, buf, buf_sz, w, h, mode, state, srcid);
}

export fn arcan_vr_setref(ctx: ?*arcan_vr_ctx) arcan_errc {
    return arcan_vr_setref_impl(ctx);
}

export fn arcan_vr_maplimb(ctx: ?*arcan_vr_ctx, ind: c_uint, vid: arcan_vobj_id, use_pos: bool, use_orient: bool) arcan_errc {
    return arcan_vr_maplimb_impl(ctx, ind, vid, use_pos, use_orient);
}

export fn arcan_vr_release(ctx: ?*arcan_vr_ctx, vid: arcan_vobj_id) arcan_errc {
    return arcan_vr_release_impl(ctx, vid);
}

export fn arcan_vr_displaydata(ctx: ?*arcan_vr_ctx, dst: ?*vr_meta) arcan_errc {
    return arcan_vr_displaydata_impl(ctx, dst);
}

export fn arcan_vr_shutdown(ctx: ?*arcan_vr_ctx) arcan_errc {
    return arcan_vr_shutdown_impl(ctx);
}
