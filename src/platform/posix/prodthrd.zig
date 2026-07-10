// Zig port of posix/prodthrd.c
// pthread-based IO thread with pipe + callback for streaming reads.

const std = @import("std");
const c = @import("posix");

const CallbackFn = *const fn (c_int, [*c]u8, usize, ?*anyopaque) callconv(.c) c_int;

const ThreadData = extern struct {
    fd: c_int,
    pipeout: c_int,
    block_sz: usize,
    tag: ?*anyopaque,
    buf: [*c]u8,
    allow_short: bool,
    callback: CallbackFn,
};

fn iothread(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const thd: *ThreadData = @ptrCast(@alignCast(arg));

    if (thd.allow_short) {
        // short-read mode: pass whatever comes through
        while (true) {
            const nr = c.read(thd.fd, thd.buf, thd.block_sz);
            if (nr == -1) {
                const err = c.__errno_location().*;
                if (err != c.EAGAIN and err != c.EINTR) {
                    _ = thd.callback(-1, null, 0, thd.tag);
                    break;
                }
                continue;
            }
            if (nr > 0) {
                if (thd.callback(thd.pipeout, thd.buf, @intCast(nr), thd.tag) == 0) {
                    break;
                }
            }
        }
    } else {
        // buffered mode: accumulate until block_sz reached
        var ofs: usize = 0;
        while (true) {
            const ntr = thd.block_sz - ofs;
            const nr = c.read(thd.fd, thd.buf + ofs, ntr);
            if (nr == -1) {
                const err = c.__errno_location().*;
                if (err != c.EAGAIN and err != c.EINTR) {
                    break;
                }
                continue;
            }
            ofs += @intCast(nr);
            if (ofs == thd.block_sz) {
                if (thd.callback(thd.pipeout, thd.buf, thd.block_sz, thd.tag) == 0)
                    break;
                ofs = 0;
            }
        }
    }

    _ = c.close(thd.fd);
    _ = c.close(thd.pipeout);
    c.free(thd.buf);
    c.free(thd);
    return null;
}

export fn platform_producer_thread(
    infd: c_int,
    block_sz: usize,
    callback: CallbackFn,
    tag: ?*anyopaque,
) c_int {
    const thd: ?*ThreadData = @ptrCast(@alignCast(c.malloc(@sizeOf(ThreadData))));
    if (thd == null) return -1;

    var pp: [2]c_int = undefined;
    if (c.pipe(&pp) == -1) {
        c.free(thd);
        return -1;
    }

    // set FD_CLOEXEC on both ends
    var flags = c.fcntl(pp[0], c.F_GETFD);
    if (flags != -1)
        _ = c.fcntl(pp[0], c.F_SETFD, flags | c.FD_CLOEXEC);

    flags = c.fcntl(pp[1], c.F_GETFD);
    if (flags != -1)
        _ = c.fcntl(pp[1], c.F_SETFD, flags | c.FD_CLOEXEC);

    // read end should be non-blocking
    flags = c.fcntl(pp[0], c.F_GETFL);
    if (flags != -1)
        _ = c.fcntl(pp[0], c.F_SETFL, flags | c.O_NONBLOCK);

    var buf_sz: usize = 4096;
    var allow_short: bool = true;

    if (block_sz != 0) {
        buf_sz = block_sz;
        allow_short = false;
    }

    const buf: [*c]u8 = @ptrCast(c.malloc(buf_sz));
    if (buf == null) {
        c.free(thd);
        _ = c.close(pp[0]);
        _ = c.close(pp[1]);
        return -1;
    }

    thd.?.* = .{
        .fd = infd,
        .block_sz = buf_sz,
        .allow_short = allow_short,
        .tag = tag,
        .pipeout = pp[1],
        .callback = callback,
        .buf = buf,
    };

    var pth: c.pthread_t = undefined;
    var pthattr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&pthattr);
    _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);

    if (c.pthread_create(&pth, &pthattr, &iothread, thd) != 0) {
        c.free(thd);
        _ = c.close(pp[0]);
        _ = c.close(pp[1]);
        return -1;
    }

    return pp[0];
}
