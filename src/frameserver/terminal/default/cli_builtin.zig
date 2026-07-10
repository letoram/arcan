// Zig reimplementation of cli_builtin.c
// Drop-in C-ABI-compatible replacement for terminal CLI builtins.
//
// Exports: cli_get_builtin, commands
//
const std = @import("std");

// Extern C declarations
extern "c" fn malloc(size: usize) ?*anyopaque;
extern "c" fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
extern "c" fn free(ptr: ?*anyopaque) void;
extern "c" fn strdup(s: [*c]const u8) [*c]u8;
extern "c" fn getenv(name: [*c]const u8) [*c]u8;
extern "c" fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) c_int;
extern "c" fn getcwd(buf: [*c]u8, size: usize) [*c]u8;
extern "c" fn chdir(path: [*c]const u8) c_int;
extern "c" fn close(fd: c_int) c_int;

const posix = struct {
    extern "c" fn open(path: [*c]const u8, flags: c_int, ...) c_int;
    extern "c" fn stat(noalias path: [*c]const u8, noalias buf: *std.c.Stat) c_int;
};

// errno access
extern "c" fn __errno_location() *c_int;
inline fn getErrno() c_int {
    return __errno_location().*;
}

const ERANGE: c_int = 34;
const ENOENT: c_int = 2;
const EACCES: c_int = 13;
const O_RDONLY: c_int = 0;

// Types matching cli_builtin.h
// These must match the C layout from cli_builtin.h exactly.

const LaunchMode = enum(c_int) {
    LAUNCH_UNSET = 0,
    LAUNCH_VT100 = 1,
    LAUNCH_TUI = 2,
    LAUNCH_WL = 3,
    LAUNCH_X11 = 4,
    LAUNCH_SHMIF = 5,
};

const ExtCmd = extern struct {
    id: u32 = 0,
    flags: c_int = 0,
    argv: [*c][*c]u8 = null,
    env: [*c][*c]u8 = null,
    wd: [*c]u8 = null,
    mode: LaunchMode = .LAUNCH_UNSET,
    stall: bool = false,
    closure: ?*const fn (usize) callconv(.c) void = null,
    closure_tag: usize = 0,
};

const ExecFn = *const fn (
    state: *CliState,
    argv: [*c][*c]u8,
    ofs: *isize,
    err: *[*c]u8,
) callconv(.c) ?*ExtCmd;

const CliCmdFn = *const fn (
    state: *CliState,
    argv: [*c]const [*c]const u8,
    n_elem: usize,
    command: c_int,
    feedback: [*c]const [*c]const u8,
    n_results: *usize,
) callconv(.c) c_int;

const CliCommand = extern struct {
    name: [*c]const u8,
    exec: ?ExecFn,
    cli_command: ?CliCmdFn,
};

const CliState = extern struct {
    env: [*c][*c]u8,
    cwd: [*c]u8,
    mode: LaunchMode,
    alive: bool,
    bgalpha: u8,
    die_on_finish: bool,
    id_counter: u32,
    pending: [4]ExtCmd,
    blocked: bool,
    in_debug: [*c]u8,
    prompt: ?*anyopaque, // struct tui_cell* — opaque, never dereferenced here
    prompt_sz: usize,
};

// Internal state
const CmdState = struct {
    cwd: [*c]u8 = null,
    capacity: usize = 0,
    dynamic: bool = false,
};

var current: CmdState = .{};

// synch_cwd: extract current working directory into cmd_state
fn synchCwd(C: *CmdState, sync_env: bool) void {
    // ensure 'cwd' is allocated
    if (C.capacity == 0) {
        const ptr = malloc(4096) orelse return;
        C.cwd = @ptrCast(ptr);
        C.capacity = 4096;
    }

    if (getcwd(C.cwd, C.capacity) == null) {
        // the 'lovely' getcwd lacking dynamic option
        while (getErrno() == ERANGE) {
            const new_sz = C.capacity * 2;
            const new_ptr = realloc(@ptrCast(C.cwd), new_sz);
            if (new_ptr == null) {
                _ = std.fmt.bufPrintZ(C.cwd[0..new_sz], "(out of memory)", .{}) catch {};
                return;
            }
            C.cwd = @ptrCast(new_ptr);
            C.capacity = new_sz;
            if (getcwd(C.cwd, C.capacity) != null)
                break; // equivalent of goto ok
            // continue loop if still ERANGE
        } else {
            // loop ended without break — getcwd failed with non-ERANGE error
            const errno_val = getErrno();
            if (errno_val == ENOENT) {
                _ = std.fmt.bufPrintZ(C.cwd[0..C.capacity], "(unlinked)", .{}) catch {};
                return;
            }
            if (errno_val == EACCES) {
                _ = std.fmt.bufPrintZ(C.cwd[0..C.capacity], "(no permission)", .{}) catch {};
                return;
            }
            _ = std.fmt.bufPrintZ(C.cwd[0..C.capacity], "(unknown)", .{}) catch {};
            return;
        }
    }

    // ok:
    if (!sync_env)
        return;

    const lastpwd = getenv("PWD");
    if (lastpwd != null)
        _ = setenv("OLDPWD", lastpwd, 1);

    _ = setenv("PWD", C.cwd, 1);
}

// cmd_cd
fn cmdCd(state: *CliState, argv: [*c][*c]u8, ofs: *isize, err: *[*c]u8) callconv(.c) ?*ExtCmd {
    _ = state;
    ofs.* = -1;
    err.* = null;

    // empty argv? try $HOME
    if (argv[1] == null) {
        const home = getenv("HOME");
        if (home == null)
            return null;

        if (chdir(home) != 0)
            return null;

        synchCwd(&current, true);
        return null;
    }

    if (chdir(argv[1]) == 0) {
        synchCwd(&current, true);
    }

    return null;
}

// cmd_mode
fn cmdMode(state: *CliState, argv: [*c][*c]u8, ofs: *isize, err: *[*c]u8) callconv(.c) ?*ExtCmd {
    _ = ofs;
    _ = err;

    if (argv[1] == null)
        return null;

    const arg: [*:0]const u8 = @ptrCast(argv[1]);
    const s = std.mem.span(arg);

    if (std.mem.eql(u8, s, "x11")) {
        state.mode = .LAUNCH_X11;
    } else if (std.mem.eql(u8, s, "tui")) {
        state.mode = .LAUNCH_TUI;
    } else if (std.mem.eql(u8, s, "wl") or std.mem.eql(u8, s, "wayland")) {
        state.mode = .LAUNCH_WL;
    } else if (std.mem.eql(u8, s, "arcan")) {
        state.mode = .LAUNCH_SHMIF;
    } else if (std.mem.eql(u8, s, "vt100")) {
        state.mode = .LAUNCH_VT100;
    }

    return null;
}

// get_decode_bin
fn getDecodeBin() [*c]const u8 {
    var statbuf: std.c.Stat = undefined;
    if (posix.stat("/usr/local/bin/afsrv_decode", &statbuf) != -1)
        return "/usr/local/bin/afsrv_decode";

    if (posix.stat("/usr/bin/afsrv_decode", &statbuf) != -1)
        return "/usr/bin/afsrv_decode";

    return "afsrv_decode";
}

// drop_descriptor
fn dropDescriptor(tag: usize) callconv(.c) void {
    _ = close(@intCast(tag));
}

// cmd_open
fn cmdOpen(state: *CliState, argv: [*c][*c]u8, ofs: *isize, err: *[*c]u8) callconv(.c) ?*ExtCmd {
    _ = state;
    _ = ofs;
    _ = err;

    if (argv[1] == null)
        return null;

    const bin = getDecodeBin();

    const fd = posix.open(argv[1], O_RDONLY);
    if (fd == -1)
        return null;

    // setup env array. `[*c]` is already nullable; wrapping it in `?` gives a
    // distinct layout that the SH aarch64 backend rejects as a bad bitcast
    // from `?*anyopaque`. Plain `[*c][*c]u8` round-trips cleanly and still
    // compares to `null`.
    const env_ptr: [*c][*c]u8 = @ptrCast(@alignCast(malloc(@sizeOf([*c]u8) * 2)));
    if (env_ptr == null) {
        _ = close(fd);
        return null;
    }
    env_ptr[0] = null;
    env_ptr[1] = null;

    // allocate result
    const res_raw = malloc(@sizeOf(ExtCmd));
    if (res_raw == null) {
        _ = close(fd);
        free(@ptrCast(env_ptr));
        return null;
    }
    const res: *ExtCmd = @ptrCast(@alignCast(res_raw));
    res.* = std.mem.zeroes(ExtCmd);
    res.flags = 0xf; // detach and null stdios
    res.env = env_ptr;
    res.mode = .LAUNCH_SHMIF;

    // allocate argv (same [*c] rationale as env_ptr above)
    const argv_ptr: [*c][*c]u8 = @ptrCast(@alignCast(malloc(@sizeOf([*c]u8) * 2)));
    if (argv_ptr == null) {
        _ = close(fd);
        free(@ptrCast(env_ptr));
        free(res_raw);
        return null;
    }

    argv_ptr[0] = strdup(bin);
    argv_ptr[1] = null;
    res.argv = argv_ptr;

    // setup ARCAN_ARG=proto=media:fd=%d
    var env_buf: [128]u8 = undefined;
    const env_str = std.fmt.bufPrintZ(&env_buf, "ARCAN_ARG=proto=media:fd={d}", .{fd}) catch return null;
    env_ptr[0] = strdup(env_str.ptr);

    res.closure = @ptrCast(&dropDescriptor);
    res.closure_tag = @intCast(fd);

    return res;
}

// cmd_exit
fn cmdExit(state: *CliState, argv: [*c][*c]u8, ofs: *isize, err: *[*c]u8) callconv(.c) ?*ExtCmd {
    _ = argv;
    _ = ofs;
    _ = err;
    state.alive = false;
    return null;
}

// cmd_debugstall
fn cmdDebugstall(state: *CliState, argv: [*c][*c]u8, ofs: *isize, err: *[*c]u8) callconv(.c) ?*ExtCmd {
    _ = argv;
    _ = ofs;
    _ = err;
    if (state.in_debug != null) {
        state.in_debug = null;
        return null;
    }

    state.in_debug = strdup("ARCAN_FRAMESERVER_DEBUGSTALL=10");
    return null;
}

// commands table
export var commands: [5]CliCommand = .{
    .{
        .name = "cd",
        .exec = @ptrCast(&cmdCd),
        .cli_command = null,
    },
    .{
        .name = "mode",
        .exec = @ptrCast(&cmdMode),
        .cli_command = null,
    },
    .{
        .name = "open",
        .exec = @ptrCast(&cmdOpen),
        .cli_command = null,
    },
    .{
        .name = "exit",
        .exec = @ptrCast(&cmdExit),
        .cli_command = null,
    },
    .{
        .name = "debugstall",
        .exec = @ptrCast(&cmdDebugstall),
        .cli_command = null,
    },
};

// cli_get_builtin
export fn cli_get_builtin(cmd: [*c]const u8) callconv(.c) ?*CliCommand {
    if (cmd == null)
        return null;

    const cmd_span = std.mem.span(@as([*:0]const u8, @ptrCast(cmd)));
    if (cmd_span.len == 0)
        return null;

    for (&commands) |*entry| {
        const name: [*:0]const u8 = @ptrCast(entry.name);
        if (std.mem.eql(u8, cmd_span, std.mem.span(name)))
            return entry;
    }

    return null;
}
