// Zig reimplementation of platform/exec.c
// Drop-in C-ABI-compatible replacement for process execution.
//
// Exports: shmif_platform_execve
//
const std = @import("std");
const builtin = @import("builtin");
const is_freestanding = (builtin.os.tag == .freestanding);
const c = @import("shmif_types");

// ---- libc externs ----
extern fn fork() c.pid_t;
extern fn execve(path: [*c]const u8, argv: [*c]const [*c]u8, envp: [*c]const [*c]u8) c_int;
extern fn open(path: [*c]const u8, oflag: c_int, ...) c_int;
extern fn dup2(oldfd: c_int, newfd: c_int) c_int;
extern fn close(fd: c_int) c_int;
extern fn pipe(pipefd: *[2]c_int) c_int;
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn setsid() c.pid_t;
extern fn signal(sig: c_int, handler: ?*const fn (c_int) callconv(.c) void) ?*const fn (c_int) callconv(.c) void;
extern fn _exit(status: c_int) noreturn;
extern fn malloc(size: usize) ?*anyopaque;
extern fn free(ptr: ?*anyopaque) void;
extern fn memset(s: ?*anyopaque, ch: c_int, n: usize) ?*anyopaque;
extern fn strdup(s: [*c]const u8) [*c]u8;
extern fn snprintf(noalias buf: [*c]u8, size: usize, noalias fmt: [*c]const u8, ...) c_int;

// extern environ
extern var environ: [*c][*c]u8;

// SIG_DFL as a typed function pointer for the signal() call
const SIG_DFL: ?*const fn (c_int) callconv(.c) void = null;

const SIGUNUSED: c_int = 31;

// ---- static helper: ensure_at ----
// Used for /dev/null mapping of stdio descriptors
fn ensure_at(num: c_int, path: [*c]const u8) void {
    const fd = open(path, c.O_RDWR);
    _ = dup2(fd, num);
    if (fd != num)
        _ = close(fd);
}

// ---- helper to clean environment ----
// Sweep from ofs downwards, free strdups, then free the array
fn clean_env(new_env: [*c][*c]u8, ofs_in: usize) void {
    if (ofs_in == 0) {
        free(@ptrCast(new_env));
        return;
    }
    var i: usize = ofs_in;
    while (i > 0) {
        i -= 1;
        free(@ptrCast(new_env[i]));
    }
    free(@ptrCast(new_env));
}

// ---- shmif_platform_execve ----

export fn shmif_platform_execve(
    socket_fd: c_int,
    mem_fd: c_int,
    path: [*c]const u8,
    argv: [*c]const [*c]u8,
    env_in: [*c]const [*c]u8,
    opts: c_int,
    fds: [*c][*c]c_int,
    fdset_sz: usize,
    err: [*c][*c]u8,
) c.pid_t {
    if (is_freestanding) return -1;
    // Prepare env even if there isn't env as we need to propagate connection
    // primitives etc.
    var env: [*c]const [*c]u8 = env_in;
    if (env == null)
        env = @ptrCast(environ);

    var nelem: usize = 0;
    if (env != null) {
        while (env[nelem] != null) : (nelem += 1) {}
    }
    nelem += 4; // ARCAN_SOCKIN_MEMFD, ARCAN_SOCKIN_FD, ARCAN_HANDOVER, NULL

    const env_sz = nelem * @sizeOf([*c]u8);
    const raw = malloc(env_sz) orelse {
        if (err != null)
            err[0] = strdup("failed to alloc/build env");
        return -1;
    };
    const new_env: [*c][*c]u8 = @ptrCast(@alignCast(raw));
    _ = memset(raw, 0, env_sz);

    // duplicate the input environment
    var ofs: usize = 0;
    if (env != null) {
        while (env[ofs] != null) {
            const duped = strdup(env[ofs]);
            if (duped == null) {
                if (err != null)
                    err[0] = null;
                clean_env(new_env, ofs);
                return -1;
            }
            new_env[ofs] = duped;
            ofs += 1;
        }
    }

    // expand with information about the connection primitives
    var tmpbuf: [1024]u8 = undefined;
    _ = snprintf(&tmpbuf, @sizeOf(@TypeOf(tmpbuf)), "ARCAN_SOCKIN_MEMFD=%d", mem_fd);
    const dup1 = strdup(&tmpbuf);
    if (dup1 == null) {
        clean_env(new_env, ofs);
        return -1;
    }
    new_env[ofs] = dup1;
    ofs += 1;

    _ = snprintf(&tmpbuf, @sizeOf(@TypeOf(tmpbuf)), "ARCAN_SOCKIN_FD=%d", socket_fd);
    const dup2_str = strdup(&tmpbuf);
    if (dup2_str == null) {
        clean_env(new_env, ofs);
        return -1;
    }
    new_env[ofs] = dup2_str;
    ofs += 1;

    const dup3 = strdup("ARCAN_HANDOVER=1");
    if (dup3 == null) {
        clean_env(new_env, ofs);
        return -1;
    }
    new_env[ofs] = dup3;
    ofs += 1;

    var stdin_src: c_int = c.STDIN_FILENO;
    var stdout_src: c_int = c.STDOUT_FILENO;
    var stderr_src: c_int = c.STDERR_FILENO;

    // if custom stdin/stdout is desired, fix that now
    var close_in: bool = false;
    var close_out: bool = false;
    var close_err: bool = false;

    // stdin setup
    if (fdset_sz > 0) {
        if (fds[0] == null) {
            stdin_src = -1;
        } else if (fds[0].* == -1) {
            var pin: [2]c_int = undefined;
            if (pipe(&pin) != 0) {
                if (err != null)
                    err[0] = strdup("failed to build stdin pipe");
                clean_env(new_env, ofs);
                return -1;
            }
            stdin_src = pin[0];
            fds[0].* = pin[1];
            close_in = true;
        } else {
            stdin_src = fds[0].*;
        }
    }

    // stdout setup
    if (fdset_sz > 1) {
        if (fds[1] == null) {
            stdout_src = -1;
        } else if (fds[1].* == -1) {
            var pout: [2]c_int = undefined;
            if (pipe(&pout) != 0) {
                if (err != null)
                    err[0] = strdup("failed to build stdout pipe");
                clean_env(new_env, ofs);
                return -1;
            }
            stdout_src = pout[1];
            fds[1].* = pout[0];
            close_out = true;
        } else {
            stdout_src = fds[1].*;
        }
    }

    // stderr setup
    if (fdset_sz > 2) {
        if (fds[2] == null) {
            stderr_src = -1;
        } else if (fds[2].* == -1) {
            var perr_fds: [2]c_int = undefined;
            if (pipe(&perr_fds) != 0) {
                if (err != null)
                    err[0] = strdup("failed to build stderr pipe");
                clean_env(new_env, ofs);
                return -1;
            }
            stderr_src = perr_fds[1];
            fds[2].* = perr_fds[0];
            close_err = true;
        } else {
            stderr_src = fds[2].*;
        }
    }

    // null-terminate
    new_env[ofs] = null;

    const pid = fork();
    if (pid == 0) {
        // -- child process --

        // ensure that the socket is not CLOEXEC
        const sock_flags = fcntl(socket_fd, c.F_GETFD);
        if (sock_flags != -1)
            _ = fcntl(socket_fd, c.F_SETFD, sock_flags & (~@as(c_int, c.FD_CLOEXEC)));

        // set up stdin
        if (stdin_src != -1) {
            if (stdin_src != c.STDIN_FILENO) {
                _ = dup2(stdin_src, c.STDIN_FILENO);
                _ = close(stdin_src);
            }
        } else {
            ensure_at(c.STDIN_FILENO, "/dev/null");
        }

        // set up stdout
        if (stdout_src != -1) {
            if (stdout_src != c.STDOUT_FILENO) {
                _ = dup2(stdout_src, c.STDOUT_FILENO);
                _ = close(stdout_src);
            }
        } else {
            ensure_at(c.STDOUT_FILENO, "/dev/null");
        }

        // set up stderr
        if (stderr_src != -1) {
            if (stderr_src != c.STDERR_FILENO) {
                _ = dup2(stderr_src, c.STDERR_FILENO);
                _ = close(stderr_src);
            }
        } else {
            ensure_at(c.STDERR_FILENO, "/dev/null");
        }

        // clear CLOEXEC on passed fds beyond stdin/stdout/stderr
        for (2..fdset_sz) |i| {
            if (fds[i] == null or fds[i].* == -1)
                continue;
            const fd_flags = fcntl(fds[i].*, c.F_GETFD);
            if (fd_flags != -1)
                _ = fcntl(fds[i].*, c.F_SETFD, fd_flags & (~@as(c_int, c.FD_CLOEXEC)));
        }

        // close the other end of created pipes in child
        if (close_out)
            _ = close(fds[1].*);
        if (close_in)
            _ = close(fds[0].*);
        if (close_err)
            _ = close(fds[2].*);

        // double-fork if detach is desired
        if ((opts & c.EXECVE_DETACH_PROCESS) != 0) {
            const pid2 = fork();
            if (pid2 != 0) {
                if (pid2 > 0)
                    _exit(c.EXIT_SUCCESS)
                else
                    _exit(c.EXIT_FAILURE);
            }
        }

        if ((opts & c.EXECVE_DETACH_KEEP_SESSION) == 0)
            _ = setsid();

        if ((opts & c.EXECVE_DETACH_RESET_MASK) != 0) {
            var sig: c_int = 1;
            while (sig < SIGUNUSED) : (sig += 1) {
                _ = signal(sig, SIG_DFL);
            }
        }

        // GNU or BSD4.2
        _ = execve(path, argv, @ptrCast(new_env));
        _exit(c.EXIT_FAILURE);
    }

    // -- parent process --
    if (close_out)
        _ = close(stdout_src);
    if (close_in)
        _ = close(stdin_src);
    if (close_err)
        _ = close(stderr_src);

    clean_env(new_env, ofs);
    return pid;
}
