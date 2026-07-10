// Zig reimplementation of platform/migrate.c
// Drop-in C-ABI-compatible replacement for migration / fallback functions.
//
// Exports: shmif_platform_fallback
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

const BADFD = c.BADFD;

// Extern C declarations

extern fn arcan_shmif_migrate(
    cont: *c.struct_arcan_shmif_cont,
    cpoint: [*c]const u8,
    key: [*c]const u8,
) c.enum_shmif_migrate_status;

extern fn arcan_shmif_resolve_connpath(
    cpoint: [*c]const u8,
    dbuf: [*c]u8,
    dbuf_sz: usize,
) c_int;

extern fn shmif_platform_check_alive(cont: *c.struct_arcan_shmif_cont) bool;
extern fn arcan_timesleep(ms: c_ulong) void;
extern fn free(ptr: ?*anyopaque) void;
extern fn close(fd: c_int) c_int;
extern fn strlen(s: [*c]const u8) usize;
extern fn strncmp(a: [*c]const u8, b: [*c]const u8, n: usize) c_int;
extern fn strdup(s: [*c]const u8) [*c]u8;

// Linux inotify declarations
extern fn inotify_init1(flags: c_int) c_int;
extern fn inotify_add_watch(fd: c_int, pathname: [*c]const u8, mask: u32) c_int;
extern fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;

const IN_CLOEXEC = 0x80000;
const IN_CREATE = 0x00000100;

// notify_wait (Linux only)

fn notify_wait(cpoint: [*c]const u8) bool {
    if (comptime builtin.os.tag != .linux)
        return false;

    var buf: [256]u8 = undefined;
    const len = arcan_shmif_resolve_connpath(cpoint, &buf, 256);
    if (len <= 0)
        return false;

    // path in abstract namespace or non-absolute
    if (buf[0] != '/')
        return false;

    // strip down to the directory path
    var pos: usize = @intCast(len);
    while (pos > 0 and buf[pos] != '/') {
        pos -= 1;
    }

    if (pos == 0)
        return false;

    buf[pos] = 0;

    const notify = inotify_init1(IN_CLOEXEC);
    if (notify == -1)
        return false;

    if (inotify_add_watch(notify, &buf, IN_CREATE) == -1) {
        _ = close(notify);
        return false;
    }

    // just wait for something, the path shouldn't be particularly active
    // inotify_event is at least 16 bytes
    var ev_buf: [256]u8 = undefined;
    _ = read(notify, @ptrCast(&ev_buf), @sizeOf([256]u8));

    _ = close(notify);
    return true;
}

// scan_exit_event

fn scan_exit_event(ctx: *c.struct_arcan_evctx) bool {
    var cur: u8 = @as(*volatile u8, @ptrCast(ctx.front)).*;
    const back: u8 = @as(*volatile u8, @ptrCast(ctx.back)).*;

    while (cur != back) {
        const ev: *c.arcan_event = @ptrCast(&ctx.eventbuf[cur]);
        if (ev.category().* == c.EVENT_TARGET and
            ev.tgt().kind == c.TARGET_COMMAND_EXIT)
            return true;

        cur = (cur + 1) % ctx.eventbuf_sz;
    }

    return false;
}

// scan_device_node_event

fn scan_device_node_event(P: *anyopaque, ctx: *c.struct_arcan_evctx) void {
    var cur: u8 = @as(*volatile u8, @ptrCast(ctx.front)).*;
    const back: u8 = @as(*volatile u8, @ptrCast(ctx.back)).*;

    while (cur != back) {
        const ev: *c.arcan_event = @ptrCast(&ctx.eventbuf[cur]);
        if (ev.category().* == c.EVENT_TARGET and
            ev.tgt().kind == c.TARGET_COMMAND_DEVICE_NODE and
            ev.tgt().ioevs[1].iv == 4) // set alt-conn
        {
            const ac = off.Hidden.getAltConn(P);
            if (ac != null) {
                free(@as(?*anyopaque, @ptrCast(ac)));
            }
            off.Hidden.setAltConn(P, null);
            const msg_ptr: [*c]const u8 = @ptrCast(&ev.tgt().message());
            if (msg_ptr[0] != 0) {
                off.Hidden.setAltConn(P, strdup(msg_ptr));
            }
        }
        cur = (cur + 1) % ctx.eventbuf_sz;
    }
}

// shmif_platform_fallback

export fn shmif_platform_fallback(
    C: ?*c.struct_arcan_shmif_cont,
    cpoint: [*c]const u8,
    force: bool,
) c.enum_shmif_migrate_status {
    if (is_freestanding) return 0;
    const cont = C orelse return c.SHMIF_MIGRATE_NOCON;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));
    const oldfd = cont.epipe;

    const inev: *c.struct_arcan_evctx = @ptrCast(@alignCast(off.Hidden.getInevPtr(P)));

    // we are actually told to exit, so collapse back to eventloop
    if (scan_exit_event(inev))
        return c.SHMIF_MIGRATE_NOCON;

    // there might be a newer altcon in the queue as well, so check that first
    scan_device_node_event(P, inev);

    // parent can pull dms explicitly
    if (force) {
        if (((off.Hidden.getFlags(P) & c.SHMIF_NOAUTO_RECONNECT) != 0) or
            shmif_platform_check_alive(cont) or off.Hidden.getOutput(P))
            return c.SHMIF_MIGRATE_NOCON;
    }

    // CONNECT_LOOP style behavior on force
    var current: [*c]const u8 = cpoint;
    if (current == null)
        return c.SHMIF_MIGRATE_NOCON;

    var sv: c.enum_shmif_migrate_status = undefined;

    sv = arcan_shmif_migrate(cont, current, null);
    while (sv == c.SHMIF_MIGRATE_NOCON) {
        if (!force)
            break;

        // try to return to the last known connection point after a few tries
        if (current == cpoint and off.Hidden.getAltConn(P) != null) {
            current = off.Hidden.getAltConn(P);
        } else {
            current = cpoint;
        }

        // if there is a poll mechanism to use, go for it
        if (comptime builtin.os.tag == .linux) {
            if (!(strlen(cpoint) > 6 and
                strncmp(cpoint, "a12://", 6) == 0) and notify_wait(cpoint))
            {
                sv = arcan_shmif_migrate(cont, current, null);
                continue;
            }
        }
        arcan_timesleep(100);

        sv = arcan_shmif_migrate(cont, current, null);
    }

    const fh: *c.arcan_event = @ptrCast(@alignCast(off.Hidden.getFhPtr(P)));

    switch (sv) {
        c.SHMIF_MIGRATE_NOCON => {},
        c.SHMIF_MIGRATE_BAD_SOURCE => {
            return sv;
        },
        c.SHMIF_MIGRATE_BADARG => {},
        c.SHMIF_MIGRATE_TRANSFER_FAIL => {},
        c.SHMIF_MIGRATE_OK => {
            if ((off.Hidden.getPh(P) & 2) != 0) {
                if (fh.tgt().ioevs[0].iv != BADFD) {
                    _ = close(fh.tgt().ioevs[0].iv);
                    fh.tgt().ioevs[0].iv = BADFD;
                    off.Hidden.setPh(P, 0);
                }
            }

            off.Hidden.setPh(P, off.Hidden.getPh(P) | 4);
            fh.* = c.arcan_event.zeroes();
            fh.category().* = c.EVENT_TARGET;
            fh.tgt().kind = c.TARGET_COMMAND_RESET;
            fh.tgt().ioevs[0].iv = 3;
            fh.tgt().ioevs[1].iv = oldfd;
        },
        else => {},
    }

    return sv;
}
