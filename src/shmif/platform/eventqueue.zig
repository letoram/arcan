// Zig reimplementation of platform/eventqueue.c
// Drop-in C-ABI-compatible replacement for event queue setup.
//
// Exports: shmif_platform_setevqs
//
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

export fn shmif_platform_setevqs(
    dst: *anyopaque,
    esem: ?*anyopaque,
    inq: *c.struct_arcan_evctx,
    outq: *c.struct_arcan_evctx,
) void {
    if (is_freestanding) return;
    _ = esem;

    inq.*.synch.synch = @ptrCast(@alignCast(off.Page.getEsyncPtr(dst)));
    inq.*.synch.killswitch = off.Page.getDmsPtr(dst);
    outq.*.synch.killswitch = off.Page.getDmsPtr(dst);

    // ARCAN_SHMIF_THREADSAFE_QUEUE path omitted (typically not compiled)

    inq.*.local = 0; // false
    inq.*.eventbuf = @ptrCast(@alignCast(off.Page.childevqEventbuf(dst)));
    inq.*.front = off.Page.childevqFrontPtr(dst);
    inq.*.back = off.Page.childevqBackPtr(dst);
    inq.*.eventbuf_sz = c.PP_QUEUE_SZ;

    outq.*.local = 0; // false
    outq.*.eventbuf = @ptrCast(@alignCast(off.Page.parentevqEventbuf(dst)));
    outq.*.front = off.Page.parentevqFrontPtr(dst);
    outq.*.back = off.Page.parentevqBackPtr(dst);
    outq.*.eventbuf_sz = c.PP_QUEUE_SZ;
}
