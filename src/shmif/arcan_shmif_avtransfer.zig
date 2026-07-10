// Zig reimplementation of arcan_shmif_avtransfer.c
// Drop-in C-ABI-compatible replacement for avtransfer functions.
//
// Exports: arcan_shmif_signal, arcan_shmif_signalhandle
//
//
const std = @import("std");
const off = @import("shmif_offsets");
const c = @import("shmif_types");

// Function pointer types for hooks
const ShmifTriggerHookFn = *const fn (?*c.struct_arcan_shmif_cont) callconv(.c) c_int;
const SupportWindowHookFn = *const fn (?*c.struct_arcan_shmif_cont, c_int) callconv(.c) void;

// Extern C declarations

extern "c" fn arcan_timemillis() u64;
extern "c" fn shmif_platform_sync_mark(page: *anyopaque, slot: c_int) void;
extern "c" fn shmif_platform_sync_wait(page: *anyopaque, slot: c_int) c_int;
extern "c" fn shmif_platform_check_alive(ctx: *c.struct_arcan_shmif_cont) bool;
extern "c" fn shmif_platform_fallback(
    ctx: *c.struct_arcan_shmif_cont,
    cp: [*c]const u8,
    force: bool,
) c.enum_shmif_migrate_status;
extern "c" fn shmif_platform_pushfd(fd: c_int, sockout: c_int) bool;

extern "c" fn arcan_shmif_enqueue(
    ctx: *c.struct_arcan_shmif_cont,
    ev: *c.arcan_event,
) c_int;

const SYNC_VIDEO: c_int = 4;
const SYNC_AUDIO: c_int = 2;

// shmif_pixel is uint32_t, shmif_asample is int16_t
const shmif_pixel = u32;
const SHMIF_ASAMPLE_SIZE = 2; // sizeof(int16_t)

// SHMIF_RGBA(0, 0, 0, 255) = 0xFF000000
const RGBA_BLACK_OPAQUE: shmif_pixel = 0xFF000000;

// is_output_segment (from shmif_platform.h)

fn is_output_segment(segid: c_int) bool {
    return (segid == c.SEGID_ENCODER or segid == c.SEGID_CLIPBOARD_PASTE);
}

// FORCE_SYNCH() macro equivalent
// Mirrors the C macro: __asm volatile("": : :"memory"); __sync_synchronize();
// In Zig 0.15, std.atomic.fence was removed, so we use @atomicRmw with
// .seq_cst ordering on a dummy variable to emit a full hardware memory barrier.

var force_synch_dummy: u32 = 0;
inline fn force_synch() void {
    asm volatile ("" ::: .{ .memory = true });
    _ = @atomicRmw(u32, &force_synch_dummy, .Add, 0, .seq_cst);
}

// calc_dirty

fn calc_dirty(
    ctx: *c.struct_arcan_shmif_cont,
    new_buf: [*c]shmif_pixel,
    old: [*c]shmif_pixel,
) bool {
    var diff: shmif_pixel = RGBA_BLACK_OPAQUE;
    const ref: shmif_pixel = RGBA_BLACK_OPAQUE;
    const ctx_w: usize = ctx.w;
    const ctx_h: usize = ctx.h;
    const ctx_pitch: usize = ctx.pitch;

    // find dirty y1, if this does not find anything, short-out
    var cy: usize = 0;
    while (cy < ctx_h and diff == ref) : (cy += 1) {
        var x: usize = 0;
        while (x < ctx_w and diff == ref) : (x += 1) {
            diff |= old[ctx_pitch * cy + x] ^ new_buf[ctx_pitch * cy + x];
        }
    }

    if (diff == ref)
        return false;

    ctx.dirty.y1 = @intCast(cy - 1);

    // find dirty y2, since y1 is dirty there must be one
    diff = ref;
    cy = ctx_h - 1;
    while (cy > 0 and diff == ref) : (cy -= 1) {
        var x: usize = 0;
        while (x < ctx_w and diff == ref) : (x += 1) {
            diff |= old[ctx_pitch * cy + x] ^ new_buf[ctx_pitch * cy + x];
        }
    }

    // dirty region starts at y1 and ends < y2
    ctx.dirty.y2 = @intCast(cy + 1);

    // now do x in the same way
    var cx: usize = undefined;
    diff = ref;
    cx = 0;
    while (cx < ctx_w and diff == ref) : (cx += 1) {
        cy = ctx.dirty.y1;
        while (cy < ctx.dirty.y2 and diff == ref) : (cy += 1) {
            diff |= old[ctx_pitch * cy + cx] ^ new_buf[ctx_pitch * cy + cx];
        }
    }
    ctx.dirty.x1 = @intCast(cx - 1);

    diff = ref;
    cx = ctx_w - 1;
    while (cx > 0 and diff == ref) : (cx -= 1) {
        cy = ctx.dirty.y1;
        while (cy < ctx.dirty.y2 and diff == ref) : (cy += 1) {
            diff |= old[ctx_pitch * cy + cx] ^ new_buf[ctx_pitch * cy + cx];
        }
    }

    ctx.dirty.x2 = @intCast(cx + 1);

    return true;
}

// step_v

fn step_v(ctx: *c.struct_arcan_shmif_cont, sigv: c_int) bool {
    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));
    var lock = false;

    const page: *anyopaque = ctx.addr orelse return false;

    // atomic_store(&ctx->addr->hints, ctx->hints)
    off.Page.setHints(page, ctx.hints);
    off.Hidden.incVframeId(P);

    // subregion is part of the shared block and not the video buffer itself
    if (ctx.hints & @as(u8, c.SHMIF_RHINT_SUBREGION) != 0) {

        // set if we should trim the dirty region based on current ^ last buffer
        if ((sigv & @as(c_int, c.SHMIF_SIGVID_AUTO_DIRTY) != 0) and
            off.Hidden.getVbufNbufActive(P) and off.Hidden.getVbufCnt(P) > 1)
        {
            var old: [*c]shmif_pixel = undefined;
            if (off.Hidden.getVbufInd(P) == 0)
                old = @ptrCast(@alignCast(off.Hidden.getVbuf(P, off.Hidden.getVbufCnt(P) - 1)))
            else
                old = @ptrCast(@alignCast(off.Hidden.getVbuf(P, off.Hidden.getVbufInd(P) - 1)));

            if (!calc_dirty(ctx, @ptrCast(@alignCast(ctx.unnamed_0.vidp)), old)) {
                return false;
            }
        }

        if (ctx.dirty.x2 <= ctx.dirty.x1 or ctx.dirty.y2 <= ctx.dirty.y1) {
            ctx.dirty.x1 = 0;
            ctx.dirty.y1 = 0;
            ctx.dirty.x2 = @intCast(ctx.w);
            ctx.dirty.y2 = @intCast(ctx.h);
        }

        // atomic_store(&ctx->addr->dirty, ctx->dirty)
        // struct_arcan_shmif_region is 8 bytes (4 x u16), store as u64 atomically
        off.Page.setDirtyRaw(page, @bitCast(ctx.dirty));

        // set an invalid dirty region so any subsequent signals would be ignored
        ctx.dirty.y2 = 0;
        ctx.dirty.x2 = 0;
        ctx.dirty.y1 = @intCast(ctx.h);
        ctx.dirty.x1 = @intCast(ctx.w);
    }

    // mark the current buffer as pending
    const shift_val: u5 = @intCast(off.Hidden.getVbufInd(P));
    const pending: c_int = @bitCast(@atomicRmw(
        u32,
        off.Page.getVpendingPtr(page),
        .Or,
        @as(u32, 1) << shift_val,
        .release,
    ));
    const dst_i: c_int = @as(c_int, off.Hidden.getVbufInd(P)) + 1;

    // let a latched support content analysis work through the buffer
    if (off.Hidden.getSupportWindowHook(P)) |hook_opaque| {
        const hook: SupportWindowHookFn = @ptrCast(@alignCast(hook_opaque));
        hook(ctx, c.SUPPORT_EVENT_VSIGNAL);
    }

    // slide window so the caller doesn't have to care about which buffer
    off.Hidden.setVbufInd(P, off.Hidden.getVbufInd(P) + 1);
    off.Hidden.setVbufNbufActive(P, true);
    if (off.Hidden.getVbufInd(P) == off.Hidden.getVbufCnt(P))
        off.Hidden.setVbufInd(P, 0);

    // note if we need to wait for an ack before continuing
    const new_shift: u5 = @intCast(off.Hidden.getVbufInd(P));
    lock = off.Hidden.getVbufCnt(P) == 1 or (pending & (@as(c_int, 1) << new_shift)) != 0;
    ctx.unnamed_0.vidp = @ptrCast(@alignCast(off.Hidden.getVbuf(P, off.Hidden.getVbufInd(P))));

    if (lock)
        shmif_platform_sync_mark(page, SYNC_VIDEO);

    // atomic_signal_fence(memory_order_seq_cst) -- compiler barrier
    asm volatile ("" ::: .{ .memory = true });
    // atomic_store_explicit(&ctx->addr->vready, dst_i, memory_order_seq_cst)
    off.Page.setVready(page, @bitCast(dst_i));

    // DIAGNOSTIC: log when vready is set (first 3 times)
    {
        const diag = struct { var count: u32 = 0; };
        if (diag.count < 3) {
            diag.count += 1;
            var dbuf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&dbuf, "[DIAG step_v #{d}] vready={d}, vidp=0x{x}, w={d}, h={d}\n", .{
                diag.count, dst_i, @intFromPtr(ctx.unnamed_0.vidp), ctx.w, ctx.h,
            }) catch "[DIAG step_v] bufPrint failed\n";
            _ = std.posix.write(2, msg) catch {};
        }
    }

    return lock;
}

// step_a

fn step_a(ctx: *c.struct_arcan_shmif_cont) bool {
    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));
    var lock = false;

    const page: *anyopaque = ctx.addr orelse return false;

    if (ctx.abufpos != 0)
        ctx.abufused = ctx.abufpos * SHMIF_ASAMPLE_SIZE;

    if (ctx.abufused == 0)
        return false;

    // atomic, set [pending, used] -> flag
    const shift_val: u5 = @intCast(off.Hidden.getAbufInd(P));
    var pending: c_int = @bitCast(@atomicRmw(
        u32,
        off.Page.getApendingPtr(page),
        .Or,
        @as(u32, 1) << shift_val,
        .release,
    ));

    // atomic_store_explicit(&ctx->addr->abufused[priv->abuf_ind], ctx->abufused, ...)
    @atomicStore(
        u16,
        off.Page.getAbufusedPtr(page, off.Hidden.getAbufInd(P)),
        ctx.abufused,
        .release,
    );

    // atomic_store_explicit(&ctx->addr->aready, priv->abuf_ind+1, ...)
    @atomicStore(
        u32,
        off.Page.getAreadyPtr(page),
        @as(u32, off.Hidden.getAbufInd(P)) + 1,
        .release,
    );

    // now it is safe to slide local references
    pending |= @as(c_int, 1) << shift_val;

    off.Hidden.setAbufInd(P, off.Hidden.getAbufInd(P) + 1);
    if (off.Hidden.getAbufInd(P) == off.Hidden.getAbufCnt(P))
        off.Hidden.setAbufInd(P, 0);
    ctx.abufused = 0;
    ctx.abufpos = 0;
    ctx.unnamed_1.audp = @ptrCast(@alignCast(off.Hidden.getAbuf(P, off.Hidden.getAbufInd(P))));
    const new_shift: u5 = @intCast(off.Hidden.getAbufInd(P));
    lock = off.Hidden.getAbufCnt(P) == 1 or (pending & (@as(c_int, 1) << new_shift)) != 0;

    force_synch();
    return lock;
}

// arcan_shmif_signal

export fn arcan_shmif_signal(C: ?*c.struct_arcan_shmif_cont, mask_in: c_int) c_uint {
    const ctx = C orelse return 0;
    if (ctx.addr == null or ctx.unnamed_0.vidp == null)
        return 0;

    if (ctx.priv == null) return 0;
    const P: *anyopaque = @ptrCast(@alignCast(ctx.priv));
    const page: *anyopaque = ctx.addr orelse return 0;

    var mask = mask_in;

    // DIAGNOSTIC: log when SIGVID signal fires (first 3 times)
    if (mask_in & @as(c_int, c.SHMIF_SIGVID) != 0) {
        const diag = struct { var count: u32 = 0; };
        if (diag.count < 3) {
            diag.count += 1;
            var dbuf: [256]u8 = undefined;
            const msg = std.fmt.bufPrint(&dbuf, "[DIAG CHILD SIGNAL #{d}] vidp=0x{x}, w={d}, h={d}, mask=0x{x}\n", .{
                diag.count, @intFromPtr(ctx.unnamed_0.vidp), ctx.w, ctx.h, @as(u32, @bitCast(mask_in)),
            }) catch "[DIAG CHILD SIGNAL] bufPrint failed\n";
            _ = std.posix.write(2, msg) catch {};
        }
    }

    // semantics for output segments are easier, no chunked buffers or hooks
    if (is_output_segment(off.Hidden.getType(P))) {
        if (mask & @as(c_int, c.SHMIF_SIGVID) != 0)
            off.Page.setVready(page, 0);
        if (mask & @as(c_int, c.SHMIF_SIGAUD) != 0)
            off.Page.setAready(page, 0);
        return 0;
    }

    // if we are in migration there is no reason to go into signal
    if (off.Hidden.getInMigrate(P))
        return 0;

    // and if we are in signal, migration will need to unlock semaphores
    off.Hidden.setInSignal(P, true);

    // protect against callers stuck in 'just signal as a means of draining buffers'
    if (!shmif_platform_check_alive(ctx)) {
        ctx.abufused = 0;
        ctx.abufpos = 0;
        _ = shmif_platform_fallback(ctx, off.Hidden.getAltConn(P), true);
        off.Hidden.setInSignal(P, false);
        return 0;
    }

    const startt: u64 = arcan_timemillis();

    if ((mask & @as(c_int, c.SHMIF_SIGVID) != 0) and off.Hidden.getVideoHook(P) != null) {
        if (off.Hidden.getVideoHook(P)) |hook_opaque| {
            const hook: ShmifTriggerHookFn = @ptrCast(@alignCast(hook_opaque));
            mask = @bitCast(hook(ctx));
        }
    }

    if ((mask & @as(c_int, c.SHMIF_SIGAUD) != 0) and off.Hidden.getAudioHook(P) != null) {
        if (off.Hidden.getAudioHook(P)) |hook_opaque| {
            const hook: ShmifTriggerHookFn = @ptrCast(@alignCast(hook_opaque));
            mask = @bitCast(hook(ctx));
        }
    }

    if (mask & @as(c_int, c.SHMIF_SIGAUD) != 0) {
        var a_lock = step_a(ctx);

        // This is different from video as we can get a partial accept
        if (a_lock and (mask & @as(c_int, c.SHMIF_SIGBLK_NONE) == 0)) {
            while (a_lock and off.Page.getApending(page) != 0 and
                shmif_platform_check_alive(ctx))
            {
                if (off.Page.getAready(page) == 0)
                    a_lock = step_a(ctx);

                _ = shmif_platform_sync_wait(page, SYNC_AUDIO);
            }
        }
    }

    // for sub-region multi-buffer synch, check before running step_v
    if (mask & @as(c_int, c.SHMIF_SIGVID) != 0) {
        while ((ctx.hints & @as(u8, c.SHMIF_RHINT_SUBREGION) != 0) and
            off.Page.getVready(page) != 0 and
            shmif_platform_check_alive(ctx))
        {
            _ = shmif_platform_sync_wait(page, SYNC_VIDEO);
        }

        const v_lock = step_v(ctx, mask);

        if (v_lock and (mask & @as(c_int, c.SHMIF_SIGBLK_NONE) == 0)) {
            while (off.Page.getVready(page) != 0 and
                shmif_platform_check_alive(ctx))
            {
                _ = shmif_platform_sync_wait(page, SYNC_VIDEO);
            }
        }
    }

    off.Hidden.setInSignal(P, false);
    return @truncate(arcan_timemillis() -% startt);
}

// arcan_shmif_signalhandle

export fn arcan_shmif_signalhandle(
    ctx: ?*c.struct_arcan_shmif_cont,
    mask: c_int,
    handle: c_int,
    stride: usize,
    format: c_int,
) c_uint {
    const cont = ctx orelse return 0;

    if (!shmif_platform_pushfd(handle, cont.epipe))
        return 0;

    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.category().* = c.EVENT_EXTERNAL;
    ev.ext().kind = c.EVENT_EXTERNAL_BUFFERSTREAM;
    ev.ext().bstream().width = @intCast(cont.w);
    ev.ext().bstream().height = @intCast(cont.h);
    ev.ext().bstream().stride = @intCast(stride);
    ev.ext().bstream().format = @bitCast(format);
    _ = arcan_shmif_enqueue(cont, &ev);
    return arcan_shmif_signal(cont, mask);
}
