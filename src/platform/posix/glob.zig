// Pure Zig port of posix/glob.c — zero C helpers.
// Resource globbing with async pipe-based threading.

const std = @import("std");

const c = struct {
    // POSIX I/O
    extern fn write(fd: c_int, buf: [*c]const u8, count: usize) isize;
    extern fn close(fd: c_int) c_int;
    extern fn pipe(pipefd: *[2]c_int) c_int;
    extern fn fcntl(fd: c_int, cmd: c_int, ...) callconv(.c) c_int;
    extern fn poll(fds: *pollfd, nfds: usize, timeout: c_int) c_int;

    // POSIX directory
    extern fn opendir(path: [*c]const u8) ?*anyopaque;
    extern fn readdir(dir: *anyopaque) ?*dirent;
    extern fn closedir(dir: *anyopaque) c_int;

    // POSIX glob
    extern fn glob(pattern: [*c]const u8, flags: c_int, errfn: ?*anyopaque, pglob: *glob_t) c_int;
    extern fn globfree(pglob: *glob_t) void;

    // POSIX threads
    extern fn pthread_create(thread: *usize, attr: ?*const pthread_attr_t, start_routine: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) c_int;
    extern fn pthread_attr_init(attr: *pthread_attr_t) c_int;
    extern fn pthread_attr_setdetachstate(attr: *pthread_attr_t, state: c_int) c_int;
    extern fn pthread_attr_destroy(attr: *pthread_attr_t) c_int;

    // libc
    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn strlen(s: [*c]const u8) usize;
    extern fn strrchr(s: [*c]const u8, ch: c_int) [*c]u8;
    extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    extern fn malloc(size: usize) ?[*]u8;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;
    extern fn memset(s: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
    extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;

    // errno
    extern fn __errno_location() *c_int;

    const F_SETFL: c_int = 4;
    const F_SETFD: c_int = 2;
    const O_NONBLOCK: c_int = 0o4000;
    const FD_CLOEXEC: c_int = 1;
    const EAGAIN: c_int = 11;
    const EINTR: c_int = 4;
    const POLLOUT: c_short = 0x04;
    const POLLHUP: c_short = 0x10;
    const POLLNVAL: c_short = 0x20;
    const PTHREAD_CREATE_DETACHED: c_int = 1;
};

const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const is_darwin = @import("builtin").os.tag.isDarwin();

const glob_t = if (is_darwin) extern struct {
    gl_pathc: usize,
    gl_matchc: c_int,
    gl_offs: usize,
    gl_flags: c_int,
    gl_pathv: [*c][*c]u8,
    gl_errfunc: ?*anyopaque,
    gl_closedir: ?*anyopaque,
    gl_readdir: ?*anyopaque,
    gl_opendir: ?*anyopaque,
    gl_lstat: ?*anyopaque,
    gl_stat: ?*anyopaque,
} else extern struct {
    gl_pathc: usize,
    gl_pathv: [*c][*c]u8,
    gl_offs: usize,
    gl_flags: c_int,
    gl_closedir: ?*anyopaque,
    gl_readdir: ?*anyopaque,
    gl_opendir: ?*anyopaque,
    gl_lstat: ?*anyopaque,
    gl_stat: ?*anyopaque,
};

const dirent = if (is_darwin) extern struct {
    // arm64 darwin: the plain readdir symbol IS the 64-bit-inode variant
    d_ino: u64,
    d_seekoff: u64,
    d_reclen: u16,
    d_namlen: u16,
    d_type: u8,
    d_name: [1024]u8,
} else extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]u8,
};

const pthread_attr_t = extern struct {
    _data: [64]u8,
};

const arcan_userns = extern struct {
    read: bool,
    write: bool,
    ipc: bool,
    dirfd: c_int,
    label: [64]u8,
    name: [32]u8,
    path: [256]u8,
};

// Engine API
extern fn arcan_expand_resource(label: [*c]const u8, ns: c_int) [*c]u8;
extern fn arcan_fetch_namespace(ns: c_int) [*c]const u8;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn verify_traverse(path: [*c]const u8) [*c]const u8;
extern fn arcan_lookup_namespace(id: [*c]const u8, ns: *arcan_userns, openfd: bool) bool;

const RESOURCE_SYS_ENDM: c_int = 2048;
const NSPACES = 12; // log2(2048) + 1 for safe indexing

const GlobCallback = ?*const fn ([*c]u8, ?*anyopaque) callconv(.c) void;

const GlobArg = struct {
    cb: GlobCallback = null,
    ns: c_int = 0,
    basename: [*c]u8 = null,
    space: [*c]u8 = null,
    tag: ?*anyopaque = null,
    fdout: c_int = -1,
    count: usize = 0,
};

fn dump_to_pipe(base_arg: [*c]u8, fd: c_int) bool {
    var base = base_arg;
    var ntw = c.strlen(base) + 1;

    while (ntw > 0) {
        const nw = c.write(fd, base, ntw);
        if (nw == -1) {
            const err = c.__errno_location().*;
            if (err == c.EAGAIN or err == c.EINTR)
                continue;
            // EWOULDBLOCK == EAGAIN on Linux, covered above
            var pfd = pollfd{
                .fd = fd,
                .events = c.POLLHUP | c.POLLNVAL | c.POLLOUT,
                .revents = 0,
            };
            _ = c.poll(&pfd, 1, -1);
            continue;
        }
        const written: usize = @intCast(nw);
        base += written;
        ntw -= written;
    }
    return true;
}

fn run_glob(path: [*c]u8, skip: usize, garg: *GlobArg) void {
    // Try as directory first
    if (c.opendir(path)) |dir| {
        while (c.readdir(dir)) |dent| {
            if (garg.cb) |cb_fn| {
                cb_fn(&dent.d_name, garg.tag);
            } else if (!dump_to_pipe(&dent.d_name, garg.fdout)) {
                break;
            }
        }
        _ = c.closedir(dir);
        return;
    }

    // Fall back to glob pattern matching
    var res = std.mem.zeroes(glob_t);
    if (c.glob(path, 0, null, &res) == 0) {
        var beg = res.gl_pathv;
        while (beg[0] != null) {
            const entry = beg[0];
            const slash = c.strrchr(entry, '/');
            const name: [*c]u8 = if (slash != null) slash + 1 else entry;

            if (garg.cb) |cb_fn| {
                cb_fn(name, garg.tag);
            } else if (!dump_to_pipe(entry + skip, garg.fdout)) {
                break;
            }
            beg += 1;
            garg.count += 1;
        }
        c.globfree(&res);
    }
}

fn glob_full(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const garg: *GlobArg = @ptrCast(@alignCast(arg orelse return null));

    if (garg.basename == null or verify_traverse(garg.basename) == null) {
        c.free(garg.basename);
        return null;
    }

    var globslots: [NSPACES]?[*c]u8 = [_]?[*c]u8{null} ** NSPACES;
    var ofs: usize = 0;

    var ns: c_int = 1;
    while (ns <= RESOURCE_SYS_ENDM) : (ns <<= 1) {
        if ((garg.ns & ns) == 0)
            continue;

        const path = arcan_expand_resource(garg.basename, ns);
        if (path == null)
            continue;

        // Deduplicate paths
        var match = false;
        for (0..ofs) |j| {
            if (globslots[j]) |slot| {
                if (c.strcmp(path, slot) == 0) {
                    arcan_mem_free(path);
                    match = true;
                    break;
                }
            } else break;
        }
        if (match)
            continue;

        if (ofs < NSPACES) {
            globslots[ofs] = path;
            ofs += 1;
        }
        const ns_path = arcan_fetch_namespace(ns);
        const skip = if (ns_path != null) c.strlen(ns_path) + 1 else 0;
        run_glob(path, skip, garg);
    }

    if (garg.fdout != -1)
        _ = c.close(garg.fdout);

    for (0..NSPACES) |i| {
        if (globslots[i]) |slot|
            arcan_mem_free(slot)
        else
            break;
    }

    return null;
}

fn glob_userns(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const garg: *GlobArg = @ptrCast(@alignCast(arg orelse return null));

    var ns: arcan_userns = undefined;

    if (garg.basename == null or verify_traverse(garg.basename) == null or
        !arcan_lookup_namespace(garg.space, &ns, false))
        return null;

    const blen = c.strlen(garg.basename);
    const plen = cstrlen_arr(&ns.path);
    const len = blen + plen + 2;
    const buf = c.malloc(len) orelse return null;
    _ = c.snprintf(buf, len, "%s/%s", @as([*c]const u8, &ns.path), garg.basename);

    const skip = plen + 1;
    run_glob(buf, skip, garg);

    if (garg.fdout != -1)
        _ = c.close(garg.fdout);

    c.free(buf);
    return null;
}

fn cstrlen_arr(s: []const u8) usize {
    for (0..s.len) |i| {
        if (s[i] == 0) return i;
    }
    return s.len;
}

fn setup_globthread(
    garg: GlobArg,
    dfd: *c_int,
    fptr: *const fn (?*anyopaque) callconv(.c) ?*anyopaque,
) void {
    const mem = c.malloc(@sizeOf(GlobArg)) orelse {
        dfd.* = -1;
        return;
    };
    const ptr: *GlobArg = @ptrCast(@alignCast(mem));
    ptr.* = garg;

    var pair: [2]c_int = undefined;
    if (c.pipe(&pair) == -1) {
        dfd.* = -1;
        c.free(ptr);
        return;
    }

    for (0..2) |i| {
        _ = c.fcntl(pair[i], c.F_SETFL, @as(c_int, c.O_NONBLOCK));
        _ = c.fcntl(pair[i], c.F_SETFD, @as(c_int, c.FD_CLOEXEC));
    }

    dfd.* = pair[0];
    ptr.fdout = pair[1];

    var globth: usize = 0;
    var globth_attr: pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&globth_attr);
    _ = c.pthread_attr_setdetachstate(&globth_attr, c.PTHREAD_CREATE_DETACHED);

    if (c.pthread_create(&globth, &globth_attr, fptr, @ptrCast(ptr)) != 0) {
        _ = c.close(pair[0]);
        _ = c.close(pair[1]);
        dfd.* = -1;
        c.free(ptr);
    }

    _ = c.pthread_attr_destroy(&globth_attr);
}

export fn arcan_glob(
    basename: [*c]u8,
    space: c_int,
    cb: GlobCallback,
    asynch: ?*c_int,
    tag: ?*anyopaque,
) c_uint {
    var garg = GlobArg{
        .cb = cb,
        .ns = space,
        .basename = c.strdup(basename),
        .tag = tag,
        .fdout = -1,
    };

    if (asynch == null) {
        _ = glob_full(&garg);
        return @intCast(garg.count);
    }

    setup_globthread(garg, asynch.?, glob_full);
    return 0;
}

export fn arcan_glob_userns(
    basename: [*c]u8,
    space: [*c]const u8,
    cb: GlobCallback,
    asynch: ?*c_int,
    tag: ?*anyopaque,
) c_uint {
    var garg = GlobArg{
        .cb = cb,
        .space = c.strdup(space),
        .basename = c.strdup(basename),
        .tag = tag,
        .fdout = -1,
    };

    if (asynch == null) {
        _ = glob_userns(&garg);
        return @intCast(garg.count);
    }

    setup_globthread(garg, asynch.?, glob_userns);
    return 0;
}
