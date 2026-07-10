// Zig reimplementation of arcan_shmif_eventhandler.c
// Drop-in C-ABI-compatible replacement for the event processing core.
//
// Exports: shmifint_process_events, shmifint_consume_pending
//
// This is the central event dispatch loop. It handles:
//  - blocking or nonblocking (from wait or poll)
//  - paused state (only accept UNPAUSE)
//  - crashed or connection terminated
//  - pairing fd and event for descriptor events
//  - cleanup of pending resources not consumed by client
//  - merging event storms (pending hint, ph)
//  - key state transitions (device switch, migration)
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

const BADFD = c.BADFD;

// Extern C declarations

extern fn shmif_platform_check_alive(cont: *c.struct_arcan_shmif_cont) bool;
extern fn shmif_platform_fetchfds(
    sockin: c_int,
    fdout: [*c]c_int,
    cap: usize,
    blocking: bool,
    alive_check: ?*const fn (?*anyopaque) callconv(.c) bool,
    tag: ?*anyopaque,
) c_int;
extern fn shmif_platform_fallback(
    cont: *c.struct_arcan_shmif_cont,
    cp: [*c]const u8,
    force: bool,
) c.enum_shmif_migrate_status;

extern fn arcan_shmif_eventstr(
    ev: *c.arcan_event,
    buf: ?[*c]u8,
    sz: usize,
) [*c]const u8;
extern fn arcan_shmif_acquire(
    parent: *c.struct_arcan_shmif_cont,
    key: [*c]const u8,
    segtype: c_int,
    flags: c_int,
) c.struct_arcan_shmif_cont;
extern fn arcan_shmif_drop(ctx: *c.struct_arcan_shmif_cont) void;
extern fn arcan_shmif_a11yint_spawn(
    ctx: *c.struct_arcan_shmif_cont,
    p: *c.struct_arcan_shmif_cont,
) bool;
extern fn arcan_timemillis() c_longlong;
extern fn close(fd: c_int) c_int;
extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn strerror(errnum: c_int) [*c]const u8;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(s: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern fn shmifint_privsep_mark_fd(fd: c_int, mode: c_int) c_int;
extern fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern fn strlen(s: [*c]const u8) usize;
extern fn getenv(name: [*c]const u8) [*c]u8;
extern fn mmap(addr: ?*anyopaque, len: usize, prot: c_int, flags: c_int, fd: c_int, offset: isize) ?*anyopaque;
extern fn munmap(addr: ?*anyopaque, len: usize) c_int;

const PROT_READ: c_int = 0x1;
const PROT_WRITE: c_int = 0x2;
const MAP_SHARED: c_int = 0x01;
const MAP_FAILED: usize = @as(usize, 0) -% 1; // (void*)-1

// Gated behind ARCAN_SHMIF_PEDBG=1 env var. When off (default) this is a
// near-zero-cost early return. A prior version wrote unconditionally and
// produced ~1M writes/sec under heavy event traffic (vim, htop), which the
// kernel redirected to the per-frameserver log file and drove afsrv_terminal
// to 99% CPU + a 4GB log within minutes.
var pedbg_state: enum(u8) { unchecked, off, on } = .unchecked;


fn evdbg(msg: [*c]const u8) void {
    switch (pedbg_state) {
        .off => return,
        .on => {
            _ = write(2, msg, strlen(msg));
        },
        .unchecked => {
            pedbg_state = if (getenv("ARCAN_SHMIF_PEDBG") != null) .on else .off;
            if (pedbg_state == .on) {
                _ = write(2, msg, strlen(msg));
            }
        },
    }
}

// local offset helpers (cast *anyopaque from shmif_offsets to C types)
inline fn pevEvPtr(P: *anyopaque) *c.arcan_event {
    return @ptrCast(@alignCast(off.Hidden.getPevEvPtr(P)));
}
inline fn dhPtr(P: *anyopaque) *c.arcan_event {
    return @ptrCast(@alignCast(off.Hidden.getDhPtr(P)));
}
inline fn fhPtr(P: *anyopaque) *c.arcan_event {
    return @ptrCast(@alignCast(off.Hidden.getFhPtr(P)));
}
inline fn inevPtr(P: *anyopaque) *c.struct_arcan_evctx {
    return @ptrCast(@alignCast(off.Hidden.getInevPtr(P)));
}

const EAGAIN = 11;

// merge_dh (displayhint coalescing)

fn merge_dh(new: *c.arcan_event, old: *c.arcan_event) bool {
    const new_tgt = new.tgt();
    const old_tgt = old.tgt();

    if (new_tgt.ioevs[7].uiv != old_tgt.ioevs[7].uiv)
        return false;

    if (new_tgt.ioevs[0].iv == 0)
        new_tgt.ioevs[0].iv = old_tgt.ioevs[0].iv;

    if (new_tgt.ioevs[1].iv == 0)
        new_tgt.ioevs[1].iv = old_tgt.ioevs[1].iv;

    if (new_tgt.ioevs[3].iv < 0)
        new_tgt.ioevs[3].iv = old_tgt.ioevs[3].iv;

    if (!(new_tgt.ioevs[4].fv > 0))
        new_tgt.ioevs[4].fv = old_tgt.ioevs[4].fv;

    if (new_tgt.ioevs[5].iv == 0)
        new_tgt.ioevs[5].iv = old_tgt.ioevs[5].iv;

    if (new_tgt.ioevs[6].iv == 0)
        new_tgt.ioevs[6].iv = old_tgt.ioevs[6].iv;

    if (new_tgt.unnamed_0.timestamp == 0) {
        new_tgt.unnamed_0.timestamp = @intCast(arcan_timemillis());
    }

    return true;
}

// scan_stepframe_event

fn scan_stepframe_event(ctx: *c.struct_arcan_evctx, old: *c.arcan_event, id: c_int) bool {
    if (old.tgt().ioevs[1].iv != id)
        return false;

    var cur: u8 = @as(*volatile u8, @ptrCast(ctx.front)).*;
    const back: u8 = @as(*volatile u8, @ptrCast(ctx.back)).*;

    while (cur != back) {
        const ev: *c.arcan_event = @ptrCast(&ctx.eventbuf[cur]);
        if (ev.category().* == c.EVENT_TARGET and
            ev.tgt().kind == c.TARGET_COMMAND_STEPFRAME and
            ev.tgt().ioevs[1].iv == id)
            return true;
        cur = (cur + 1) % ctx.eventbuf_sz;
    }
    return false;
}

// scan_display_event

fn scan_display_event(ctx: *c.struct_arcan_evctx, old: *c.arcan_event) bool {
    var cur: u8 = @as(*volatile u8, @ptrCast(ctx.front)).*;
    const back: u8 = @as(*volatile u8, @ptrCast(ctx.back)).*;

    while (cur != back) {
        const ev: *c.arcan_event = @ptrCast(&ctx.eventbuf[cur]);
        if (ev.category().* == c.EVENT_TARGET and
            ev.tgt().kind == old.tgt().kind and
            merge_dh(ev, old))
        {
            return true;
        }
        cur = (cur + 1) % ctx.eventbuf_sz;
    }

    return false;
}

// event_to_fdmode

fn event_to_fdmode(ev: *c.arcan_event) c_int {
    if (ev.category().* != c.EVENT_TARGET)
        return c.MARK_PASS;

    const kind = ev.tgt().kind;
    if (kind == c.TARGET_COMMAND_BCHUNK_IN or
        kind == c.TARGET_COMMAND_RESTORE or
        kind == c.TARGET_COMMAND_FONTHINT)
    {
        return c.MARK_READ;
    } else if (kind == c.TARGET_COMMAND_BCHUNK_OUT or
        kind == c.TARGET_COMMAND_STORE)
    {
        return c.MARK_WRITE;
    }

    // failsafe so we won't just break everything and have something to watch
    return c.MARK_PASS;
}

// fd_event

fn fd_event(cont: *c.struct_arcan_shmif_cont, dst: *c.arcan_event) bool {
    const private: *anyopaque = @ptrCast(@alignCast(cont.priv));
    off.Hidden.setPevConsumed(private, true);

    if (dst.category().* == c.EVENT_TARGET and
        dst.tgt().kind == c.TARGET_COMMAND_NEWSEGMENT)
    {
        // forward the file descriptor as well so that, in the case of a HANDOVER,
        // the parent process has enough information to forward into a new process.
        const marked_sock = shmifint_privsep_mark_fd(off.Hidden.getPevFd(private, 0), c.MARK_SOCKET);
        dst.tgt().ioevs[0].iv = marked_sock;
        off.Hidden.setPsegEpipe(private, marked_sock);

        dst.tgt().ioevs[6].iv =
            shmifint_privsep_mark_fd(off.Hidden.getPevFd(private, 1), c.MARK_SHMIF);

        _ = snprintf(
            @as([*c]u8, @ptrCast(dst.tgt().message())),
            @sizeOf(@TypeOf(dst.tgt().message().*)),
            "%d",
            dst.tgt().ioevs[6].iv,
        );
        return true;
    }
    // Compositor-allocated DMA-BUF vidp (subtype 6): mmap fd, replace vidp
    else if (dst.category().* == c.EVENT_TARGET and
        dst.tgt().kind == c.TARGET_COMMAND_DEVICE_NODE and
        dst.tgt().ioevs[1].iv == 6)
    {
        const fd = off.Hidden.getPevFd(private, 0);
        if (fd >= 0) {
            const stride: u32 = @intCast(dst.tgt().ioevs[2].iv);
            const h: u32 = @intCast(cont.h);
            const map_sz: usize = @as(usize, stride) * @as(usize, h);

            if (map_sz > 0) {
                const ptr = mmap(null, map_sz, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
                if (ptr != null and @intFromPtr(ptr) != MAP_FAILED) {
                    // Unmap old DMA-BUF vidp if any
                    const old_fd = off.Hidden.getDmabufVidpFd(private);
                    if (old_fd >= 0) {
                        const old_ptr = off.Hidden.getDmabufVidpPtr(private);
                        const old_sz = off.Hidden.getDmabufVidpMapSz(private);
                        if (old_ptr != null and old_sz > 0)
                            _ = munmap(old_ptr, old_sz);
                        _ = close(old_fd);
                    }

                    // Store DMA-BUF state and replace vidp
                    off.Hidden.setDmabufVidpFd(private, fd);
                    off.Hidden.setDmabufVidpPtr(private, ptr);
                    off.Hidden.setDmabufVidpMapSz(private, map_sz);
                    off.Hidden.setDmabufVidpStride(private, stride);
                    cont.unnamed_0.vidp = @ptrCast(@alignCast(ptr));
                } else {
                    _ = close(fd);
                }
            } else {
                _ = close(fd);
            }
        }
        off.Hidden.setPevFd(private, 0, BADFD);
        return true; // consumed, don't forward to user
    }
    // this event can swap out store access handle for sensitive material
    else if (dst.category().* == c.EVENT_TARGET and
        dst.tgt().kind == c.TARGET_COMMAND_DEVICE_NODE and
        dst.tgt().ioevs[3].iv == 3)
    {
        if (off.Hidden.getKeystateStore(private) != 0)
            _ = close(off.Hidden.getKeystateStore(private));

        off.Hidden.setKeystateStore(private,
            shmifint_privsep_mark_fd(off.Hidden.getPevFd(private, 0), c.MARK_KEYSTORE));
        off.Hidden.setAutoclean(private, true);
        off.Hidden.setPevFd(private, 0, BADFD);
        return true;
    }
    // otherwise we have a normal pending slot with a descriptor
    else {
        dst.tgt().ioevs[0].iv =
            shmifint_privsep_mark_fd(off.Hidden.getPevFd(private, 0), event_to_fdmode(dst));
    }

    return false;
}

// fetch_check

fn fetch_check(t: ?*anyopaque) callconv(.c) bool {
    return shmif_platform_check_alive(@ptrCast(@alignCast(t)));
}

// shmifint_consume_pending

export fn shmifint_consume_pending(cont: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const C = cont orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(C.priv));

    if (!off.Hidden.getPevConsumed(P))
        return;

    // H10 probe: log pev.fds[0] and pev.fds[1] values at entry. If fds[1]
    // is ever non-BADFD here, a coalesced SCM_RIGHTS orphaned it.
    {
        const sc_open = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
        const sc_fprintf = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
        const sc_fclose = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
        const sc_getpid = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
        if (sc_open("/tmp/arcan_shmif_trace.log", "a")) |f| {
            _ = sc_fprintf(f, "[%d] consume_pending ENTRY fds[0]=%d fds[1]=%d pseg_epipe=%d\n",
                sc_getpid(), off.Hidden.getPevFd(P, 0), off.Hidden.getPevFd(P, 1),
                off.Hidden.getPsegEpipe(P));
            _ = sc_fclose(f);
        }
    }

    if (BADFD != off.Hidden.getPsegEpipe(P)) {
        // Check for accessibility subsegment
        if (off.Hidden.getPevGotev(P) and
            pevEvPtr(P).category().* == c.EVENT_TARGET and
            pevEvPtr(P).tgt().kind == c.TARGET_COMMAND_NEWSEGMENT and
            pevEvPtr(P).tgt().ioevs[2].iv == @as(i32, @intCast(c.SEGID_ACCESSIBILITY)))
        {
            var pcont = arcan_shmif_acquire(C, null, c.SEGID_ACCESSIBILITY, 0);
            if (pcont.addr != null) {
                if (!arcan_shmif_a11yint_spawn(&pcont, C))
                    arcan_shmif_drop(&pcont);
                return;
            }
        }

        _ = close(off.Hidden.getPsegEpipe(P));
        off.Hidden.setPsegEpipe(P, BADFD);
    }

    if (BADFD != off.Hidden.getPevFd(P, 0)) {
        _ = close(off.Hidden.getPevFd(P, 0));
    }

    if (BADFD != off.Hidden.getPevFd(P, 1)) {
        _ = close(off.Hidden.getPevFd(P, 1));
    }

    off.Hidden.setPevFd(P, 0, BADFD);
    off.Hidden.setPevFd(P, 1, BADFD);
    off.Hidden.setPevGotev(P, false);
    off.Hidden.setPevConsumed(P, false);
    off.Hidden.setPevHandedover(P, false);
}

// pause_evh

fn pause_evh(
    cont: *c.struct_arcan_shmif_cont,
    priv: *anyopaque,
    ev: *c.arcan_event,
) bool {
    if (ev.category().* != c.EVENT_TARGET)
        return true;

    var rv: bool = true;
    const kind = ev.tgt().kind;

    if (kind == c.TARGET_COMMAND_UNPAUSE or
        kind == c.TARGET_COMMAND_RESET)
    {
        off.Hidden.setPaused(priv, false);
    } else if (kind == c.TARGET_COMMAND_EXIT) {
        off.Hidden.setAlive(priv, false);
        rv = false;
    } else if (kind == c.TARGET_COMMAND_DISPLAYHINT) {
        _ = merge_dh(ev, dhPtr(priv));
        dhPtr(priv).* = ev.*;
        off.Hidden.setPh(priv, off.Hidden.getPh(priv) | 1);
    } else if (kind == c.TARGET_COMMAND_FONTHINT) {
        fhPtr(priv).category().* = @intCast(c.EVENT_TARGET);
        fhPtr(priv).tgt().kind = c.TARGET_COMMAND_FONTHINT;

        // received event while one already pending? don't leak descriptor
        if (ev.tgt().ioevs[1].iv != 0) {
            if (fhPtr(priv).tgt().ioevs[0].iv != BADFD)
                _ = close(fhPtr(priv).tgt().ioevs[0].iv);
            _ = shmif_platform_fetchfds(
                cont.epipe,
                @ptrCast(&fhPtr(priv).tgt().ioevs[0].iv),
                1,
                true,
                &fetch_check,
                @ptrCast(cont),
            );
        }

        if (ev.tgt().ioevs[2].fv > 0.0)
            fhPtr(priv).tgt().ioevs[2].fv = ev.tgt().ioevs[2].fv;
        if (ev.tgt().ioevs[3].iv > -1)
            fhPtr(priv).tgt().ioevs[3].iv = ev.tgt().ioevs[3].iv;

        // set the bit to indicate we need to return this event
        off.Hidden.setPh(priv, off.Hidden.getPh(priv) | 2);
    }

    return rv;
}

// shmifint_process_events

export fn shmifint_process_events(
    cont: ?*c.struct_arcan_shmif_cont,
    dst_ptr: ?*c.arcan_event,
    blocking: bool,
    upret: bool,
) c_int {
    if (is_freestanding) return 0;
    const C = cont orelse return -1;
    const dst = dst_ptr orelse return -1;

    // labeled block to simulate goto reset
    // We use an outer loop for the "reset" label and inner labeled blocks
    // for "checkfd" and "done"
    var noks: bool = false;
    var rv: c_int = 0;

    reset_loop: while (true) {
        if (C.addr == null) {
            evdbg("[pe] addr=null, ret -1\n");
            return -1;
        }

        const P: *anyopaque = @ptrCast(@alignCast(C.priv));
        const ctx: *c.struct_arcan_evctx = inevPtr(P);
        noks = false;
        rv = 0;

        // we have a RESET delay-slot:ed, that takes priority
        if ((off.Hidden.getPh(P) & 4) != 0) {
            dst.* = fhPtr(P).*;
            off.Hidden.setPaused(P, false);
            rv = 1;
            off.Hidden.setPh(P, 0);
            // goto done
            return if (shmif_platform_check_alive(C) or noks) rv else -1;
        }

        {
            const hook_raw = off.Hidden.getSupportWindowHook(P);
            if (hook_raw) |h| {
                const hook: *const fn (*c.struct_arcan_shmif_cont, c_int) callconv(.c) void = @ptrCast(@alignCast(h));
                hook(C, @intCast(c.SUPPORT_EVENT_POLL));
            }
        }

        // Select few events has a special queue position and can be delivered
        // 'out of order' from normal affairs
        if (!off.Hidden.getPaused(P) and off.Hidden.getPh(P) != 0) {
            if ((off.Hidden.getPh(P) & 1) != 0) {
                off.Hidden.setPh(P, off.Hidden.getPh(P) & ~@as(c_int, 1));
                dst.* = dhPtr(P).*;
                rv = 1;
                return if (shmif_platform_check_alive(C) or noks) rv else -1;
            } else if ((off.Hidden.getPh(P) & 2) != 0) {
                dst.* = fhPtr(P).*;
                off.Hidden.setPevConsumed(P, dst.tgt().ioevs[0].iv != BADFD);
                off.Hidden.setPevFd(P, 0, dst.tgt().ioevs[0].iv);
                off.Hidden.setPh(P, off.Hidden.getPh(P) & ~@as(c_int, 2));
                rv = 1;
                return if (shmif_platform_check_alive(C) or noks) rv else -1;
            } else {
                off.Hidden.setPh(P, 0);
                rv = 1;
                dst.* = fhPtr(P).*;
                return if (shmif_platform_check_alive(C) or noks) rv else -1;
            }
        }

        // clean up any pending descriptors
        shmifint_consume_pending(C);

        // checkfd: fetchfd also pumps 'got event' pings
        evdbg("[pe] entering checkfd_loop\n");
        var checkfd_done = false;
        checkfd_loop: while (!checkfd_done) {
            std.c._errno().* = 0;
            if (BADFD == off.Hidden.getPevFd(P, 0)) {
                evdbg("[pe] calling fetchfds\n");
                _ = shmif_platform_fetchfds(
                    C.epipe,
                    @as([*c]c_int, @ptrCast(off.Hidden.getPevFdsPtr(P))),
                    2,
                    blocking,
                    &fetch_check,
                    @ptrCast(C),
                );
            }

            if (off.Hidden.getPevGotev(P)) {
                if (off.Hidden.getPevFd(P, 0) != BADFD) {
                    if (fd_event(C, dst) and off.Hidden.getAutoclean(P)) {
                        off.Hidden.setAutoclean(P, false);
                        shmifint_consume_pending(C);
                    } else {
                        rv = 1;
                    }
                } else if (blocking) {
                    const err = std.c._errno().*;
                    if (err == 0 or err == EAGAIN) {
                        continue :checkfd_loop;
                    }
                }

                // goto done
                return if (shmif_platform_check_alive(C) or noks) rv else -1;
            }

            // do-while condition: P->pev.gotev && shmif_platform_check_alive(c)
            if (off.Hidden.getPevGotev(P) and shmif_platform_check_alive(C)) {
                continue :checkfd_loop;
            }
            checkfd_done = true;
        }

        // atomic increment of front -> event enqueued
        evdbg("[pe] checkfd done, checking event queue\n");
        const front_val = @as(*volatile u8, @ptrCast(ctx.front)).*;
        // Acquire-ordered load of back pairs with the parent's seq_cst
        // FORCE_SYNCH between the event memcpy and the back_ptr advance in
        // platform_fsrv_pushevent. Without this on aarch64 the child can
        // observe the updated back pointer before the event bytes have been
        // published, reading a stale/zero slot.
        const back_val = @atomicLoad(u8, @as(*volatile u8, @ptrCast(ctx.back)), .acquire);

        if (front_val != back_val) {
            {
                const cat = ctx.eventbuf[front_val].category().*;
                const kind = ctx.eventbuf[front_val].tgt().kind;
                var buf: [64]u8 = undefined;
                _ = snprintf(&buf, 64, "[pe] event cat=%d kind=%d\n", @as(c_int, cat), @as(c_int, @bitCast(kind)));
                evdbg(&buf);
            }
            dst.* = ctx.eventbuf[front_val];

            // memset to 0xff for easier visibility on debugging
            _ = memset(
                @as(?*anyopaque, @ptrCast(&ctx.eventbuf[front_val])),
                0xff,
                @sizeOf(c.arcan_event),
            );
            @as(*volatile u8, @ptrCast(ctx.front)).* = (front_val + 1) % ctx.eventbuf_sz;
            {
                const f_open_ex = @extern(*const fn ([*c]const u8, [*c]const u8) callconv(.c) ?*anyopaque, .{ .name = "fopen" });
                const f_printf_ex = @extern(*const fn (?*anyopaque, [*c]const u8, ...) callconv(.c) c_int, .{ .name = "fprintf" });
                const f_close_ex = @extern(*const fn (?*anyopaque) callconv(.c) c_int, .{ .name = "fclose" });
                const getpid_ex = @extern(*const fn () callconv(.c) c_int, .{ .name = "getpid" });
                if (f_open_ex("/tmp/arcan_shmif_trace.log", "a")) |fd| {
                    _ = f_printf_ex(fd, "[%d] child incremented front: was=%d now=%d shm_front_addr=%p\n",
                        getpid_ex(), @as(c_int, @intCast(front_val)),
                        @as(c_int, @intCast(@as(*volatile u8, @ptrCast(ctx.front)).*)),
                        ctx.front);
                    _ = f_close_ex(fd);
                }
            }

            // Unless mask is set, paused won't be changed
            if (off.Hidden.getPaused(P)) {
                if (pause_evh(C, P, dst))
                    continue :reset_loop;
                rv = 1;
                noks = dst.category().* == c.EVENT_TARGET and
                    dst.tgt().kind == c.TARGET_COMMAND_EXIT;
                return if (shmif_platform_check_alive(C) or noks) rv else -1;
            }

            if (dst.category().* == c.EVENT_TARGET) {
                const kind = dst.tgt().kind;

                if (kind == c.TARGET_COMMAND_DISPLAYHINT) {
                    if (!off.Hidden.getValidInitial(P) and scan_display_event(ctx, dst))
                        continue :reset_loop;
                } else if (kind == c.TARGET_COMMAND_STEPFRAME) {
                    if (scan_stepframe_event(ctx, dst, 2) or scan_stepframe_event(ctx, dst, 3))
                        continue :reset_loop;
                } else if (kind == c.TARGET_COMMAND_PAUSE) {
                    if ((off.Hidden.getFlags(P) & c.SHMIF_MANUAL_PAUSE) == 0) {
                        off.Hidden.setPaused(P, true);
                        continue :reset_loop;
                    }
                } else if (kind == c.TARGET_COMMAND_UNPAUSE) {
                    if ((off.Hidden.getFlags(P) & c.SHMIF_MANUAL_PAUSE) == 0) {
                        if (upret)
                            return 0;
                        off.Hidden.setPaused(P, false);
                        continue :reset_loop;
                    }
                } else if (kind == c.TARGET_COMMAND_BUFFER_FAIL) {
                    if (C.privext) |pext| {
                        pext.state_fl = @intCast(c.STATE_NOACCEL);
                    }
                    continue :reset_loop;
                } else if (kind == c.TARGET_COMMAND_EXIT) {
                    off.Hidden.setAlive(P, false);
                    noks = true;
                } else if (kind == c.TARGET_COMMAND_FONTHINT) {
                    if (dst.tgt().ioevs[1].iv == 1) {
                        pevEvPtr(P).* = dst.*;
                        off.Hidden.setPevGotev(P, true);
                        // goto checkfd - restart the inner loop
                        checkfd_done = false;
                        var checkfd_inner = false;
                        checkfd_inner_loop: while (!checkfd_inner) {
                            std.c._errno().* = 0;
                            if (BADFD == off.Hidden.getPevFd(P, 0)) {
                                _ = shmif_platform_fetchfds(
                                    C.epipe,
                                    @as([*c]c_int, @ptrCast(off.Hidden.getPevFdsPtr(P))),
                                    2,
                                    blocking,
                                    &fetch_check,
                                    @ptrCast(C),
                                );
                            }
                            if (off.Hidden.getPevGotev(P)) {
                                if (off.Hidden.getPevFd(P, 0) != BADFD) {
                                    if (fd_event(C, dst) and off.Hidden.getAutoclean(P)) {
                                        off.Hidden.setAutoclean(P, false);
                                        shmifint_consume_pending(C);
                                    } else {
                                        rv = 1;
                                    }
                                } else if (blocking) {
                                    const err = std.c._errno().*;
                                    if (err == 0 or err == EAGAIN) {
                                        continue :checkfd_inner_loop;
                                    }
                                }
                                return if (shmif_platform_check_alive(C) or noks) rv else -1;
                            }
                            if (off.Hidden.getPevGotev(P) and shmif_platform_check_alive(C)) {
                                continue :checkfd_inner_loop;
                            }
                            checkfd_inner = true;
                        }
                        // fell through checkfd without returning, continue to done
                        return if (shmif_platform_check_alive(C) or noks) rv else -1;
                    } else {
                        dst.tgt().ioevs[0].iv = BADFD;
                    }
                } else if (kind == c.TARGET_COMMAND_DEVICE_NODE) {
                    const iev = dst.tgt().ioevs[1].iv;

                    if (iev == 4) {
                        // replace slot with message, never forward
                        const ac = off.Hidden.getAltConn(P);
                        if (ac != null) {
                            free(@as(?*anyopaque, @ptrCast(ac)));
                            off.Hidden.setAltConn(P, null);
                        }

                        // if we're provided with a guid, keep it
                        var guid: [2]u64 = undefined;
                        guid[0] = @as(u64, dst.tgt().ioevs[2].uiv) |
                            (@as(u64, dst.tgt().ioevs[3].uiv) << 32);
                        guid[1] = @as(u64, dst.tgt().ioevs[4].uiv) |
                            (@as(u64, dst.tgt().ioevs[5].uiv) << 32);

                        if ((guid[0] != 0 or guid[1] != 0) and
                            (off.Hidden.getGuid(P, 0) != guid[0] and off.Hidden.getGuid(P, 1) != guid[1]))
                        {
                            off.Hidden.setGuid(P, 0, guid[0]);
                            off.Hidden.setGuid(P, 1, guid[1]);
                        }

                        const msg_ptr: [*c]const u8 = @ptrCast(&dst.tgt().message());
                        if (msg_ptr[0] != 0)
                            off.Hidden.setAltConn(P, strdup(msg_ptr));

                        continue :reset_loop;
                    } else if (iev == 1) {
                        if (dst.tgt().ioevs[3].iv == 3) {
                            pevEvPtr(P).* = dst.*;
                            off.Hidden.setPevGotev(P, true);
                            // goto checkfd via inner loop
                            return doCheckFd(C, P, dst, blocking, noks);
                        }
                    } else if (iev > 1 and iev <= 3) {
                        const msg_ptr: [*c]const u8 = @ptrCast(&dst.tgt().message());
                        if (msg_ptr[0] == 0) {
                            pevEvPtr(P).* = dst.*;
                            off.Hidden.setPevGotev(P, true);
                            return doCheckFd(C, P, dst, blocking, noks);
                        } else {
                            if (shmif_platform_fallback(C, msg_ptr, false) != c.SHMIF_MIGRATE_OK) {
                                rv = 0;
                                return if (shmif_platform_check_alive(C) or noks) rv else -1;
                            } else {
                                continue :reset_loop;
                            }
                        }
                    } else if (iev == 6) {
                        // Compositor-allocated DMA-BUF vidp: receive fd, mmap, replace vidp.
                        // Forward through doCheckFd to receive paired descriptor.
                        pevEvPtr(P).* = dst.*;
                        off.Hidden.setPevGotev(P, true);
                        return doCheckFd(C, P, dst, blocking, noks);
                    } else {
                        continue :reset_loop;
                    }
                } else if (kind == c.TARGET_COMMAND_NEWSEGMENT) {
                    off.Hidden.setAutoclean(P, (dst.tgt().ioevs[5].iv != 0));
                    // fallthrough to descriptor-waiting events
                    off.Hidden.setPevGotev(P, true);
                    pevEvPtr(P).* = dst.*;
                    return doCheckFd(C, P, dst, blocking, noks);
                } else if (kind == c.TARGET_COMMAND_STORE or
                    kind == c.TARGET_COMMAND_RESTORE or
                    kind == c.TARGET_COMMAND_BCHUNK_IN or
                    kind == c.TARGET_COMMAND_BCHUNK_OUT)
                {
                    off.Hidden.setPevGotev(P, true);
                    pevEvPtr(P).* = dst.*;
                    return doCheckFd(C, P, dst, blocking, noks);
                }
            }

            rv = 1;
        }
        // a successful migrate will delay-slot the RESET event
        else if (!shmif_platform_check_alive(C)) {
            evdbg("[pe] no events, check_alive=false\n");
            if (shmif_platform_fallback(C, off.Hidden.getAltConn(P), true) == c.SHMIF_MIGRATE_OK)
                continue :reset_loop;
            evdbg("[pe] fallback failed, returning\n");
            return if (shmif_platform_check_alive(C) or noks) rv else -1;
        }
        // Need to constantly pump the event socket for incoming descriptors
        else if (blocking and shmif_platform_check_alive(C)) {
            evdbg("[pe] no events, blocking+alive, re-entering loop\n");
            continue :reset_loop;
        }

        // done
        return if (shmif_platform_check_alive(C) or noks) rv else -1;
    }

    // unreachable, but satisfy return
    return -1;
}

// doCheckFd helper (simulates goto checkfd -> done)

fn doCheckFd(
    C: *c.struct_arcan_shmif_cont,
    P: *anyopaque,
    dst: *c.arcan_event,
    blocking: bool,
    noks_in: bool,
) c_int {
    var rv: c_int = 0;

    // checkfd loop
    while (true) {
        std.c._errno().* = 0;
        if (BADFD == off.Hidden.getPevFd(P, 0)) {
            _ = shmif_platform_fetchfds(
                C.epipe,
                @as([*c]c_int, @ptrCast(off.Hidden.getPevFdsPtr(P))),
                2,
                blocking,
                &fetch_check,
                @ptrCast(C),
            );
        }

        if (off.Hidden.getPevGotev(P)) {
            if (off.Hidden.getPevFd(P, 0) != BADFD) {
                if (fd_event(C, dst) and off.Hidden.getAutoclean(P)) {
                    off.Hidden.setAutoclean(P, false);
                    shmifint_consume_pending(C);
                } else {
                    rv = 1;
                }
            } else if (blocking) {
                const err = std.c._errno().*;
                if (err == 0 or err == EAGAIN)
                    continue;
            }

            return if (shmif_platform_check_alive(C) or noks_in) rv else -1;
        }

        // do-while condition
        if (off.Hidden.getPevGotev(P) and shmif_platform_check_alive(C)) {
            continue;
        }
        break;
    }

    return if (shmif_platform_check_alive(C) or noks_in) rv else -1;
}
