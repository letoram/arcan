// Copyright 2014-2016, Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: http://arcan-fe.com
//
// Zig port of frameserver.c — chainloader / frameserver entry point.

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ stdio.h, stdlib.h, string.h, ... })`
// block. Keeps the `c.X` spellings used below. Each alias routes to the
// appropriate hand-written replacement module (zero `@cImport` left).
const shmif = @import("shmif_types");
const libc = @import("posix");
const fsrv_opts = @import("fsrv_opts");

const c = struct {
    // libc — stdio streams + printf family
    // (stdout/stderr are extern vars — read at runtime, can't be aliased
    // as comptime consts, so callers reach into `libc` directly.)
    pub const fflush = libc.fflush;
    pub const fclose = libc.fclose;
    pub const fopen = libc.fopen;
    pub const fprintf = libc.fprintf;
    pub const freopen = libc.freopen;
    pub const printf = libc.printf;
    pub const setlinebuf = libc.setlinebuf;
    pub const snprintf = libc.snprintf;

    // libc — memory + strings
    pub const malloc = libc.malloc;
    pub const strcmp = libc.strcmp;
    pub const strerror = libc.strerror;
    pub const strlen = libc.strlen;
    pub const strtoul = libc.strtoul;

    // libc — process + env
    pub const execv = libc.execv;
    pub const getenv = libc.getenv;
    pub const getpid = libc.getpid;
    pub const setsid = libc.setsid;
    pub const sleep = libc.sleep;

    // libc — time
    pub const localtime = libc.localtime;
    pub const strftime = libc.strftime;
    pub const time = libc.time;

    // libc — dirent + fs
    pub const closedir = libc.closedir;
    pub const dirfd = libc.dirfd;
    pub const opendir = libc.opendir;
    pub const readdir = libc.readdir;
    pub const readlinkat = libc.readlinkat;

    // libc — misc
    pub const _errno = libc.__errno_location;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
};

const st = shmif;

// Arcan extern declarations not in shmif_types
extern "c" fn arcan_shmif_open_ext(flags: c_uint, arg: *[*c]st.struct_arg_arr, ext: st.struct_shmif_open_ext, ext_sz: usize) st.struct_arcan_shmif_cont;
extern "c" fn arg_unpack(str: ?[*:0]const u8) [*c]st.struct_arg_arr;
extern "c" fn arg_cleanup(arr: [*c]st.struct_arg_arr) void;

const mode_fun = *const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int;

// b.addOptions emits default_mode as `?[]const u8` (no sentinel). The
// underlying memory is a NUL-terminated string literal — reinterpret the
// pointer as a C string for streql/fprintf calls below.
const default_mode_z: ?[*:0]const u8 = if (fsrv_opts.default_mode) |m|
    @ptrCast(m.ptr)
else
    null;

// External frameserver entry points — defined in other compilation units.
// Only declare the ones that are enabled via build-time defines.
const afsrv_decode = if (fsrv_opts.enable_decode)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_decode" })
else
    @as(?mode_fun, null);

const afsrv_terminal = if (fsrv_opts.enable_terminal)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_terminal" })
else
    @as(?mode_fun, null);

const afsrv_encode = if (fsrv_opts.enable_encode)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_encode" })
else
    @as(?mode_fun, null);

const afsrv_remoting = if (fsrv_opts.enable_remoting)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_remoting" })
else
    @as(?mode_fun, null);

const afsrv_game = if (fsrv_opts.enable_game)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_game" })
else
    @as(?mode_fun, null);

const afsrv_avfeed = if (fsrv_opts.enable_avfeed)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_avfeed" })
else
    @as(?mode_fun, null);

const afsrv_bun = if (fsrv_opts.enable_bun)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_bun" })
else
    @as(?mode_fun, null);

const afsrv_probe = if (fsrv_opts.enable_probe)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_probe" })
else
    @as(?mode_fun, null);

const afsrv_netcl = if (fsrv_opts.enable_net)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_netcl" })
else
    @as(?mode_fun, null);

const afsrv_netsrv = if (fsrv_opts.enable_net)
    @extern(*const fn (?*st.struct_arcan_shmif_cont, [*c]st.struct_arg_arr) callconv(.c) c_int, .{ .name = "afsrv_netsrv" })
else
    @as(?mode_fun, null);

fn close_logdev() void {
    _ = c.fflush(libc.stderr);
}

fn toggle_logdev(prefix: [*:0]const u8) void {
    const logdir: ?[*:0]const u8 = c.getenv("ARCAN_FRAMESERVER_LOGDIR");

    if (logdir == null)
        return;

    var timeb: [16]u8 = undefined;
    const t = c.time(null);
    const basetime = c.localtime(&t) orelse return;
    _ = c.strftime(&timeb, timeb.len - 1, "%y%m%d_%H%M", basetime);

    const logdir_nn: [*:0]const u8 = logdir.?;
    const logdir_len = c.strlen(logdir_nn);
    const prefix_len = c.strlen(prefix);
    const logbuf_sz = logdir_len +
        @as(usize, "/fsrv__yymmddhhss__65536.txt".len) + prefix_len;
    const logbuf_ptr = c.malloc(logbuf_sz) orelse return;
    const logbuf: [*c]u8 = @ptrCast(logbuf_ptr);

    _ = c.snprintf(
        logbuf,
        @intCast(logbuf_sz),
        "%s/fsrv_%s_%s_%d.txt",
        logdir_nn,
        prefix,
        &timeb,
        @as(c_int, @intCast(c.getpid())),
    );
    if (c.freopen(logbuf, "a", libc.stderr) == null) {
        if (c.freopen("/dev/null", "a", libc.stderr) == null) {
            _ = c.fclose(libc.stderr);
        }
    }
    c.setlinebuf(libc.stderr);
}

fn dumpargs(argc: c_int, argv: [*c][*c]u8) void {
    _ = c.printf("invalid number of arguments (%d):\n", argc);
    _ = c.printf(
        "[1 mode] : %s\n",
        if (argc > 1 and argv[1] != null) @as([*c]const u8, argv[1]) else @as([*c]const u8, ""),
    );
    _ = c.printf(
        "environment (ARCAN_ARG) : %s\n",
        if (c.getenv("ARCAN_ARG") != null) c.getenv("ARCAN_ARG") else @as([*c]const u8, ""),
    );
    _ = c.printf(
        "environment (ARCAN_SOCKIN_FD) : %s\n",
        if (c.getenv("ARCAN_SOCKIN_FD") != null) c.getenv("ARCAN_SOCKIN_FD") else @as([*c]const u8, ""),
    );
    _ = c.printf(
        "environment (ARCAN_CONNPATH) : %s\n",
        if (c.getenv("ARCAN_CONNPATH") != null) c.getenv("ARCAN_CONNPATH") else @as([*c]const u8, ""),
    );
}

fn launch_mode(
    modestr: [*:0]const u8,
    fptr: mode_fun,
    id: c_uint,
    flags: c_uint,
    altarg: ?[*:0]u8,
) c_int {
    const debug: ?[*:0]const u8 = c.getenv("ARCAN_FRAMESERVER_DEBUGSTALL");

    if (comptime !fsrv_opts.is_chainloader) {
        if (debug == null) {
            toggle_logdev(modestr);
        }
    }

    {
        const dbg = c.fopen("/tmp/arcan_fsrv_launch.log", "a");
        if (dbg != null) {
            const sockin = c.getenv("ARCAN_SOCKIN_FD");
            const connp = c.getenv("ARCAN_CONNPATH");
            _ = c.fprintf(dbg, "launch_mode(%s): SOCKIN_FD=%s CONNPATH=%s\n",
                modestr,
                if (sockin != null) sockin else @as([*c]const u8, "(null)"),
                if (connp != null) connp else @as([*c]const u8, "(null)"));
            _ = c.fclose(dbg);
        }
    }

    var arg: [*c]st.struct_arg_arr = null;
    var con = arcan_shmif_open_ext(
        @bitCast(flags),
        &arg,
        st.struct_shmif_open_ext{
            .type = if (@typeInfo(@TypeOf(@as(st.struct_shmif_open_ext, undefined).type)) == .@"enum")
                @enumFromInt(id)
            else
                @bitCast(id),
            .title = null,
            .ident = null,
            .guid = .{ 0, 0 },
        },
        @sizeOf(st.struct_shmif_open_ext),
    );

    {
        const dbg = c.fopen("/tmp/arcan_fsrv_launch.log", "a");
        if (dbg != null) {
            _ = c.fprintf(dbg, "launch_mode(%s): open_ext done addr=%s\n",
                modestr, if (con.addr != null) @as([*c]const u8, "OK") else @as([*c]const u8, "NULL"));
            _ = c.fclose(dbg);
        }
    }

    if (arg == null and altarg != null) {
        arg = arg_unpack(altarg);
    }

    if (debug) |dbg| {
        const sleeplen = c.strtoul(dbg, null, 10);

        var ev: st.arcan_event = st.arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = st.EVENT_EXTERNAL_IDENT;
        _ = st.arcan_shmif_enqueue(&con, &ev);
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data)),
            "debugstall:%d:%zu",
            @as(c_int, @intCast(sleeplen)),
            @as(usize, @intCast(c.getpid())),
        );

        if (sleeplen <= 0) {
            _ = c.fprintf(
                libc.stdout,
                "\x1b[1mARCAN_FRAMESERVER_DEBUGSTALL,\x1b[0m " ++
                    "spin-waiting for debugger.\n \tAttach to pid: " ++
                    "\x1b[32m%d\x1b[39m\x1b[0m and break out of loop" ++
                    " (set loop = 0)\n",
                c.getpid(),
            );

            // volatile spin-wait for debugger attach
            var loop: c_int = 1;
            const loop_ptr: *volatile c_int = &loop;
            while (loop_ptr.* == 1) {}
        } else {
            _ = c.fprintf(
                libc.stdout,
                "\x1b[1mARCAN_FRAMESERVER_DEBUGSTALL set, waiting %d s.\n" ++
                    "\tfor debugging/tracing, attach to pid: \x1b[32m%d\x1b[39m\x1b[0m\n",
                @as(c_int, @intCast(sleeplen)),
                @as(c_int, @intCast(c.getpid())),
            );
            _ = c.sleep(@intCast(sleeplen));
        }
    }

    return fptr(if (con.addr != null) &con else null, arg);
}

fn streql(a: ?[*:0]const u8, b: [*:0]const u8) bool {
    if (a == null) return false;
    return c.strcmp(a.?, b) == 0;
}

/// Personality-dispatch entry point. The may binary's mainArgs invokes
/// this when argv[0] is `afsrv_<mode>` or `arcan_frameserver`. mode
/// extraction lives in may; here we just route to chainloader or
/// frameserver_main based on the build-time fsrv_opts.is_chainloader
/// (off for may — all frameservers run in-process, no exec hop).
export fn frameserver_entry(argc: c_int, argv: [*c][*c]u8) c_int {
    if (comptime fsrv_opts.is_chainloader) {
        return chainloader_main(argc, argv);
    } else {
        return frameserver_main(argc, argv);
    }
}

/// Re-exposed so may's mainArgs can call directly without going through
/// the chainloader fork in personality dispatch.
export fn frameserver_dispatch(argc: c_int, argv: [*c][*c]u8) c_int {
    return frameserver_main(argc, argv);
}

/// Re-exposed for the `arcan_frameserver` personality (which mirrors
/// upstream's exec-style chainloader; may uses it for compatibility
/// when the engine still spawns via `arcan_frameserver <mode>`).
export fn frameserver_chainload(argc: c_int, argv: [*c][*c]u8) c_int {
    return chainloader_main(argc, argv);
}

fn chainloader_main(argc: c_int, argv: [*c][*c]u8) c_int {
    if (argc != 2) {
        dumpargs(argc, argv);
        return c.EXIT_FAILURE;
    }

    if (argv[0] == null)
        return c.EXIT_FAILURE;

    const arg0: [*:0]u8 = @ptrCast(argv[0]);

    // Strip trailing slashes
    var i: usize = c.strlen(arg0);
    if (i > 0) i -= 1;
    while (i > 0 and arg0[i] == '/') {
        arg0[i] = 0;
        i -= 1;
    }
    // Walk back to find the last '/' separator
    while (i > 0 and arg0[i - 1] != '/') {
        i -= 1;
    }
    if (i > 0) {
        arg0[i - 1] = 0;
    }

    const dirn: [*:0]const u8 = arg0;
    const base_ptr: [*:0]const u8 = arg0 + i;

    const base: [*:0]const u8 = if (c.strcmp(base_ptr, "arcan_frameserver") == 0)
        "afsrv"
    else
        base_ptr;

    const mode: [*:0]const u8 = @ptrCast(argv[1]);

    const bin_sz = c.strlen(dirn) + c.strlen(base) + c.strlen(mode) + 3;
    const newarg_ptr = c.malloc(bin_sz) orelse return c.EXIT_FAILURE;
    const newarg_buf: [*c]u8 = @ptrCast(newarg_ptr);
    _ = c.snprintf(newarg_buf, @intCast(bin_sz), "%s/%s_%s", dirn, base, mode);

    // We no longer need the mode argument
    argv[1] = null;
    argv[0] = newarg_buf;

    _ = c.setsid();

    _ = c.fprintf(libc.stderr, "chainloader: execv(%s)\n", newarg_buf);
    _ = c.execv(newarg_buf, @ptrCast(argv));

    _ = c.fprintf(
        libc.stderr,
        "chainloader: execv FAILED for %s: %s\n",
        newarg_buf,
        c.strerror(std.c._errno().*),
    );
    return c.EXIT_FAILURE;
}

fn frameserver_main(argc: c_int, argv: [*c][*c]u8) c_int {
    const has_default_mode = comptime default_mode_z != null;

    const fsrvmode: ?[*:0]const u8 = if (comptime default_mode_z) |m|
        m
    else if (argc > 1)
        @ptrCast(argv[1])
    else
        null;

    const argstr: ?[*:0]u8 = if (has_default_mode) blk: {
        break :blk if (argc > 1) @as(?[*:0]u8, @ptrCast(argv[1])) else null;
    } else blk: {
        break :blk if (argc > 2) @as(?[*:0]u8, @ptrCast(argv[2])) else null;
    };

    // Monitor for descriptor leaks from parent (debug only)
    if (comptime @hasDecl(c, "_DEBUG")) {
        if (comptime !@hasDecl(c, "__APPLE__") and !@hasDecl(c, "__BSD")) {
            if (c.opendir("/proc/self/fd")) |dir| {
                var desc_count: usize = 0;
                while (c.readdir(dir)) |dirp| {
                    if (c.strcmp(&dirp.*.d_name, ".") != 0 and c.strcmp(&dirp.*.d_name, "..") != 0)
                        desc_count += 1;
                }
                _ = c.closedir(dir);

                if (desc_count > 5) {
                    _ = c.fprintf(
                        libc.stdout,
                        "\x1b[1msuspicious amount (%zu) of descriptors open, investigate.\x1b[0m\n",
                        desc_count,
                    );
                    dump_links("/proc/self/fd");
                }
            }
        }
    }

    // Dispatch based on mode
    if (comptime fsrv_opts.enable_decode) {
        if (streql(fsrvmode, "decode"))
            return launch_mode(
                "decode",
                afsrv_decode,
                st.SEGID_UNKNOWN,
                st.SHMIF_MANUAL_PAUSE | st.SHMIF_NOACTIVATE_RESIZE | st.SHMIF_NOREGISTER,
                argstr,
            );
    }

    if (comptime fsrv_opts.enable_terminal) {
        if (streql(fsrvmode, "terminal"))
            return launch_mode("terminal", afsrv_terminal, st.SEGID_TERMINAL, 0, argstr);
    }

    if (comptime fsrv_opts.enable_encode) {
        if (streql(fsrvmode, "encode"))
            return launch_mode("encode", afsrv_encode, st.SEGID_ENCODER, 0, argstr);
    }

    if (comptime fsrv_opts.enable_remoting) {
        if (streql(fsrvmode, "remoting"))
            return launch_mode("remoting", afsrv_remoting, st.SEGID_REMOTING, 0, argstr);
    }

    if (comptime fsrv_opts.enable_game) {
        if (streql(fsrvmode, "game"))
            return launch_mode("game", afsrv_game, st.SEGID_GAME, st.SHMIF_NOACTIVATE_RESIZE, argstr);
    }

    if (comptime fsrv_opts.enable_avfeed) {
        if (streql(fsrvmode, "avfeed"))
            return launch_mode("avfeed", afsrv_avfeed, st.SEGID_MEDIA, st.SHMIF_DISABLE_GUARD, argstr);
    }

    if (comptime fsrv_opts.enable_bun) {
        if (streql(fsrvmode, "bun"))
            return launch_mode("bun", afsrv_bun, st.SEGID_APPLICATION, st.SHMIF_DISABLE_GUARD, argstr);
    }

    if (comptime fsrv_opts.enable_probe) {
        if (streql(fsrvmode, "probe"))
            return launch_mode("probe", afsrv_probe, st.SEGID_MEDIA, st.SHMIF_DISABLE_GUARD, argstr);
    }

    // NET is special — it has submodes (client/server) resolved via ARCAN_ARG
    if (comptime fsrv_opts.enable_net) {
        if (streql(fsrvmode, "net")) {
            var tmp: [*c]st.struct_arg_arr = arg_unpack(c.getenv("ARCAN_ARG"));
            if (tmp == null)
                tmp = arg_unpack(argstr);

            var id: c_uint = undefined;
            var fptr: mode_fun = undefined;
            var modestr: ?[*:0]const u8 = null;

            var rk: [*c]const u8 = null;
            if (tmp != null and st.arg_lookup(tmp, "mode", 0, &rk)) {
                if (rk != null and c.strcmp(rk, "client") == 0) {
                    id = st.SEGID_REMOTING;
                    fptr = afsrv_netcl;
                    modestr = "client";
                } else if (rk != null and c.strcmp(rk, "server") == 0) {
                    id = st.SEGID_NETWORK_SERVER;
                    fptr = afsrv_netsrv;
                    modestr = "server";
                } else {
                    _ = c.fprintf(
                        libc.stdout,
                        "frameserver_net, invalid ARCAN_ARG env:\n" ++
                            "must have mode=modev set to client or server.\n",
                    );
                    return c.EXIT_FAILURE;
                }
            }
            // will invalidate all aliases from _lookup
            arg_cleanup(tmp);

            if (modestr == null) {
                _ = c.fprintf(
                    libc.stdout,
                    "frameserver_net, invalid ARCAN_ARG env:\n" ++
                        "must have mode=modev set to client or server.\n",
                );
                return c.EXIT_FAILURE;
            }

            return launch_mode(modestr.?, fptr, id, 0, argstr);
        }
    }

    _ = c.printf(
        "frameserver launch failed, unsupported mode (%s)\n",
        if (fsrvmode) |m| @as([*c]const u8, m) else @as([*c]const u8, "(null)"),
    );
    dumpargs(argc, argv);

    return c.EXIT_FAILURE;
}

fn dump_links(path: [*:0]const u8) void {
    const dp = c.opendir(path) orelse return;
    const fd = c.dirfd(dp);

    while (c.readdir(dp)) |dirp| {
        if (c.strcmp(&dirp.*.d_name, ".") == 0)
            continue;
        if (c.strcmp(&dirp.*.d_name, "..") == 0)
            continue;

        var buf: [256]u8 = undefined;
        const nr = c.readlinkat(fd, &dirp.*.d_name, &buf, buf.len - 1);
        if (nr == -1)
            continue;

        buf[@intCast(nr)] = 0;
        _ = c.fprintf(libc.stdout, "\t%s\n", &buf);
    }

    _ = c.closedir(dp);
}
