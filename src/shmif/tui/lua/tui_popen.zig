const std = @import("std");
const c = @import("shmif_types");

const lua_State = c.lua_State;

const SIGUNUSED = 31;
const IUTF8 = 0x00004000;

// musl struct termios layout (60 bytes total, matching shmif_types opaque _data)
const struct_termios_real = extern struct {
    c_iflag: c_uint,
    c_oflag: c_uint,
    c_cflag: c_uint,
    c_lflag: c_uint,
    c_line: u8,
    c_cc: [32]u8,
    _pad: [3]u8,
    __c_ispeed: c_uint,
    __c_ospeed: c_uint,
};

extern var environ: [*c][*c]u8;

fn lua_rawlen(L: ?*lua_State, idx: c_int) usize {
    return c.lua_objlen(L, idx);
}

/// Sets the FD_CLOEXEC flag. Returns 0 on success, -1 on error.
fn set_cloexec(fd: c_int) c_int {
    if (c.fcntl(fd, c.F_SETFD, c.fcntl(fd, c.F_GETFD) | c.FD_CLOEXEC) == -1) {
        c.perror("Error setting FD_CLOEXEC flag");
        return -1;
    }
    return 0;
}

fn close_if_valid(fd: c_int) void {
    if (fd >= 0) {
        _ = c.close(fd);
    }
}

/// Runs command in another process, with full remote interaction capabilities.
/// Be aware that command is passed to sh -c, so shell expansion will occur.
///
/// If stdin_fd is set to >= 0 it will be used as the command's stdin.
/// Otherwise it will be provided through *writefd pipe pair.
///
/// Writing to *writefd will write to the command's stdin.
/// Reading from *readfd will read from the command's stdout.
/// Reading from *errfd will read from the command's stderr.
///
/// If NULL is passed for writefd, readfd, or errfd, then the command's
/// stdin, stdout, or stderr will be mapped to /dev/null.
///
/// Returns the child PID on success, -1 on error.
fn popen3(
    command: [*c]const u8,
    stdin_fd_arg: c_int,
    writefd: ?*c_int,
    readfd: ?*c_int,
    errfd: ?*c_int,
    argv: [*c][*c]u8,
    env: [*c][*c]u8,
    pty: bool,
) c.pid_t {
    _ = pty;
    var in_pipe = [2]c_int{ -1, -1 };
    var out_pipe = [2]c_int{ -1, -1 };
    var err_pipe = [2]c_int{ -1, -1 };
    const stdin_fd = stdin_fd_arg;

    // 2011 implementation of popen3() by Mike Bourgeous
    // https://gist.github.com/1022231
    // modified to allow explicit substitution of pipes and non sh -c forms.

    if (command == null and argv == null) {
        _ = c.fprintf(c.stderr, "Cannot popen3() a NULL command.\n");
        close_if_valid(stdin_fd);
        close_if_valid(in_pipe[0]);
        close_if_valid(in_pipe[1]);
        close_if_valid(out_pipe[0]);
        close_if_valid(out_pipe[1]);
        close_if_valid(err_pipe[0]);
        close_if_valid(err_pipe[1]);
        return -1;
    }

    if (stdin_fd == -1 and writefd != null and c.pipe(&in_pipe) != 0) {
        c.perror("Error creating pipe for stdin");
        close_if_valid(stdin_fd);
        close_if_valid(in_pipe[0]);
        close_if_valid(in_pipe[1]);
        close_if_valid(out_pipe[0]);
        close_if_valid(out_pipe[1]);
        close_if_valid(err_pipe[0]);
        close_if_valid(err_pipe[1]);
        return -1;
    }
    if (readfd != null and c.pipe(&out_pipe) != 0) {
        c.perror("Error creating pipe for stdout");
        close_if_valid(stdin_fd);
        close_if_valid(in_pipe[0]);
        close_if_valid(in_pipe[1]);
        close_if_valid(out_pipe[0]);
        close_if_valid(out_pipe[1]);
        close_if_valid(err_pipe[0]);
        close_if_valid(err_pipe[1]);
        return -1;
    }
    if (errfd != null and c.pipe(&err_pipe) != 0) {
        c.perror("Error creating pipe for stderr");
        close_if_valid(stdin_fd);
        close_if_valid(in_pipe[0]);
        close_if_valid(in_pipe[1]);
        close_if_valid(out_pipe[0]);
        close_if_valid(out_pipe[1]);
        close_if_valid(err_pipe[0]);
        close_if_valid(err_pipe[1]);
        return -1;
    }

    const pid = c.fork();
    switch (pid) {
        -1 => {
            // Error
            c.perror("Error creating child process");
            close_if_valid(stdin_fd);
            close_if_valid(in_pipe[0]);
            close_if_valid(in_pipe[1]);
            close_if_valid(out_pipe[0]);
            close_if_valid(out_pipe[1]);
            close_if_valid(err_pipe[0]);
            close_if_valid(err_pipe[1]);
            return -1;
        },
        0 => {
            // Child
            if (stdin_fd != -1) {
                if (c.dup2(stdin_fd, c.STDIN_FILENO) == -1) {
                    c.perror("Error assigning stdin to child");
                    c.exit(-1);
                }
                _ = c.close(stdin_fd);
                // Note: C original has fcntl(F_GETFL, STDIN_FILENO) with swapped args
                _ = c.fcntl(
                    @as(c_int, c.STDIN_FILENO),
                    c.F_SETFL,
                    c.fcntl(c.F_GETFL, @as(c_int, c.STDIN_FILENO)) & (~@as(c_int, c.O_NONBLOCK)),
                );
            } else if (writefd != null) {
                _ = c.close(in_pipe[1]);
                if (c.dup2(in_pipe[0], c.STDIN_FILENO) == -1) {
                    c.perror("Error assigning stdin in child process");
                    c.exit(-1);
                }
                _ = c.close(in_pipe[0]);
            } else {
                // sparse allocation requirement makes this work
                _ = c.close(c.STDIN_FILENO);
                if (c.open("/dev/null", c.O_RDONLY) == -1) {
                    c.perror("Error disabling stdin in child process");
                    c.exit(-1);
                }
            }

            if (readfd != null) {
                _ = c.close(out_pipe[0]);
                if (c.dup2(out_pipe[1], c.STDOUT_FILENO) == -1) {
                    c.perror("Error assigning stdout in child process");
                    c.exit(-1);
                }
                _ = c.close(out_pipe[1]);
            } else {
                _ = c.close(c.STDOUT_FILENO);
                if (c.open("/dev/null", c.O_WRONLY) == -1) {
                    c.perror("Error disabling stdout in child process");
                    c.exit(-1);
                }
            }

            if (errfd != null) {
                _ = c.close(err_pipe[0]);
                if (c.dup2(err_pipe[1], c.STDERR_FILENO) == -1) {
                    c.perror("Error assigning stderr in child process");
                    c.exit(-1);
                }
                _ = c.close(err_pipe[1]);
            } else {
                _ = c.close(c.STDERR_FILENO);
                if (c.open("/dev/null", c.O_WRONLY) == -1) {
                    // can't perror this one
                    c.exit(-1);
                }
            }

            if (argv != null) {
                environ = env;
                _ = c.execvp(argv[0], @as([*c]const [*c]u8, @ptrCast(&argv[1])));
            } else {
                _ = c.execl(
                    "/bin/sh",
                    "/bin/sh",
                    "-c",
                    command,
                    @as(?*const u8, null),
                    env,
                    @as(?*const u8, null),
                );
            }

            c.perror("Error executing command in child process");
            c.exit(-1);
        },
        else => {
            // Parent - fall through
        },
    }

    if (stdin_fd != -1) {
        _ = c.close(stdin_fd);
    }

    // nonblock is set on import elsewhere
    if (writefd) |wfd| {
        _ = c.close(in_pipe[0]);
        _ = set_cloexec(in_pipe[1]);
        wfd.* = in_pipe[1];
    }
    if (readfd) |rfd| {
        _ = c.close(out_pipe[1]);
        _ = set_cloexec(out_pipe[0]);
        rfd.* = out_pipe[0];
    }
    if (errfd) |efd| {
        _ = c.close(err_pipe[1]);
        _ = set_cloexec(out_pipe[0]);
        efd.* = err_pipe[0];
    }

    return pid;
}

export fn tui_popen_tbltoargv(L: ?*lua_State, ind: c_int) [*c][*c]u8 {
    const count = lua_rawlen(L, ind);
    const raw = c.malloc(@sizeOf([*c]u8) * (count + 1));
    if (raw == null) {
        _ = c.luaL_error(L, "popen: couldn't allocate argument store");
        return null;
    }
    const res: [*c][*c]u8 = @ptrCast(@alignCast(raw));

    res[count] = null;

    for (0..count) |i| {
        c.lua_rawgeti(L, ind, @as(c_int, @intCast(i + 1)));
        res[i] = c.strdup(c.luaL_checklstring(L, -1, null));
        if (res[i] == null) {
            _ = c.luaL_error(L, "popen: couldn't copy argument");
        }
        c.lua_settop(L, -1 - 1);
    }

    return res;
}

export fn tui_popen_tbltoenv(L: ?*lua_State, ind: c_int) [*c][*c]u8 {
    var count: usize = 0;

    c.lua_pushvalue(L, ind);
    c.lua_pushnil(L);

    // One pass to count the number of valid entries, then alloc to match.
    while (c.lua_next(L, -2) != 0) {
        const ltype = c.lua_type(L, -1);
        const ktype = c.lua_type(L, -2);
        if (ktype == c.LUA_TSTRING) {
            if (ltype == c.LUA_TBOOLEAN) {
                if (c.lua_toboolean(L, -1) != 0)
                    count += 1;
            } else if (ltype == c.LUA_TSTRING)
                count += 1;
        }
        c.lua_settop(L, -1 - 1);
    }

    const nb = (count + 1) * @sizeOf([*c]u8);
    if (nb < count) {
        c.lua_settop(L, -1 - 1);
        return null;
    }

    const raw = c.malloc(nb);
    if (raw == null) {
        c.lua_settop(L, -1 - 1);
        return null;
    }
    const env: [*c][*c]u8 = @ptrCast(@alignCast(raw));

    c.lua_pushnil(L);
    count = 0;
    while (c.lua_next(L, -2) != 0) {
        const ltype = c.lua_type(L, -1);
        if (ltype == c.LUA_TBOOLEAN) {
            env[count] = c.strdup(c.lua_tolstring(L, -2, null));
        } else if (ltype == c.LUA_TSTRING) {
            const key = c.lua_tolstring(L, -2, null);
            const val = c.lua_tolstring(L, -1, null);
            const l1 = c.strlen(key);
            const l2 = c.strlen(val);
            const dst_raw = c.malloc(l1 + l2 + 2);
            if (dst_raw) |dst_nonnull| {
                const dst: [*c]u8 = @ptrCast(dst_nonnull);
                _ = c.memcpy(dst, key, l1);
                dst[l1] = '=';
                _ = c.memcpy(dst + l1 + 1, val, l2);
                dst[l1 + l2 + 1] = '\x00';
                env[count] = dst;
            }
        }
        if (env[count] != null)
            count += 1;
        c.lua_settop(L, -1 - 1);
    }
    env[count] = null;
    c.lua_settop(L, -1 - 1);
    return env;
}

export fn tui_popen(L: ?*lua_State) c_int {
    var ci: c_int = 1;
    if (c.lua_type(L, ci) == c.LUA_TUSERDATA) {
        ci += 1;
    }

    var command: [*c]const u8 = null;
    var argv: [*c][*c]u8 = null;

    if (c.lua_type(L, ci) == c.LUA_TTABLE) {
        argv = tui_popen_tbltoargv(L, ci);
    } else if (c.lua_type(L, ci) == c.LUA_TSTRING) {
        command = c.luaL_checklstring(L, ci, null);
    } else {
        _ = c.luaL_error(L, "popen: expected string or table command argument");
    }
    ci += 1;

    var stdin_fd: c_int = -1;
    if (c.lua_type(L, ci) == c.LUA_TUSERDATA) {
        const ib: *[*c]c.struct_nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, ci, "nonblockIO")));
        stdin_fd = ib.*[0].fd;
        ib.*[0].fd = -1;

        // we need to drop the non-blocking status here or children might fail
        _ = c.alt_nbio_close(L, ib);
        ci += 1;
    }

    const mode: [*c]const u8 = c.luaL_optlstring(L, ci, "rwe", null);
    ci += 1;
    var env: [*c][*c]u8 = environ;

    var free_env = false;

    if (c.lua_type(L, ci) == c.LUA_TTABLE) {
        env = tui_popen_tbltoenv(L, ci);
        free_env = true;
    }

    var sin_fd: c_int = -1;
    var sout_fd: c_int = -1;
    var serr_fd: c_int = -1;

    var sin: ?*c_int = null;
    var sout: ?*c_int = null;
    var serr: ?*c_int = null;

    // Nuances with [pty] is that we need both 'sigwinch' and sighup handling, we
    // can do that through our own kill() abstraction and have a 'resize' signal.
    var pid: c.pid_t = undefined;

    if (c.strcmp(mode, "pty") == 0) {
        const pty_fd = c.posix_openpt(c.O_RDWR | c.O_NOCTTY);
        pid = c.fork();
        switch (pid) {
            -1 => {
                _ = c.close(pty_fd);
            },
            0 => {
                // Child
                var attr: c.struct_termios = undefined;
                _ = c.grantpt(pty_fd);
                _ = c.unlockpt(pty_fd);
                const name = c.ptsname(pty_fd);
                const fd = c.open(name, c.O_RDWR | c.O_CLOEXEC | c.O_NOCTTY);

                // New group and terminal with backspace as verase, and input as utf8
                _ = c.setsid();
                _ = c.tcgetattr(pty_fd, &attr);
                // Access termios fields via cast to real layout
                const real_attr: *struct_termios_real = @ptrCast(@alignCast(&attr));
                real_attr.c_cc[c.VERASE] = 0o10;
                real_attr.c_iflag |= IUTF8;
                _ = c.tcsetattr(fd, c.TCSANOW, &attr);

                // Replace stdio- slots with copies of the same fd
                _ = c.dup2(fd, c.STDIN_FILENO);
                _ = c.dup2(fd, c.STDOUT_FILENO);
                _ = c.dup2(fd, c.STDERR_FILENO);
                _ = c.ioctl(fd, c.TIOCSCTTY, @as(c_int, 0));

                if (fd > 2)
                    _ = c.close(fd);

                // Reset all signals to default
                var i: usize = 0;
                while (i < SIGUNUSED) : (i += 1) {
                    _ = c.signal(@intCast(i), null); // SIG_DFL = (void(*)(int))0
                }

                _ = c.close(pty_fd);

                // Finally exec
                if (argv != null) {
                    environ = env;
                    _ = c.execve(argv[0], @ptrCast(&argv[1]), @ptrCast(env));
                } else {
                    _ = c.execlp(
                        command,
                        "/bin/sh",
                        command,
                        @as(?*const u8, null),
                        env,
                        @as(?*const u8, null),
                    );
                }

                c.exit(c.EXIT_FAILURE);
            },
            else => {
                // Parent - duplicate so we can handle close() individually
                sout_fd = pty_fd;
                sin_fd = c.dup(pty_fd);
            },
        }
    } else {
        if (c.strchr(mode, @as(c_int, 'r')) != null)
            sout = &sout_fd;

        if (c.strchr(mode, @as(c_int, 'w')) != null)
            sin = &sin_fd;

        if (c.strchr(mode, @as(c_int, 'e')) != null)
            serr = &serr_fd;

        // need to also return the pid so that waitpid is possible
        pid = popen3(command, stdin_fd, sin, sout, serr, argv, env, false);
    }

    // only if env wasn't grabbed from ext-environ
    if (free_env) {
        var i: usize = 0;
        while (env[i] != null) : (i += 1) {
            c.free(env[i]);
        }
        c.free(@as(?*anyopaque, @ptrCast(env)));
    }

    if (argv != null) {
        var i: usize = 0;
        while (argv[i] != null) : (i += 1) {
            c.free(argv[i]);
        }
        c.free(@as(?*anyopaque, @ptrCast(argv)));
    }

    if (pid == -1)
        return 0;

    _ = c.alt_nbio_import(L, sin_fd, c.O_WRONLY, null, null);
    _ = c.alt_nbio_import(L, sout_fd, c.O_RDONLY, null, null);
    _ = c.alt_nbio_import(L, serr_fd, c.O_RDONLY, null, null);
    c.lua_pushnumber(L, @floatFromInt(pid));

    return 4;
}

export fn tui_pty_resize(L: ?*lua_State) c_int {
    const io: *[*c]c.struct_nonblock_io = @ptrCast(@alignCast(c.luaL_checkudata(L, 1, "nonblockIO")));
    var ws: c.struct_winsize = undefined;

    ws.ws_col = @intCast(c.luaL_checkinteger(L, 2));
    ws.ws_row = @intCast(c.luaL_checkinteger(L, 3));

    if (io.* == null) {
        _ = c.luaL_error(L, "pty_resize called on closed nbio");
    }

    c.lua_pushboolean(L, @intFromBool(c.ioctl(io.*.*.fd, c.TIOCSWINSZ, &ws) == 0));
    return 1;
}

export fn tui_pid_signal(L: ?*lua_State) c_int {
    var ci: c_int = 1;
    if (c.lua_type(L, ci) == c.LUA_TUSERDATA) {
        ci += 1;
    }

    const pid: c.pid_t = @intCast(c.luaL_checkinteger(L, ci));
    ci += 1;
    var sig: c_int = c.SIGKILL;

    if (c.lua_type(L, ci) == c.LUA_TSTRING) {
        const s = c.lua_tolstring(L, ci, null);
        if (c.strcasecmp(s, "kill") == 0) {
            sig = c.SIGKILL;
        } else if (c.strcasecmp(s, "hup") == 0) {
            sig = c.SIGHUP;
        } else if (c.strcasecmp(s, "user1") == 0) {
            sig = c.SIGUSR1;
        } else if (c.strcasecmp(s, "user2") == 0) {
            sig = c.SIGUSR2;
        } else if (c.strcasecmp(s, "stop") == 0) {
            sig = c.SIGSTOP;
        } else if (c.strcasecmp(s, "quit") == 0) {
            sig = c.SIGQUIT;
        } else if (c.strcasecmp(s, "continue") == 0) {
            sig = c.SIGCONT;
        } else {
            _ = c.luaL_error(L, "unknown signal requested");
        }
    } else if (c.lua_type(L, ci) == c.LUA_TNUMBER) {
        sig = @intFromFloat(c.lua_tonumber(L, ci));
    } else {
        _ = c.luaL_error(L, "tui:pkill(signal) - wrong / missing type for signal");
    }

    c.lua_pushboolean(L, @intFromBool(c.kill(pid, sig) == 0));
    return 1;
}

export fn tui_pid_status(L: ?*lua_State) c_int {
    var ci: c_int = 1;
    if (c.lua_type(L, ci) == c.LUA_TUSERDATA) {
        ci += 1;
    }

    const pid: c.pid_t = @intCast(c.luaL_checkinteger(L, ci));
    var status: c_int = undefined;
    const res = c.waitpid(pid, &status, c.WNOHANG);
    if (res == -1) {
        c.lua_pushboolean(L, 0);
        return 1;
    } else if (res != 0) {
        if (c.WIFEXITED(status)) {
            c.lua_pushboolean(L, 0);
            c.lua_pushnumber(L, @floatFromInt(c.WEXITSTATUS(status)));
            return 2;
        }
    }

    c.lua_pushboolean(L, 1);
    return 1;
}
