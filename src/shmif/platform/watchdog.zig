// Zig reimplementation of platform/watchdog.c
// Drop-in C-ABI-compatible replacement for watchdog / guard-thread functions.
//
// Exports: shmif_platform_check_alive, shmif_platform_guard_resynch,
//          shmif_platform_guard_lock, shmif_platform_guard_unlock,
//          shmif_platform_guard_release, shmif_platform_guard
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const off = @import("shmif_offsets");
const c = @import("shmif_types");

const BADFD = c.BADFD;

// Extern C declarations

extern fn shmif_platform_sync_post(page: *anyopaque, slot: c_int) c_int;
extern fn kill(pid: c.pid_t, sig: c_int) c_int;
extern fn recv(sockfd: c_int, buf: ?*anyopaque, len: usize, flags: c_int) isize;
extern fn sleep(seconds: c_uint) c_uint;
extern fn shutdown(sockfd: c_int, how: c_int) c_int;
extern fn free(ptr: ?*anyopaque) void;
extern fn getppid() c.pid_t;
extern fn getpid() c.pid_t;

fn dbg(msg: []const u8) void {
    _ = std.posix.write(2, msg) catch {};
}

const pthread_t = c.pthread_t;
const pthread_attr_t = c.pthread_attr_t;

extern fn pthread_mutex_lock(mutex: *anyopaque) c_int;
extern fn pthread_mutex_unlock(mutex: *anyopaque) c_int;
extern fn pthread_mutex_init(mutex: *anyopaque, attr: ?*const anyopaque) c_int;
extern fn pthread_mutex_destroy(mutex: *anyopaque) c_int;
extern fn pthread_create(
    thread: *pthread_t,
    attr: ?*const pthread_attr_t,
    start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    arg: ?*anyopaque,
) c_int;
extern fn pthread_attr_init(attr: *pthread_attr_t) c_int;
extern fn pthread_attr_setdetachstate(attr: *pthread_attr_t, detachstate: c_int) c_int;

const SHUT_RDWR = 2;
const MSG_PEEK = 0x2;
const MSG_DONTWAIT = 0x40;
const EWOULDBLOCK = 11;
const EAGAIN = 11;
const ESRCH = 3;
const PTHREAD_CREATE_DETACHED = 1;
const EXIT_FAILURE = 1;

const SYNC_EVENT = c.SYNC_EVENT;
const SYNC_AUDIO = c.SYNC_AUDIO;
const SYNC_VIDEO = c.SYNC_VIDEO;

const exitf_fn = *const fn (c_int) callconv(.c) void;

// parent_alive

fn parent_alive(gs: *anyopaque, ever_matched: *bool) bool {
    // for authoritative connections, a parent monitoring pid is set
    const parent = off.Hidden.getGuardParent(gs);
    if (parent > 0) {
        // Orphan-detect via PPID. kill(stale_pid, 0) misses PID reuse — if
        // the original arcan died and the slot was recycled by an unrelated
        // process, the kill check returns 0 and the frameserver lingers
        // forever (reparented to systemd, holding deleted /memfd:arcan_shmif
        // segments). PPID changes the moment we're reparented; comparing it
        // against the recorded parent_pid catches the leak deterministically.
        //
        // PPID-equality is only meaningful for frameservers arcan FORKED
        // (getppid() == arcan_pid at start). For external shmif clients
        // (ARCAN_CONNPATH=durden, afsrv_bun-from-cat9-cell, third-party
        // clients) getppid() is the launching shell, never arcan, so the
        // ppid != parent test would fire on every healthy connection. We
        // latch ever_matched on the first iteration where ppid == parent;
        // only after that does a divergence indicate orphaning.
        // See bug 0114 (regression of bug 0113).
        const ppid = getppid();
        if (ppid == parent) {
            ever_matched.* = true;
        } else if (ever_matched.*) {
            // Orphan detected. Don't std.debug.panic — that produces a
            // bogus second coredump every time arcan dies (bug 0125):
            // arcan crashes -> N frameservers each panic here ->
            // coredumpctl fills with "afsrv_*" cores that aren't bugs,
            // they're just the orphan-detect firing as designed. Return
            // false so the watchdog body runs the normal teardown
            // (mutex/dms/socket shutdown + exitf(EXIT_FAILURE)) and we
            // exit cleanly with a stderr breadcrumb.
            var buf: [128]u8 = undefined;
            const msg = std.fmt.bufPrint(
                &buf,
                "watchdog: orphaned (parent={d} ppid={d}), exiting\n",
                .{ parent, ppid },
            ) catch "watchdog: orphaned, exiting\n";
            dbg(msg);
            return false;
        }
        if (kill(parent, 0) == -1) {
            // Only ESRCH means the process is gone. EPERM means it exists
            // but we lack permission to signal it (e.g. after setsid+exec).
            const err = std.c._errno().*;
            if (err == ESRCH) {
                dbg("parent_alive: kill(pid,0) ESRCH - parent gone\n");
                return false;
            }
            // EPERM or other error: process exists, don't kill the child
        }
    }

    // H19 TEST: peek disabled — testing if MSG_PEEK races with main thread's
    // recvmsg for SCM_RIGHTS delivery. If preroll success jumps, the peek is
    // the culprit. Parent kill(pid,0) check above is still in effect.
    // const parent_fd = off.Hidden.getGuardParentFd(gs);
    // if (parent_fd != -1) {
    //     var ch: u8 = undefined;
    //     const ret = recv(parent_fd, @ptrCast(&ch), 1, MSG_PEEK | MSG_DONTWAIT);
    //     if (ret == -1) {
    //         const err = std.c._errno().*;
    //         if (err != EWOULDBLOCK and err != EAGAIN) {
    //             dbg("parent_alive: recv failed, errno!=EWOULDBLOCK\n");
    //             return false;
    //         }
    //     }
    // }

    return true;
}

// watchdog thread

fn watchdog(gs: ?*anyopaque) callconv(.c) ?*anyopaque {
    const gstr: *anyopaque = @ptrCast(@alignCast(gs));
    dbg("watchdog: thread started\n");

    // Latch for the PPID-orphan detector. Set to true on the first
    // tick where getppid() == recorded parent (meaning we are or
    // were a forked child of arcan). Subsequent PPID divergence
    // panics. External shmif clients (ARCAN_CONNPATH=durden, etc.)
    // never set this, so the panic stays disarmed for them. See
    // bug 0114.
    var ever_matched: bool = false;

    while (off.Hidden.getGuardActive(gstr)) {
        if (!parent_alive(gstr, &ever_matched)) {
            dbg("watchdog: parent NOT alive, triggering guard\n");
            // guard synch mutex only protects the structure itself
            _ = pthread_mutex_lock(off.Hidden.getGuardSynchPtr(gstr));

            // setting the dms here is for any others that might monitor the segment
            const dms = off.Hidden.getGuardDms(gstr);
            if (dms) |dms_ptr| {
                @as(*volatile u8, @ptrCast(dms_ptr)).* = 0;
            }

            off.Hidden.setGuardLocalDms(gstr, false);
            if (off.Hidden.getGuardPage(gstr)) |page| {
                _ = shmif_platform_sync_post(
                    page,
                    SYNC_EVENT | SYNC_AUDIO | SYNC_VIDEO,
                );
            }
            off.Hidden.setGuardActive(gstr, false);

            // same as everywhere else, implementation need to allow unlock to destroy
            const synch = off.Hidden.getGuardSynchPtr(gstr);
            _ = pthread_mutex_unlock(synch);
            _ = pthread_mutex_destroy(synch);

            // also shutdown the socket, should unlock any blocking I/O stage
            _ = shutdown(off.Hidden.getGuardParentFd(gstr), SHUT_RDWR);

            if (off.Hidden.getGuardExitf(gstr)) |exitf_raw| {
                const exitf: exitf_fn = @ptrCast(@alignCast(exitf_raw));
                exitf(EXIT_FAILURE);
            }

            return null;
        }

        _ = sleep(1);
    }

    return null;
}

// shmif_platform_check_alive

export fn shmif_platform_check_alive(C: ?*c.struct_arcan_shmif_cont) bool {
    if (is_freestanding) return true;
    const cont = C orelse return false;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (!off.Hidden.getAlive(P)) {
        dbg("check_alive: alive=false\n");
        return false;
    }

    if (!off.Hidden.getGuardLocalDms(P)) {
        dbg("check_alive: guard_local_dms=false\n");
        return false;
    }

    // C->addr->dms
    const addr = cont.addr orelse {
        dbg("check_alive: addr=null\n");
        return false;
    };
    if (off.Page.getDms(@ptrCast(addr)) == 0) {
        // Protocol-defined "parent asked us to exit". Upstream
        // reference/arcan-upstream/src/shmif/platform/watchdog.c:97-104
        // returns false here; the caller drains TARGET_COMMAND_EXIT and
        // shuts down cleanly. Dump a one-shot diagnostic then propagate.
        const Once = struct { var reported: bool = false; };
        if (!Once.reported) {
            Once.reported = true;
            var diagbuf: [512]u8 = undefined;
            const addr_int = @intFromPtr(addr);
            const page_parent = off.Page.getParent(@ptrCast(addr));
            const guard_parent = off.Hidden.getGuardParent(P);
            const kr = kill(guard_parent, 0);
            const ke = std.c._errno().*;
            const cookie = off.Page.getCookie(@ptrCast(addr));
            const msg = std.fmt.bufPrint(&diagbuf,
                "check_alive: dms=0 addr=0x{x} page.parent={d} guard_parent={d} kill={d} errno={d} cookie=0x{x}\n",
                .{ addr_int, page_parent, guard_parent, kr, ke, cookie }) catch "check_alive: dms=0 fmt err\n";
            dbg(msg);
        }
        return false;
    }

    return true;
}

// shmif_platform_guard_resynch

export fn shmif_platform_guard_resynch(
    C: ?*c.struct_arcan_shmif_cont,
    parent_pid: c_int,
    parent_fd: c_int,
) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (!off.Hidden.getGuardActive(P))
        return;

    // we are already locked
    const addr = cont.addr orelse return;
    const dms_ptr = off.Page.getDmsPtr(@ptrCast(addr));
    off.Hidden.setGuardDms(P, dms_ptr);
    off.Hidden.setGuardParentFd(P, parent_fd);
    off.Hidden.setGuardParent(P, parent_pid);
    off.Hidden.setGuardPage(P, @ptrCast(addr));
}

// shmif_platform_guard_lock

export fn shmif_platform_guard_lock(C: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));
    if (off.Hidden.getGuardActive(P))
        _ = pthread_mutex_lock(off.Hidden.getGuardSynchPtr(P));
}

// shmif_platform_guard_unlock

export fn shmif_platform_guard_unlock(C: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));
    if (off.Hidden.getGuardActive(P))
        _ = pthread_mutex_unlock(off.Hidden.getGuardSynchPtr(P));
}

// shmif_platform_guard_release

export fn shmif_platform_guard_release(C: ?*c.struct_arcan_shmif_cont) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (!off.Hidden.getGuardActive(P)) {
        free(@as(?*anyopaque, @ptrCast(cont.priv)));
        return;
    }

    off.Hidden.setGuardDms(P, null);
    off.Hidden.setGuardActive(P, false);
}

// shmif_platform_guard

export fn shmif_platform_guard(
    C: ?*c.struct_arcan_shmif_cont,
    CFG: c.struct_watchdog_config,
) void {
    if (is_freestanding) return;
    const cont = C orelse return;
    const P: *anyopaque = @ptrCast(@alignCast(cont.priv));

    if (off.Hidden.getGuardActive(P))
        return;

    off.Hidden.setGuardLocalDms(P, true);
    off.Hidden.setGuardParent(P, CFG.parent_pid);
    off.Hidden.setGuardParentFd(P, CFG.parent_fd);
    off.Hidden.setGuardExitf(P, if (CFG.exitf) |f| @constCast(@ptrCast(f)) else null);
    off.Hidden.setGuardPage(P, @ptrCast(cont.addr));

    const addr = cont.addr orelse return;
    const dms_ptr = off.Page.getDmsPtr(@ptrCast(addr));
    off.Hidden.setGuardDms(P, dms_ptr);

    var pth: pthread_t = undefined;
    var pthattr: pthread_attr_t = undefined;
    _ = pthread_attr_init(&pthattr);
    _ = pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);
    _ = pthread_mutex_init(off.Hidden.getGuardSynchPtr(P), null);

    // failure means loss of functionality but not a terminal condition
    off.Hidden.setGuardActive(P, true);
    if (pthread_create(&pth, &pthattr, &watchdog, @ptrCast(P)) != 0) {
        off.Hidden.setGuardActive(P, false);
    }
}
