// Zig port of src/shmif/tui/lua/tui_lua_glob.c
// Implements glob/directory listing for TUI Lua bindings.

const std = @import("std");
const c = @import("shmif_types");

const lua_State = c.lua_State;

// musl struct dirent layout (d_name at offset 19)
const struct_dirent = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: c_ushort,
    d_type: u8,
    d_name: [256]u8,
};

const glob_arg = struct {
    basename: [*c]u8,
    fdout: c_int,
};

fn dump_to_pipe(base_in: [*c]u8, fd: c_int) bool {
    var base = base_in;
    var ntw: usize = c.strlen(base) + 1;

    while (ntw != 0) {
        const nw = c.write(fd, @as(*const anyopaque, @ptrCast(base)), ntw);
        if (nw == -1) {
            const err = c.__errno_location().*;
            if (err == c.EAGAIN or err == c.EINTR)
                continue;

            if (err == c.EWOULDBLOCK) {
                var pfd = c.struct_pollfd{
                    .fd = fd,
                    .events = c.POLLHUP | c.POLLNVAL | c.POLLOUT,
                    .revents = 0,
                };
                _ = c.poll(&pfd, 1, -1);
                continue;
            }

            return false;
        } else {
            const written: usize = @intCast(nw);
            base += written;
            ntw -= written;
        }
    }

    return true;
}

fn glob_full(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const garg: *glob_arg = @ptrCast(@alignCast(arg));
    var res: c.glob_t = std.mem.zeroes(c.glob_t);

    const dir = c.opendir(garg.basename);
    if (dir) |d| {
        while (true) {
            const raw = c.readdir(d);
            if (raw == null) break;
            const dent: *struct_dirent = @ptrCast(@alignCast(raw));
            if (!dump_to_pipe(&dent.d_name, garg.fdout))
                break;
        }

        _ = c.closedir(d);
    } else {
        if (c.glob(garg.basename, 0, null, &res) == 0) {
            var beg: [*c][*c]u8 = @ptrCast(res.gl_pathv);

            while (beg.* != null) {
                if (!dump_to_pipe(beg.*, garg.fdout)) {
                    break;
                }
                beg += 1;
            }

            c.globfree(&res);
        }
    }

    // out:
    if (garg.fdout != -1) {
        _ = c.close(garg.fdout);
    }

    c.free(@ptrCast(garg.basename));

    return null;
}

fn setup_globthread(garg: glob_arg, dfd: *c_int, fptr: *const fn (?*anyopaque) callconv(.c) ?*anyopaque) void {
    const ptr: *glob_arg = @ptrCast(@alignCast(c.malloc(@sizeOf(glob_arg))));
    ptr.* = garg;

    var pair: [2]c_int = undefined;
    if (c.pipe(&pair) == -1) {
        dfd.* = -1;
        return;
    }
    for (0..2) |i| {
        _ = c.fcntl(pair[i], c.F_SETFL, c.O_NONBLOCK);
        _ = c.fcntl(pair[i], c.F_SETFD, c.FD_CLOEXEC);
    }

    dfd.* = pair[0];
    ptr.fdout = pair[1];

    var globth: c.pthread_t = undefined;
    var globth_attr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&globth_attr);
    _ = c.pthread_attr_setdetachstate(&globth_attr, c.PTHREAD_CREATE_DETACHED);

    if (c.pthread_create(&globth, &globth_attr, fptr, @as(*anyopaque, @ptrCast(ptr))) != 0) {
        _ = c.close(pair[0]);
        _ = c.close(pair[1]);
        dfd.* = -1;
        c.free(@ptrCast(ptr));
    }

    _ = c.pthread_attr_destroy(&globth_attr);
}

export fn tui_glob(L: ?*lua_State) c_int {
    // TUI_UDATA — struct tui_lmeta may be opaque due to anonymous union,
    // so we validate via pointer: first pointer-sized field is 'tui'.
    const ud = c.luaL_checkudata(L, 1, "Arcan TUI");
    if (ud == null) {
        _ = c.luaL_error(L, "no userdata");
        unreachable;
    }
    // The first field of tui_lmeta is the anonymous union whose first member
    // is 'struct tui_context* tui' — check it is non-null.
    const tui_ptr: *const ?*anyopaque = @ptrCast(@alignCast(ud));
    if (tui_ptr.* == null) {
        _ = c.luaL_error(L, "no tui context");
        unreachable;
    }

    const garg = glob_arg{
        .basename = c.strdup(c.luaL_checklstring(L, 2, null)),
        .fdout = -1,
    };

    var fd: c_int = undefined;
    setup_globthread(garg, &fd, &glob_full);

    if (fd != -1) {
        var dst: ?*c.struct_nonblock_io = null;
        _ = c.alt_nbio_import(L, fd, c.O_RDONLY, &dst, null);
    } else {
        c.lua_pushnil(L);
    }

    return 1;
}
