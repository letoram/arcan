// Pure Zig port of posix/launch.c — zero C helpers.
// Process launching: fork, external targets, frameserver spawning.
// Uses byte-offset accessors for arcan_frameserver (opaque due to _Atomic/bitfields).

const std = @import("std");

const c = struct {
    extern fn fork() c_int;
    extern fn waitpid(pid: c_int, status: *c_int, options: c_int) c_int;
    extern fn execve(pathname: [*c]const u8, argv: [*c][*c]u8, envp: [*c][*c]u8) c_int;
    extern fn execv(pathname: [*c]const u8, argv: [*c][*c]u8) c_int;
    extern fn _exit(status: c_int) noreturn;
    extern fn dup2(oldfd: c_int, newfd: c_int) c_int;
    extern fn close(fd: c_int) c_int;
    extern fn open(path: [*c]const u8, flags: c_int, ...) callconv(.c) c_int;
    extern fn setsid() c_int;
    extern fn setpriority(which: c_int, who: c_uint, prio: c_int) c_int;
    extern fn getrlimit(resource: c_int, rlim: *rlimit) c_int;
    extern fn poll(fds: [*]pollfd, nfds: usize, timeout: c_int) c_int;
    extern fn setenv(name: [*c]const u8, value: [*c]const u8, overwrite: c_int) c_int;
    extern fn putenv(string: [*c]u8) c_int;
    extern fn getenv(name: [*c]const u8) [*c]const u8;
    extern fn mkfifo(path: [*c]const u8, mode: u32) c_int;
    extern fn fopen(path: [*c]const u8, mode: [*c]const u8) ?*anyopaque;
    extern fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) callconv(.c) c_int;
    extern fn fclose(stream: *anyopaque) c_int;
    extern fn setlinebuf(stream: *anyopaque) void;
    extern fn sigaction(signum: c_int, act: ?*const sigaction_t, oldact: ?*sigaction_t) c_int;

    extern fn strdup(s: [*c]const u8) [*c]u8;
    extern fn strlen(s: [*c]const u8) usize;
    extern fn strcmp(a: [*c]const u8, b: [*c]const u8) c_int;
    extern fn strchr(s: [*c]const u8, ch: c_int) [*c]u8;
    extern fn strtol(s: [*c]const u8, endptr: ?*[*c]u8, base: c_int) c_long;
    extern fn strerror(errnum: c_int) [*c]const u8;
    extern fn malloc(size: usize) ?[*]u8;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn memcpy(dst: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
    extern fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) callconv(.c) c_int;

    extern fn __errno_location() *c_int;
    extern fn write(fd: c_int, buf: [*c]const u8, count: usize) isize;
    extern fn sendmsg(sockfd: c_int, msg: *const msghdr, flags: c_int) isize;

    const MSG_DONTWAIT: c_int = 0x40;
    const MSG_NOSIGNAL: c_int = 0x4000;

    const O_RDONLY: c_int = 0;
    const O_WRONLY: c_int = 0o1;
    const O_CREAT: c_int = 0o100;
    const O_APPEND: c_int = 0o2000;
    const O_CLOEXEC: c_int = 0o2000000;
    const STDIN_FILENO: c_int = 0;
    const STDOUT_FILENO: c_int = 1;
    const STDERR_FILENO: c_int = 2;
    const PRIO_PROCESS: c_int = 0;
    const RLIMIT_NOFILE: c_int = 7;
    const SIGPIPE: c_int = 13;
    const SIG_IGN: usize = 1;
    const EXIT_FAILURE: c_int = 1;
    const S_IRUSR: u32 = 0o400;
    const S_IWUSR: u32 = 0o200;
    const POLLNVAL: c_short = 0x20;
    const INT_MAX: c_int = 0x7fffffff;
};

const rlimit = extern struct {
    rlim_cur: u64,
    rlim_max: u64,
};

const pollfd = extern struct {
    fd: c_int,
    events: c_short,
    revents: c_short,
};

const sigaction_t = extern struct {
    sa_handler: usize,
    sa_mask: [16]u64, // sigset_t on aarch64-linux = 128 bytes
    sa_flags: c_int,
    sa_restorer: ?*anyopaque = null,
};

const iovec = extern struct {
    iov_base: ?*anyopaque,
    iov_len: usize,
};

const msghdr = extern struct {
    msg_name: ?*anyopaque,
    msg_namelen: c_uint,
    msg_iov: [*]iovec,
    msg_iovlen: usize,
    msg_control: ?*anyopaque,
    msg_controllen: usize,
    msg_flags: c_int,
};

// Engine API
extern fn arcan_warning(fmt: [*c]const u8, ...) callconv(.c) void;
extern fn arcan_alloc_mem(sz: usize, memtype: c_int, hint: c_int, al: c_int) ?*anyopaque;
extern fn arcan_mem_free(ptr: ?*anyopaque) void;
extern fn arcan_mem_growarr(arr: *arcan_strarr) void;
extern fn arcan_timemillis() c_ulong;
extern fn arcan_frametime() i64;
extern fn arcan_conductor_toggle_watchdog() void;
extern fn arcan_conductor_register_frameserver(fsrv: *anyopaque) void;
extern fn arcan_video_addfobject(ffunc: c_int, state: vfunc_state, cons: img_cons, zv: c_int) i64;
extern fn arcan_video_deleteobject(vid: i64) void;
extern fn arcan_audio_feed(cb: ?*anyopaque, tag: ?*anyopaque, errc: *c_int) c_int;
extern fn arcan_frameserver_audioframe_direct(aobj: ?*anyopaque, id: c_int, buffer: isize, cont: bool, tag: ?*anyopaque) c_int;
extern fn arcan_event_enqueue(ctx: ?*anyopaque, ev: *anyopaque) c_int;
extern fn arcan_event_defaultctx() ?*anyopaque;
extern fn arcan_fetch_namespace(ns: c_int) [*c]u8;
extern fn arcan_expand_namespaces(data: [*c][*c]u8) [*c][*c]u8;
extern fn platform_fsrv_spawn_server(segid: c_int, w: c_int, h: c_int, tag: usize, clsock: *c_int) ?*anyopaque;
extern fn platform_fsrv_listen_external(key: [*c]const u8, pw: [*c]const u8, fd: c_int, mode: u32, w: usize, h: usize, tag: usize) ?*anyopaque;
extern fn platform_fsrv_destroy(fsrv: *anyopaque) void;
extern fn platform_config_lookup(tag: *usize) ?*const fn ([*c]const u8, c_int, *[*c]u8, usize) callconv(.c) bool;

// In-process frameserver dispatch — replaces the legacy fork+exec of
// libexec/may/afsrv_<mode>. Implemented in src/frameserver/frameserver.zig;
// looks up the mode (argv[1]) and calls the corresponding afsrv_<mode> fn
// in-process. The child process keeps its forked address space, so
// per-instance globals stay isolated without needing afsrv_terminal et al
// to be re-entrant.
extern fn frameserver_dispatch(argc: c_int, argv: [*c][*c]u8) c_int;

const arcan_strarr = extern struct {
    count: usize,
    limit: usize,
    data: [*c][*c]u8,
};

const img_cons = extern struct {
    w: c_uint,
    h: c_uint,
    bpp: u8,
};

const vfunc_state = extern struct {
    tag: c_int,
    _pad: [4]u8 = [_]u8{0} ** 4,
    ptr: ?*anyopaque,
};

// Constants
const ARCAN_MEM_ABUFFER: c_int = 4;
const ARCAN_MEM_STRINGBUF: c_int = 5;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEM_TEMPORARY: c_int = 2;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;
const ARCAN_MEMALIGN_PAGE: c_int = 1;

const ARCAN_TAG_FRAMESERV: c_int = 3;
const FFUNC_NULLFRAME: c_int = 6;
const FFUNC_SOCKPOLL: c_int = 13;
const ARCAN_EID: i64 = 0;
const EVENT_FSRV: c_int = 32;
const EVENT_FSRV_PREROLL: c_int = 5;
const SEGID_UNKNOWN: c_int = 0;
const SEGID_GAME: c_int = 9;
const SEGID_NETWORK_CLIENT: c_int = 3;
const SEGID_NETWORK_SERVER: c_int = 2;
const SEGID_ENCODER: c_int = 7;
const SEGID_TERMINAL: c_int = 5;

const RESOURCE_APPL: c_int = 2;
const RESOURCE_APPL_TEMP: c_int = 1;
const RESOURCE_APPL_STATE: c_int = 8;
const RESOURCE_APPL_SHARED: c_int = 4;
const RESOURCE_SYS_DEBUG: c_int = 1024;
const RESOURCE_SYS_SCRIPTS: c_int = 2048;
const RESOURCE_SYS_BINS: c_int = 256;

// arcan_frameserver byte-offset accessors (aarch64-linux, verified via gcc offsetof)
const FSRV = struct {
    const DESC_WIDTH: usize = 0;
    const DESC_HEIGHT: usize = 2;
    const DESC_BPP: usize = 24;
    const SOURCE: usize = 680;
    const DPIPE: usize = 688;
    const CHILD: usize = 692;
    const METAMASK: usize = 736;
    const AID: usize = 808;
    const VID: usize = 816;
    const LAUNCHEDTIME: usize = 880;
    const SZ_AUDB: usize = 1384;
    const AUDB: usize = 1408;
    const SEGID: usize = 2000;
    const SHM_HANDLE: usize = 2032 + 8; // shm + handle offset

    fn ptr(base: *anyopaque, comptime offset: usize, comptime T: type) *T {
        return @ptrCast(@alignCast(@as([*]u8, @ptrCast(base)) + offset));
    }

    fn getDescWidth(self: *anyopaque) u16 {
        return ptr(self, DESC_WIDTH, u16).*;
    }
    fn getDescHeight(self: *anyopaque) u16 {
        return ptr(self, DESC_HEIGHT, u16).*;
    }
    fn getDescBpp(self: *anyopaque) u8 {
        return ptr(self, DESC_BPP, u8).*;
    }
    fn setLaunchedtime(self: *anyopaque, val: i64) void {
        ptr(self, LAUNCHEDTIME, i64).* = val;
    }
    fn setSource(self: *anyopaque, val: [*c]u8) void {
        ptr(self, SOURCE, [*c]u8).* = val;
    }
    fn setChild(self: *anyopaque, val: c_int) void {
        ptr(self, CHILD, c_int).* = val;
    }
    fn getDpipe(self: *anyopaque) c_int {
        return ptr(self, DPIPE, c_int).*;
    }
    fn getVid(self: *anyopaque) i64 {
        return ptr(self, VID, i64).*;
    }
    fn setVid(self: *anyopaque, val: i64) void {
        ptr(self, VID, i64).* = val;
    }
    fn setSegid(self: *anyopaque, val: c_int) void {
        ptr(self, SEGID, c_int).* = val;
    }
    fn getSegid(self: *anyopaque) c_int {
        return ptr(self, SEGID, c_int).*;
    }
    fn getShmHandle(self: *anyopaque) c_int {
        return ptr(self, SHM_HANDLE, c_int).*;
    }
    fn setSzAudb(self: *anyopaque, val: usize) void {
        ptr(self, SZ_AUDB, usize).* = val;
    }
    fn setAudb(self: *anyopaque, val: ?*anyopaque) void {
        ptr(self, AUDB, ?*anyopaque).* = val;
    }
    fn getMetamask(self: *anyopaque) c_uint {
        return ptr(self, METAMASK, c_uint).*;
    }
    fn setMetamask(self: *anyopaque, val: c_uint) void {
        ptr(self, METAMASK, c_uint).* = val;
    }
    fn setAid(self: *anyopaque, val: c_int) void {
        ptr(self, AID, c_int).* = val;
    }
};

// frameserver_envp byte-offset accessors
const ENVP = struct {
    const USE_BUILTIN: usize = 0;
    const CUSTOM_FEED: usize = 8;
    const PRESERVE_ENV: usize = 16;
    const INIT_W: usize = 20;
    const INIT_H: usize = 24;
    const METAMASK: usize = 48;
    const ARGS_BUILTIN_RESOURCE: usize = 56;
    const ARGS_BUILTIN_MODE: usize = 64;
    const ARGS_EXTERNAL_FNAME: usize = 56;
    const ARGS_EXTERNAL_ARGV: usize = 64;
    const ARGS_EXTERNAL_ENVV: usize = 72;
    const ARGS_EXTERNAL_RESOURCE: usize = 80;
    const SIZE: usize = 88;

    fn ptr(base: *anyopaque, comptime offset: usize, comptime T: type) *T {
        return @ptrCast(@alignCast(@as([*]u8, @ptrCast(base)) + offset));
    }

    fn useBuiltin(self: *anyopaque) bool {
        return ptr(self, USE_BUILTIN, bool).*;
    }
    fn customFeed(self: *anyopaque) i64 {
        return ptr(self, CUSTOM_FEED, i64).*;
    }
    fn preserveEnv(self: *anyopaque) bool {
        return ptr(self, PRESERVE_ENV, bool).*;
    }
    fn initW(self: *anyopaque) c_int {
        return ptr(self, INIT_W, c_int).*;
    }
    fn initH(self: *anyopaque) c_int {
        return ptr(self, INIT_H, c_int).*;
    }
    fn metamask(self: *anyopaque) c_uint {
        return @bitCast(ptr(self, METAMASK, c_int).*);
    }
    fn builtinMode(self: *anyopaque) [*c]const u8 {
        return ptr(self, ARGS_BUILTIN_MODE, [*c]const u8).*;
    }
    fn setBuiltinMode(self: *anyopaque, val: [*c]const u8) void {
        ptr(self, ARGS_BUILTIN_MODE, [*c]const u8).* = val;
    }
    fn builtinResource(self: *anyopaque) [*c]const u8 {
        return ptr(self, ARGS_BUILTIN_RESOURCE, [*c]const u8).*;
    }
    fn externalFname(self: *anyopaque) [*c]const u8 {
        return ptr(self, ARGS_EXTERNAL_FNAME, [*c]const u8).*;
    }
    fn externalArgv(self: *anyopaque) *arcan_strarr {
        return @ptrCast(@alignCast(ptr(self, ARGS_EXTERNAL_ARGV, ?*anyopaque).*));
    }
    fn externalEnvv(self: *anyopaque) *arcan_strarr {
        return @ptrCast(@alignCast(ptr(self, ARGS_EXTERNAL_ENVV, ?*anyopaque).*));
    }
    fn externalResource(self: *anyopaque) [*c]const u8 {
        return ptr(self, ARGS_EXTERNAL_RESOURCE, [*c]const u8).*;
    }
};

fn add_interpose(libs: *arcan_strarr, envv: *arcan_strarr) [*c]u8 {
    var interp: [*c]u8 = null;
    var lib_sz: usize = 0;
    const basestr = "LD_PRELOAD=";

    var work = libs.data;
    while (work[0] != null) {
        lib_sz += c.strlen(work[0]) + 1;
        work += 1;
    }

    if (lib_sz > 0) {
        const alloc_sz = lib_sz + basestr.len + 1;
        const mem = c.malloc(alloc_sz) orelse return null;
        interp = mem;
        _ = c.memcpy(mem, basestr.ptr, basestr.len);
        var ofs: usize = basestr.len;

        work = libs.data;
        while (work[0] != null) {
            const len = c.strlen(work[0]);
            _ = c.memcpy(mem + ofs, work[0], len);
            mem[ofs + len] = ':';
            ofs += len + 1;
            work += 1;
        }
        mem[ofs - 1] = 0;
    }

    if (envv.limit - envv.count < 2)
        arcan_mem_growarr(envv);

    envv.data[envv.count] = interp;
    envv.count += 1;

    return interp;
}

fn append_env(darr: *arcan_strarr, argarr: [*c]u8, conn: [*c]const u8, mem: [*c]const u8) void {
    const spaces = [_][*c]const u8{
        c.getenv("PATH"),
        c.getenv("CWD"),
        c.getenv("HOME"),
        c.getenv("LANG"),
        c.getenv("ARCAN_FRAMESERVER_DEBUGSTALL"),
        c.getenv("ARCAN_RENDER_NODE"),
        c.getenv("ARCAN_VIDEO_NO_FDPASS"),
        arcan_fetch_namespace(RESOURCE_APPL),
        arcan_fetch_namespace(RESOURCE_APPL_TEMP),
        arcan_fetch_namespace(RESOURCE_APPL_STATE),
        arcan_fetch_namespace(RESOURCE_APPL_SHARED),
        arcan_fetch_namespace(RESOURCE_SYS_DEBUG),
        arcan_fetch_namespace(RESOURCE_SYS_SCRIPTS),
        conn,
        mem,
        argarr,
        c.getenv("LD_LIBRARY_PATH"),
        c.getenv("XDG_RUNTIME_DIR"),
        c.getenv("XDG_STATE_HOME"),
        c.getenv("XDG_CONFIG_HOME"),
        c.getenv("LASH_BASE"),
        c.getenv("LASH_SHELL"),
        c.getenv("ARCAN_CONNPATH"),
    };

    const keys = [_][*c]const u8{
        "PATH",
        "CWD",
        "HOME",
        "LANG",
        "ARCAN_FRAMESERVER_DEBUGSTALL",
        "ARCAN_RENDER_NODE",
        "ARCAN_VIDEO_NO_FDPASS",
        "ARCAN_APPLPATH",
        "ARCAN_APPLTEMPPATH",
        "ARCAN_STATEPATH",
        "ARCAN_RESOURCEPATH",
        "ARCAN_FRAMESERVER_LOGDIR",
        "ARCAN_SCRIPTPATH",
        "ARCAN_SOCKIN_FD",
        "ARCAN_SOCKIN_MEMFD",
        "ARCAN_ARG",
        "LD_LIBRARY_PATH",
        "XDG_RUNTIME_DIR",
        "XDG_STATE_HOME",
        "XDG_CONFIG_HOME",
        "LASH_BASE",
        "LASH_SHELL",
        "ARCAN_CONNPATH",
    };

    const n_spaces = spaces.len;
    while (darr.count + n_spaces + 1 > darr.limit)
        arcan_mem_growarr(darr);

    var convb: [512]u8 = undefined;
    var step = if (darr.count > 0) darr.count - 1 else 0;

    for (0..n_spaces) |i| {
        if (spaces[i] != null and c.strlen(spaces[i]) > 0) {
            if (c.snprintf(&convb, convb.len, "%s=%s", keys[i], spaces[i]) > 0) {
                darr.data[step] = c.strdup(&convb);
                step += 1;
            }
        }
    }

    darr.count = step;
    darr.data[step] = null;
}

export fn arcan_target_launch_external(
    fname: [*c]const u8,
    argv: *arcan_strarr,
    envv: *arcan_strarr,
    libs: *arcan_strarr,
    exitc: *c_int,
) c_ulong {
    _ = add_interpose(libs, envv);
    const child = c.fork();

    if (child > 0) {
        arcan_conductor_toggle_watchdog();
        var stat_loc: c_int = 0;
        _ = c.waitpid(child, &stat_loc, 0);

        // WIFEXITED / WEXITSTATUS macros for Linux
        if ((stat_loc & 0x7f) == 0) {
            exitc.* = (stat_loc >> 8) & 0xff;
        } else {
            exitc.* = c.EXIT_FAILURE;
        }

        const ticks = arcan_timemillis();
        arcan_conductor_toggle_watchdog();
        return arcan_timemillis() - ticks;
    } else if (child == 0) {
        _ = c.execve(fname, argv.data, envv.data);
        c._exit(1);
    }

    exitc.* = c.EXIT_FAILURE;
    return 0;
}

export fn arcan_closefrom(fd: c_int) void {
    var rlim: rlimit = undefined;
    var lim: usize = 512;
    if (c.getrlimit(c.RLIMIT_NOFILE, &rlim) == 0)
        lim = @intCast(rlim.rlim_cur);

    const fds_mem = arcan_alloc_mem(
        @sizeOf(pollfd) * lim,
        ARCAN_MEM_STRINGBUF,
        ARCAN_MEM_BZERO | ARCAN_MEM_TEMPORARY,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse return;
    const fds: [*]pollfd = @ptrCast(@alignCast(fds_mem));

    for (0..lim) |i| {
        fds[i].fd = @as(c_int, @intCast(i)) + fd;
    }

    if (c.poll(fds, lim, 0) != -1) {
        for (0..lim) |i| {
            if ((fds[i].revents & c.POLLNVAL) == 0)
                _ = c.close(fds[i].fd);
        }
    }

    arcan_mem_free(fds_mem);
}

export fn platform_launch_listen_external(
    key: [*c]const u8,
    pw: [*c]const u8,
    fd: c_int,
    mode: u32,
    w: usize,
    h: usize,
    tag: usize,
) ?*anyopaque {
    const res = platform_fsrv_listen_external(key, pw, fd, mode, w, h, tag) orelse return null;

    const cons = img_cons{
        .w = FSRV.getDescWidth(res),
        .h = FSRV.getDescHeight(res),
        .bpp = FSRV.getDescBpp(res),
    };
    const state = vfunc_state{ .tag = ARCAN_TAG_FRAMESERV, .ptr = res };

    FSRV.setLaunchedtime(res, arcan_frametime());
    FSRV.setVid(res, arcan_video_addfobject(FFUNC_SOCKPOLL, state, cons, 0));
    if (FSRV.getVid(res) == ARCAN_EID) {
        platform_fsrv_destroy(res);
        return null;
    }

    return res;
}

export fn platform_launch_fork(
    setup_ptr: *anyopaque,
    tag: usize,
) ?*anyopaque {
    var arr = std.mem.zeroes(arcan_strarr);
    var add_audio = true;
    var clsock: c_int = 0;

    const ctx = platform_fsrv_spawn_server(
        SEGID_UNKNOWN,
        ENVP.initW(setup_ptr),
        ENVP.initH(setup_ptr),
        tag,
        &clsock,
    ) orelse {
        return null;
    };

    FSRV.setLaunchedtime(ctx, arcan_frametime());
    FSRV.setSource(ctx, null);
    const shmfd = FSRV.getShmHandle(ctx);

    if (ENVP.useBuiltin(setup_ptr)) {
        const mode = ENVP.builtinMode(setup_ptr);
        if (c.strcmp(mode, "game") == 0) {
            FSRV.setSegid(ctx, SEGID_GAME);
        } else if (c.strcmp(mode, "net-cl") == 0) {
            FSRV.setSegid(ctx, SEGID_NETWORK_CLIENT);
            ENVP.setBuiltinMode(setup_ptr, "net");
        } else if (c.strcmp(mode, "net-srv") == 0) {
            FSRV.setSegid(ctx, SEGID_NETWORK_SERVER);
            ENVP.setBuiltinMode(setup_ptr, "net");
        } else if (c.strcmp(mode, "encode") == 0) {
            FSRV.setSegid(ctx, SEGID_ENCODER);
            FSRV.setSzAudb(ctx, 65535);
            add_audio = false;
            FSRV.setAudb(ctx, arcan_alloc_mem(65535, ARCAN_MEM_ABUFFER, 0, ARCAN_MEMALIGN_PAGE));
        } else if (c.strcmp(mode, "terminal") == 0) {
            FSRV.setSegid(ctx, SEGID_TERMINAL);
        }

        const res = ENVP.builtinResource(setup_ptr);
        FSRV.setSource(ctx, c.strdup(if (res != null) res else mode));
        append_env(&arr, @constCast(ENVP.builtinResource(setup_ptr)), "3", "4");
    } else {
        const res = ENVP.externalResource(setup_ptr);
        FSRV.setSource(ctx, c.strdup(if (res != null) res else ""));
        const source = FSRV.ptr(ctx, FSRV.SOURCE, [*c]u8).*;
        append_env(ENVP.externalEnvv(setup_ptr), source, "3", "4");
    }

    const cons = img_cons{
        .w = @intCast(ENVP.initW(setup_ptr)),
        .h = @intCast(ENVP.initH(setup_ptr)),
        .bpp = 4,
    };
    const state = vfunc_state{ .tag = ARCAN_TAG_FRAMESERV, .ptr = ctx };
    const custom_feed = ENVP.customFeed(setup_ptr);

    if (custom_feed == 0) {
        FSRV.setVid(ctx, arcan_video_addfobject(FFUNC_NULLFRAME, state, cons, 0));
        FSRV.setMetamask(ctx, FSRV.getMetamask(ctx) | ENVP.metamask(setup_ptr));

        if (FSRV.getVid(ctx) == 0) {
            platform_fsrv_destroy(ctx);
            return null;
        }
    } else {
        FSRV.setVid(ctx, custom_feed);
    }

    const child = c.fork();
    if (child > 0) {
        FSRV.setChild(ctx, child);
    } else if (child == 0) {
        // Wake-up ping injected post-atfork. A library atfork-child handler
        // (recvmsg size=102 loop on inherited unix sockets, until -EAGAIN —
        // confirmed via bpftrace on unix_stream_recvmsg) runs before this
        // line and empties any preroll bytes that were on the dpipe at fork
        // time. The first kid wins because at fork time arcan hasn't queued
        // anything yet; 2nd+ kids lose because ~41 preroll bytes are already
        // in kid_end's recv queue at fork. This sendmsg lands a fresh '!'
        // byte in the kid_end queue *after* atfork has finished, so the
        // post-exec lash's first fetchfds returns immediately and preroll
        // proceeds normally.
        //
        // Per-field msghdr/iovec init avoids an SH-backend struct-literal
        // miscompile that drops middle fields.
        {
            const dpipe_p = FSRV.getDpipe(ctx);
            var ping_byte: u8 = '!';
            // Per-field iovec init — std.mem.zeroes(iovec)+per-field is more
            // robust than a struct literal under SH backend, but we also
            // want to confirm the bytes-on-the-wire here, so write fields
            // explicitly + memset any padding.
            var iov: iovec = undefined;
            @memset(@as([*]u8, @ptrCast(&iov))[0..@sizeOf(iovec)], 0);
            iov.iov_base = @ptrCast(&ping_byte);
            iov.iov_len = 1;
            var msg: msghdr = undefined;
            @memset(@as([*]u8, @ptrCast(&msg))[0..@sizeOf(msghdr)], 0);
            msg.msg_iov = @ptrCast(&iov);
            msg.msg_iovlen = 1;
            const rv = c.sendmsg(dpipe_p, &msg, c.MSG_DONTWAIT | c.MSG_NOSIGNAL);
            const f = c.fopen("/tmp/arcan_shm_trace.log", "a");
            if (f) |fd| {
                const errno_fn = @extern(*const fn () callconv(.c) *c_int, .{ .name = "__errno_location" });
                _ = c.fprintf(fd, "atfork ping: dpipe=%d rv=%ld errno=%d iov_len=%zu\n",
                    dpipe_p, @as(c_longlong, rv), errno_fn().*, iov.iov_len);
                _ = c.fclose(fd);
            }
        }
        {
            const f = c.fopen("/tmp/arcan_shm_trace.log", "a");
            if (f) |fd| {
                _ = c.fprintf(fd, "fork child: raw_shmfd=%d raw_clsock=%d\n",
                    shmfd, clsock);
                _ = c.fclose(fd);
            }
        }
        _ = c.close(c.STDERR_FILENO + 1);
        _ = c.dup2(clsock, c.STDERR_FILENO + 1);
        _ = c.dup2(shmfd, c.STDERR_FILENO + 2);
        arcan_closefrom(c.STDERR_FILENO + 3);

        if (c.setsid() == -1)
            c._exit(c.EXIT_FAILURE);

        // Drop nice level
        var cfg_tag: usize = 0;
        const get_config = platform_config_lookup(&cfg_tag);
        var level: c_int = 0;
        var priostr: [*c]u8 = undefined;
        if (get_config) |cfg_fn| {
            if (cfg_fn("child_priority", 0, &priostr, cfg_tag)) {
                level = @intCast(@mod(c.strtol(priostr, null, 10), c.INT_MAX));
            }
        }
        _ = c.setpriority(c.PRIO_PROCESS, 0, level);

        // Redirect stdin to /dev/null, stdout/stderr to debug log
        var nfd = c.open("/tmp/arcan_fsrv_debug.log", c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c_uint, 0o666));
        if (nfd != -1) {
            _ = c.dup2(nfd, c.STDOUT_FILENO);
            _ = c.dup2(nfd, c.STDERR_FILENO);
            _ = c.close(nfd);
        }
        {
            const msg = "fsrv child: forked OK\n";
            _ = c.write(2, msg, msg.len);
        }
        nfd = c.open("/dev/null", c.O_RDONLY);
        if (nfd != -1) {
            _ = c.dup2(nfd, c.STDIN_FILENO);
            _ = c.close(nfd);
        }

        // Ignore SIGPIPE
        var sa = std.mem.zeroes(sigaction_t);
        sa.sa_handler = c.SIG_IGN;
        _ = c.sigaction(c.SIGPIPE, &sa, null);

        if (ENVP.useBuiltin(setup_ptr)) {
            var argv_arr = [_][*c]u8{
                arcan_fetch_namespace(RESOURCE_SYS_BINS),
                @constCast(ENVP.builtinMode(setup_ptr)),
                null,
            };
            {
                var dbg_buf: [1024]u8 = undefined;
                _ = c.snprintf(&dbg_buf, dbg_buf.len, "fsrv exec: argv[0]=%s argv[1]=%s\n",
                    if (argv_arr[0] != null) argv_arr[0] else @as([*c]u8, @constCast("(null)")),
                    if (argv_arr[1] != null) argv_arr[1] else @as([*c]u8, @constCast("(null)")));
                _ = c.write(2, &dbg_buf, c.strlen(&dbg_buf));
            }

            // DEBUG: write launch details to a persistent log file
            {
                const dbg = c.fopen("/tmp/arcan_launch_debug.log", "a");
                if (dbg) |dbg_f| {
                    _ = c.fprintf(dbg_f, "platform_launch_fork child: argv[0]='%s' argv[1]='%s' preserve_env=%d\n",
                        if (argv_arr[0] != null) argv_arr[0] else @as([*c]u8, @constCast("(null)")),
                        if (argv_arr[1] != null) argv_arr[1] else @as([*c]u8, @constCast("(null)")),
                        @as(c_int, if (ENVP.preserveEnv(setup_ptr)) 1 else 0));
                    const sockin = c.getenv("ARCAN_SOCKIN_FD");
                    const connp = c.getenv("ARCAN_CONNPATH");
                    _ = c.fprintf(dbg_f, "  env: ARCAN_SOCKIN_FD=%s ARCAN_CONNPATH=%s\n",
                        if (sockin != null) sockin else @as([*c]const u8, "(null)"),
                        if (connp != null) connp else @as([*c]const u8, "(null)"));
                    _ = c.fclose(dbg_f);
                }
            }

            // In-process dispatch: instead of execve'ing a libexec/may/afsrv_<mode>
            // binary that would chainload back into this same `may` build, install
            // the child-private env (ARCAN_SOCKIN_FD/_MEMFD/_ARG plus the inherited
            // user env that `append_env` already replicated into arr.data) into our
            // own environ and call frameserver_dispatch directly. The fork above
            // gives us isolation; no exec needed. argv shape stays [exe, mode, null]
            // because frameserver_main reads argv[1] for the mode string.
            if (arr.data != null) {
                var i: usize = 0;
                while (arr.data[i] != null) : (i += 1) {
                    // putenv stores the passed pointer (not a copy); arr lives in
                    // the forked child's memory for the duration of the call.
                    _ = c.putenv(arr.data[i]);
                }
            }
            const rv = frameserver_dispatch(2, &argv_arr);
            c._exit(rv);
        } else {
            const ext_envv = ENVP.externalEnvv(setup_ptr);
            const ext_argv = ENVP.externalArgv(setup_ptr);
            _ = c.execve(
                ENVP.externalFname(setup_ptr),
                ext_argv.data,
                ext_envv.data,
            );
            c._exit(c.EXIT_FAILURE);
        }
    } else {
        // fork failed
        arcan_video_deleteobject(FSRV.getVid(ctx));
        platform_fsrv_destroy(ctx);
        return null;
    }
    _ = c.close(clsock);

    var errc: c_int = 0;
    if (add_audio) {
        FSRV.setAid(ctx, arcan_audio_feed(
            @constCast(@ptrCast(&arcan_frameserver_audioframe_direct)),
            ctx,
            &errc,
        ));
    }

    if (FSRV.getSegid(ctx) != SEGID_UNKNOWN) {
        // Construct EVENT_FSRV/PREROLL event (128 bytes).
        // align(8) is load-bearing: vid at byte 104 is read as *i64 (align 8),
        // and a default [128]u8 stack slot is only 1-byte aligned. Without
        // align(8) the @alignCast on &ev[104] traps with "incorrect alignment"
        // on the 2nd+ child preroll (ticket MAY-006).
        var ev: [128]u8 align(8) = [_]u8{0} ** 128;
        ev[120] = @intCast(EVENT_FSRV); // category at offset 120
        // fsrv.kind = EVENT_FSRV_PREROLL (offset 0, 4 bytes)
        const kind_ptr: *c_int = @ptrCast(@alignCast(&ev[0]));
        kind_ptr.* = EVENT_FSRV_PREROLL;
        // fsrv.video = ctx->vid (offset 104, 8 bytes)
        const vid_ptr: *i64 = @ptrCast(@alignCast(&ev[104]));
        vid_ptr.* = FSRV.getVid(ctx);
        _ = arcan_event_enqueue(arcan_event_defaultctx(), &ev);
    }

    arcan_conductor_register_frameserver(ctx);
    return ctx;
}

export fn platform_launch_internal(
    fname: [*c]const u8,
    argv: *arcan_strarr,
    envv: *arcan_strarr,
    libs: *arcan_strarr,
    tag: usize,
) ?*anyopaque {
    _ = add_interpose(libs, envv);
    argv.data = arcan_expand_namespaces(argv.data);
    envv.data = arcan_expand_namespaces(envv.data);

    // Construct frameserver_envp on stack (88 bytes)
    var args: [ENVP.SIZE]u8 = [_]u8{0} ** ENVP.SIZE;
    const args_ptr: *anyopaque = &args;
    // use_builtin = false (already zero)
    // args.external.fname
    ENVP.ptr(args_ptr, ENVP.ARGS_EXTERNAL_FNAME, [*c]const u8).* = fname;
    // args.external.envv
    ENVP.ptr(args_ptr, ENVP.ARGS_EXTERNAL_ENVV, ?*anyopaque).* = envv;
    // args.external.argv
    ENVP.ptr(args_ptr, ENVP.ARGS_EXTERNAL_ARGV, ?*anyopaque).* = argv;

    return platform_launch_fork(args_ptr, tag);
}

export fn arcan_monitor_external(
    cmd: [*c]u8,
    fifo_path: [*c]u8,
    input: *?*anyopaque,
) bool {
    _ = c.mkfifo(fifo_path, c.S_IRUSR | c.S_IWUSR);

    const child = c.fork();
    if (child == 0) {
        var argv_arr = [_][*c]u8{ cmd, fifo_path, null };
        _ = c.execve(cmd, &argv_arr, null);
        c._exit(0);
    }

    input.* = c.fopen(fifo_path, "r");
    if (input.*) |inp| {
        c.setlinebuf(inp);
    }
    return true;
}
