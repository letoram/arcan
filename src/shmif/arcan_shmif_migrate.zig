// Zig reimplementation of arcan_shmif_migrate.c
// Drop-in C-ABI-compatible replacement for migration functions.
//
// Exports: arcan_shmif_migrate
//
const std = @import("std");
const off = @import("shmif_offsets");
const builtin = @import("builtin");
const c = @import("shmif_types");

// Extern C declarations

extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*c]const u8) [*c]u8;
extern "c" fn memcpy(noalias dst: ?*anyopaque, noalias src: ?*const anyopaque, n: usize) ?*anyopaque;
extern "c" fn close(fd: c_int) c_int;
extern "c" fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
extern "c" fn fcntl(fd: c_int, cmd: c_int, ...) c_int;

extern "c" fn mmap(addr: ?*anyopaque, length: usize, prot: c_int, flags: c_int, fd: c_int, offset: i64) ?*anyopaque;
extern "c" fn munmap(addr: ?*anyopaque, length: usize) c_int;

extern "c" fn pthread_self() c.pthread_t;
extern "c" fn pthread_equal(t1: c.pthread_t, t2: c.pthread_t) c_int;

// musl defines pthread_t as ?*struct___pthread (pointer), glibc as unsigned long (usize).
fn usizeToPthread(v: usize) c.pthread_t {
    return if (@typeInfo(c.pthread_t) == .pointer or @typeInfo(c.pthread_t) == .optional)
        @ptrFromInt(v)
    else
        @intCast(v);
}

extern "c" fn arcan_shmif_connect(connpath: [*c]const u8, connkey: [*c]const u8, conn_ch: *c_int) [*c]u8;
extern "c" fn arcan_shmif_acquire(parent: ?*c.struct_arcan_shmif_cont, shmkey: [*c]const u8, seg_type: c_int, flags: c_int) c.struct_arcan_shmif_cont;
extern "c" fn arcan_shmif_enqueue(ctx: *c.struct_arcan_shmif_cont, ev: *c.arcan_event) c_int;
extern "c" fn arcan_shmif_resize_ext(arg: *c.struct_arcan_shmif_cont, width: c_uint, height: c_uint, ext: c.struct_shmif_resize_ext) bool;
extern "c" fn arcan_shmif_drop(C: *c.struct_arcan_shmif_cont) void;
extern "c" fn arcan_shmif_vbufsz(atype: c_int, hints: u8, w: usize, h: usize, rows: usize, cols: usize) usize;
extern "c" fn arcan_shmif_mapav(page: ?*anyopaque, vbuf: [*c]?*c.shmif_pixel, vbufc: u8, vbufsz: usize, abuf: [*c]?*c.shmif_asample, abufc: u8, abufsz: usize) void;

extern "c" fn shmif_platform_a12addr(addr: [*c]const u8) c.struct_a12addr_info;
extern "c" fn shmif_platform_a12spawn(cont: *c.struct_arcan_shmif_cont, addr: [*c]const u8, dsock: *c_int) [*c]u8;
extern "c" fn shmif_platform_setevqs(page: ?*anyopaque, sem: ?*anyopaque, inevq: *c.struct_arcan_evctx, outevq: *c.struct_arcan_evctx) void;
extern "c" fn shmif_platform_sync_post(page: ?*anyopaque, slot: c_int) c_int;
extern "c" fn shmif_platform_guard_lock(cont: *c.struct_arcan_shmif_cont) void;
extern "c" fn shmif_platform_guard_unlock(cont: *c.struct_arcan_shmif_cont) void;
extern "c" fn shmif_platform_guard_resynch(cont: *c.struct_arcan_shmif_cont, parent_pid: c_int, parent_fd: c_int) void;
extern "c" fn shmif_platform_log_device(cont: ?*c.struct_arcan_shmif_cont) *anyopaque;
// BUG-S17: use shmif_log_stderr (write(2)) instead of fprintf(logdev) to avoid GOT relaxation crash
extern "c" fn shmif_log_stderr(fmt: [*c]const u8, ...) void;

// Inline helpers for casting offset-based pointers to C types
const ResetHookFn = *const fn (c_int, ?*anyopaque) callconv(.c) void;

inline fn castResetHook(raw: ?*anyopaque) ?ResetHookFn {
    return if (raw) |p| @ptrCast(@alignCast(p)) else null;
}

inline fn castEvctx(raw: *anyopaque) *c.struct_arcan_evctx {
    return @ptrCast(@alignCast(raw));
}

// Constants

const PROT_READ: c_int = 0x1;
const PROT_WRITE: c_int = 0x2;
const MAP_SHARED: c_int = 0x01;
const FD_CLOEXEC: c_int = 1;
const F_SETFD: c_int = 2;
const F_GETFD: c_int = 1;

// arcan_shmif_migrate

export fn arcan_shmif_migrate(
    C: ?*c.struct_arcan_shmif_cont,
    newpath: [*c]const u8,
    key: [*c]const u8,
) c.enum_shmif_migrate_status {
    const cont = C orelse return c.SHMIF_MIGRATE_BADARG;
    if (cont.addr == null or newpath == null) return c.SHMIF_MIGRATE_BADARG;

    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (pthread_equal(usizeToPthread(off.Hidden.getPrimaryId(P)), pthread_self()) == 0)
        return c.SHMIF_MIGRATE_BAD_SOURCE;

    var dpipe: c_int = undefined;
    var keyfile: [*c]u8 = null;

    if (shmif_platform_a12addr(newpath).len != -1) {
        keyfile = shmif_platform_a12spawn(cont, newpath, &dpipe);
    } else {
        keyfile = arcan_shmif_connect(newpath, key, &dpipe);
    }
    if (keyfile == null) return c.SHMIF_MIGRATE_NOCON;

    // re-use tracked old credentials
    _ = fcntl(dpipe, F_SETFD, FD_CLOEXEC);
    var NEW = arcan_shmif_acquire(null, keyfile, off.Hidden.getType(P), off.Hidden.getFlags(P));

    if (NEW.addr == null) {
        _ = close(dpipe);
        return c.SHMIF_MIGRATE_NOCON;
    }
    NEW.epipe = dpipe;

    // all preconditions GO
    off.Hidden.setInMigrate(P, true);
    shmif_platform_guard_resynch(cont, -1, dpipe);

    // REGISTER is special, as GUID can be internally generated but should persist
    if (off.Hidden.getFlags(P) & c.SHMIF_NOREGISTER != 0) {
        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.category().* = @intCast(c.EVENT_EXTERNAL);
        ev.ext().kind = c.EVENT_EXTERNAL_REGISTER;
        ev.ext().registr().kind = @intCast(off.Hidden.getType(P));
        ev.ext().registr().guid[0] = off.Hidden.getGuid(P, 0);
        ev.ext().registr().guid[1] = off.Hidden.getGuid(P, 1);
        _ = arcan_shmif_enqueue(&NEW, &ev);
    }

    // allow a reset-hook to release anything pending
    if (castResetHook(off.Hidden.getResetHook(P))) |rh|
        rh(@as(c_int, @intCast(c.SHMIF_RESET_REMAP)), off.Hidden.getResetHookTag(P));

    // extract settings from the page and context
    const w: c_uint = @intCast(cont.w);
    const h: c_uint = @intCast(cont.h);

    var ext: c.struct_shmif_resize_ext = std.mem.zeroes(c.struct_shmif_resize_ext);
    ext.abuf_sz = cont.abufsize;
    ext.vbuf_cnt = @intCast(off.Hidden.getVbufCnt(P));
    ext.abuf_cnt = @intCast(off.Hidden.getAbufCnt(P));
    ext.samplerate = @intCast(cont.samplerate);
    ext.meta = @intCast(off.Hidden.getAtype(P));
    ext.rows = off.Page.getRows(cont.addr.?);
    ext.cols = off.Page.getCols(cont.addr.?);

    // Copy hints and resize the new context
    NEW.hints = cont.hints;
    const resize_ok = arcan_shmif_resize_ext(&NEW, w, h, ext);

    // wake anything possibly blocking
    _ = shmif_platform_sync_post(cont.addr, @intCast(c.SYNC_EVENT | c.SYNC_AUDIO | c.SYNC_VIDEO));

    // Copy A/V contents (only if resize succeeded — otherwise NEW has default-sized buffers)
    const NEW_P: *anyopaque = @ptrCast(@alignCast(NEW.priv));

    if (resize_ok) {
        const vbuf_sz_new = arcan_shmif_vbufsz(
            @intCast(off.Hidden.getAtype(NEW_P)),
            NEW.hints,
            NEW.w,
            NEW.h,
            off.Page.getRows(NEW.addr.?),
            off.Page.getCols(NEW.addr.?),
        );

        const vbuf_sz_old = arcan_shmif_vbufsz(
            @intCast(off.Hidden.getAtype(P)),
            cont.hints,
            cont.w,
            cont.h,
            ext.rows,
            ext.cols,
        );

        // safety: ensure vbuf fits within the segment's data area
        const page_sz = off.Page.sizeof_page;
        const data_area = if (NEW.shmsize > page_sz) NEW.shmsize - page_sz else 0;

        if (vbuf_sz_new == vbuf_sz_old and vbuf_sz_new <= data_area) {
            var i: usize = 0;
            while (i < off.Hidden.getVbufCnt(P)) : (i += 1) {
                if (off.Hidden.getVbuf(NEW_P, i)) |dst| {
                    if (off.Hidden.getVbuf(P, i)) |src| {
                        _ = memcpy(@as(?*anyopaque, @ptrCast(dst)), @as(?*const anyopaque, @ptrCast(src)), vbuf_sz_new);
                    }
                }
            }
        } else if (vbuf_sz_new != vbuf_sz_old) {
            shmif_log_stderr("[shmif::recovery] vbuf_sz mismatch (%zu, %zu)\n", vbuf_sz_new, vbuf_sz_old);
            // fill with indicator color
            const color: c.shmif_pixel = c.SHMIF_RGBA(90, 60, 60, 255);
            var row: usize = 0;
            while (row < NEW.h) : (row += 1) {
                if (NEW.unnamed_0.vidp) |vidp| {
                    var col: usize = 0;
                    while (col < NEW.w) : (col += 1) {
                        vidp[row * NEW.pitch + col] = color;
                    }
                }
            }
        }
    }

    // Copy audio buffers (only if resize succeeded)
    if (resize_ok and NEW.abuf_cnt == off.Hidden.getAbufCnt(P) and NEW.abufsize == cont.abufsize) {
        var i: usize = 0;
        while (i < off.Hidden.getAbufCnt(P) and i < off.Hidden.getAbufCnt(NEW_P)) : (i += 1) {
            if (off.Hidden.getAbuf(NEW_P, i)) |dst| {
                if (off.Hidden.getAbuf(P, i)) |src| {
                    _ = memcpy(@as(?*anyopaque, @ptrCast(dst)), @as(?*const anyopaque, @ptrCast(src)), cont.abufsize);
                }
            }
        }
    } else {
        shmif_log_stderr("[shmif::recovery] couldn't restore audio parameters\n");
    }

    // Save state before dropping old context
    const old_page = @intFromPtr(cont.addr);
    const old_user = cont.user;
    const old_hook = off.Hidden.getResetHook(P);
    const old_hook_tag = off.Hidden.getResetHookTag(P);
    const old_hints = cont.hints;
    const old_dirty = cont.dirty;

    // Transfer privext
    NEW.privext = cont.privext;
    const ext_raw = malloc(@sizeOf(c.struct_shmif_ext_hidden)) orelse return c.SHMIF_MIGRATE_NOCON;
    const new_ext: *c.struct_shmif_ext_hidden = @ptrCast(@alignCast(ext_raw));
    cont.privext = new_ext;
    new_ext.* = std.mem.zeroes(c.struct_shmif_ext_hidden);
    new_ext.active_fd = -1;
    new_ext.pending_fd = -1;

    off.Hidden.setInMigrate(P, false);
    arcan_shmif_drop(cont);

    // try to re-use the old mapping
    const alias = mmap(@ptrFromInt(old_page), NEW.shmsize, PROT_READ | PROT_WRITE, MAP_SHARED, NEW.shmh, 0);

    if (@intFromPtr(alias) != old_page) {
        _ = munmap(alias, NEW.shmsize);
    } else {
        // managed to retain old mapping
        _ = munmap(NEW.addr, NEW.shmsize);
        NEW.addr = @ptrCast(@alignCast(alias));

        shmif_platform_guard_lock(&NEW);
        shmif_platform_guard_resynch(&NEW, @intCast(off.Page.getParent(NEW.addr.?)), NEW.epipe);
        shmif_platform_guard_unlock(&NEW);

        arcan_shmif_mapav(
            NEW.addr,
            @ptrCast(off.Hidden.getVbufArrayPtr(NEW_P)),
            off.Hidden.getVbufCnt(NEW_P),
            NEW.w * NEW.h * @sizeOf(c.shmif_pixel),
            @ptrCast(off.Hidden.getAbufArrayPtr(NEW_P)),
            off.Hidden.getAbufCnt(NEW_P),
            NEW.abufsize,
        );

        shmif_platform_setevqs(NEW.addr, null, castEvctx(off.Hidden.getInevPtr(NEW_P)), castEvctx(off.Hidden.getOutevPtr(NEW_P)));

        NEW.unnamed_0.vidp = @ptrCast(@alignCast(off.Hidden.getVbuf(NEW_P, 0)));
        NEW.unnamed_1.audp = @ptrCast(@alignCast(off.Hidden.getAbuf(NEW_P, 0)));
    }

    off.Hidden.setResetHook(NEW_P, old_hook);
    off.Hidden.setResetHookTag(NEW_P, old_hook_tag);

    // Copy the prepared context unto the user-tracked one
    _ = memcpy(
        @as(?*anyopaque, @ptrCast(cont)),
        @as(?*const anyopaque, @ptrCast(&NEW)),
        @sizeOf(c.struct_arcan_shmif_cont),
    );

    cont.hints = old_hints;
    cont.dirty = old_dirty;
    cont.user = old_user;

    // signal the reset hook listener
    if (cont.priv) |priv| {
        const priv_h: *anyopaque = @ptrCast(@alignCast(priv));
        if (castResetHook(off.Hidden.getResetHook(priv_h))) |rh|
            rh(@as(c_int, @intCast(c.SHMIF_RESET_REMAP)), off.Hidden.getResetHookTag(priv_h));
    }

    return c.SHMIF_MIGRATE_OK;
}
