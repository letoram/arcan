// Zig reimplementation of arcan_shmif_filehelper.c
// Drop-in C-ABI-compatible replacement for filehelper functions.
//
// Exports: arcan_shmif_bgcopy, arcan_shmif_bchunk_resolve
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const c = @import("shmif_types");

// Extern C declarations

extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn close(fd: c_int) c_int;
extern fn read(fd: c_int, buf: ?*anyopaque, count: usize) isize;
extern fn write(fd: c_int, buf: ?*const anyopaque, count: usize) isize;
extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;
extern fn arcan_timemillis() u64;
extern fn readlink(
    path: [*c]const u8,
    buf: [*c]u8,
    bufsiz: usize,
) isize;

const stat_t = c.struct_stat;
extern fn fstat(fd: c_int, buf: *stat_t) c_int;
extern fn stat(path: [*c]const u8, buf: *stat_t) c_int;

extern fn pthread_create(
    thread: *std.c.pthread_t,
    attr: ?*const std.c.pthread_attr_t,
    start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
    arg: ?*anyopaque,
) c_int;
extern fn pthread_attr_init(attr: *std.c.pthread_attr_t) c_int;
extern fn pthread_attr_setdetachstate(attr: *std.c.pthread_attr_t, detachstate: c_int) c_int;

const PTHREAD_CREATE_DETACHED: c_int = 1;
const PATH_MAX: usize = 4096;

// static helper: write_buffer

fn write_buffer(fd: c_int, inbuf_in: [*c]u8, inbuf_sz_in: usize) bool {
    var inbuf: [*c]u8 = inbuf_in;
    var inbuf_sz = inbuf_sz_in;
    while (inbuf_sz > 0) {
        const nr = write(fd, @as(?*const anyopaque, @ptrCast(inbuf)), inbuf_sz);
        if (nr == -1) {
            const err = std.c._errno().*;
            if (err == c.EAGAIN or err == c.EINTR)
                continue;
            return false;
        }
        inbuf += @intCast(nr);
        inbuf_sz -= @intCast(nr);
    }
    return true;
}

// static helper: copy_thread

fn copy_thread(inarg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const fds: *[4]c_int = @ptrCast(@alignCast(inarg));
    var inbuf: [4096]u8 = undefined;
    var sc: i8 = 0;

    var acc: usize = 0;
    var last_acc: usize = 0;
    const report_mb: usize = 10;
    var time_last: u64 = arcan_timemillis();

    var tot: usize = 0;
    var fs: stat_t = std.mem.zeroes(stat_t);

    // might not remain accurate but fair to keep around
    if (fstat(fds[0], &fs) != -1 and fs.st_size > 0) {
        tot = @intCast(fs.st_size);
    }

    // depending on type and OS, there are a number of options e.g. sendfile,
    // splice, sosplice, ... right now just use a slow/safe
    while (true) {
        const nr = read(fds[0], @as(?*anyopaque, @ptrCast(&inbuf)), inbuf.len);
        if (nr == -1) {
            const err = std.c._errno().*;
            if (err == c.EAGAIN or err == c.EINTR)
                continue;
            sc = -1;
            break;
        }
        if (nr == 0) {
            break;
        } else if (!write_buffer(fds[1], @as([*c]u8, @ptrCast(&inbuf)), @intCast(nr))) {
            sc = -2;
            break;
        }

        // PIPE_BUF is required to be >= 512 on POSIX, only update every n megabytes or
        // every second or so as to not block unnecessarily on reporting
        if (fds[3] & @as(c_int, c.SHMIF_BGCOPY_PROGRESS) != 0) {
            acc += @intCast(nr);

            if (acc - last_acc > report_mb * 1024 * 1024 or
                arcan_timemillis() - time_last > 1000)
            {
                last_acc = acc;
                time_last = arcan_timemillis();
                const n = snprintf(
                    @as([*c]u8, @ptrCast(&inbuf)),
                    inbuf.len,
                    "%zu:%zu:%zu\n",
                    @as(usize, @intCast(nr)),
                    acc,
                    tot,
                );
                _ = write(fds[2], @as(?*const anyopaque, @ptrCast(&inbuf)), @intCast(n));
            }
        }
    }

    if (fds[3] & @as(c_int, c.SHMIF_BGCOPY_KEEPIN) == 0)
        _ = close(fds[0]);
    if (fds[3] & @as(c_int, c.SHMIF_BGCOPY_KEEPOUT) == 0)
        _ = close(fds[1]);

    if (fds[2] != -1) {
        if (fds[3] & @as(c_int, c.SHMIF_BGCOPY_PROGRESS) != 0) {
            const n = snprintf(
                @as([*c]u8, @ptrCast(&inbuf)),
                inbuf.len,
                "%d:%zu:%zu\n",
                @as(c_int, sc),
                acc,
                tot,
            );
            while (write(fds[2], @as(?*const anyopaque, @ptrCast(&inbuf)), @intCast(n)) == -1) {
                const err = std.c._errno().*;
                if (err != c.EAGAIN and err != c.EINTR)
                    break;
            }
        } else {
            while (write(fds[2], @as(?*const anyopaque, @ptrCast(&sc)), 1) == -1) {
                const err = std.c._errno().*;
                if (err != c.EAGAIN and err != c.EINTR)
                    break;
            }
        }

        _ = close(fds[2]);
    }

    free(@as(?*anyopaque, @ptrCast(fds)));
    return null;
}

// arcan_shmif_bgcopy

export fn arcan_shmif_bgcopy(
    _: ?*c.struct_arcan_shmif_cont,
    fdin: c_int,
    fdout: c_int,
    sigfd: c_int,
    fl: c_int,
) void {
    if (is_freestanding) return;
    const raw = malloc(@sizeOf(c_int) * 4) orelse return;
    const fds: *[4]c_int = @ptrCast(@alignCast(raw));
    fds[0] = fdin;
    fds[1] = fdout;
    fds[2] = sigfd;
    fds[3] = fl;

    // options, fork or thread
    var pth: std.c.pthread_t = undefined;
    var pthattr: std.c.pthread_attr_t = undefined;
    _ = pthread_attr_init(&pthattr);
    _ = pthread_attr_setdetachstate(&pthattr, PTHREAD_CREATE_DETACHED);

    if (pthread_create(&pth, &pthattr, &copy_thread, @as(?*anyopaque, @ptrCast(fds))) != 0) {
        if (fl & @as(c_int, c.SHMIF_BGCOPY_KEEPIN) == 0)
            _ = close(fdin);
        if (fl & @as(c_int, c.SHMIF_BGCOPY_KEEPOUT) == 0)
            _ = close(fdout);
        if (sigfd != -1) {
            var ch: i8 = -3;
            _ = write(sigfd, @as(?*const anyopaque, @ptrCast(&ch)), 1);
        }
        free(raw);
    }
}

// arcan_shmif_bchunk_resolve

export fn arcan_shmif_bchunk_resolve(
    _: ?*c.struct_arcan_shmif_cont,
    bev: ?*c.arcan_event,
) [*c]u8 {
    if (is_freestanding) return null;
    if (comptime builtin.os.tag == .linux) {
        const ev = bev orelse return null;
        if (ev.category().* != c.EVENT_TARGET or
            (ev.tgt().kind != c.TARGET_COMMAND_BCHUNK_IN and
                ev.tgt().kind != c.TARGET_COMMAND_BCHUNK_OUT))
            return null;

        var buf: [24]u8 = undefined;
        _ = snprintf(
            @as([*c]u8, @ptrCast(&buf)),
            buf.len,
            "/proc/self/fd/%d",
            ev.tgt().ioevs[0].iv,
        );

        const mbuf: [*c]u8 = @ptrCast(malloc(PATH_MAX) orelse return null);

        const rv = readlink(
            @as([*c]const u8, @ptrCast(&buf)),
            mbuf,
            PATH_MAX,
        );

        if (rv == -1 or mbuf[0] != '/') {
            free(@as(?*anyopaque, @ptrCast(mbuf)));
            return null;
        }

        var base_stat: stat_t = std.mem.zeroes(stat_t);
        var comp_stat: stat_t = std.mem.zeroes(stat_t);
        if (fstat(ev.tgt().ioevs[0].iv, &base_stat) == -1 or
            stat(mbuf, &comp_stat) == -1 or
            base_stat.st_ino != comp_stat.st_ino)
        {
            free(@as(?*anyopaque, @ptrCast(mbuf)));
            return null;
        }

        return mbuf;
    } else {
        // OpenBSD has no solution, FreeBSD / OSX has a fcntl that can be used
        return null;
    }
}
