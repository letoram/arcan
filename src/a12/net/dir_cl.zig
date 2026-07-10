// Zig port of a12/net/dir_cl.c — directory client implementation for arcan-net.
// Connects to a directory server, enumerates services, requests connections,
// handles appl downloads, and manages local state.
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");
const posix = std.posix;
const fs = std.fs;

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. Each alias routes to the appropriate hand-written replacement module
// (zero `@cImport` left). The `c.X` spellings at call sites below are unchanged.
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // ── libc (posix + stdio) ────────────────────────────────────────────────
    pub const AF_UNIX = libc.AF_UNIX;
    pub const AT_REMOVEDIR = libc.AT_REMOVEDIR;
    pub const DT_DIR = libc.DT_DIR;
    pub const EXIT_FAILURE = libc.EXIT_FAILURE;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const FILE = libc.FILE;
    pub const F_SETFD = libc.F_SETFD;
    pub const F_SETFL = libc.F_SETFL;
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_NONBLOCK = libc.O_NONBLOCK;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_TRUNC = libc.O_TRUNC;
    pub const O_WRONLY = libc.O_WRONLY;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const SHUT_RDWR = libc.SHUT_RDWR;
    pub const SIGCHLD = libc.SIGCHLD;
    pub const SIGPIPE = libc.SIGPIPE;
    pub const SOCK_STREAM = libc.SOCK_STREAM;
    pub const STDERR_FILENO = libc.STDERR_FILENO;
    pub const STDIN_FILENO = libc.STDIN_FILENO;
    pub const STDOUT_FILENO = libc.STDOUT_FILENO;
    pub const close = libc.close;
    pub const closedir = libc.closedir;
    pub const dup2 = libc.dup2;
    pub const execvpe = libc.execvpe;
    pub const exit = libc.exit;
    pub const fchdir = libc.fchdir;
    pub const fclose = libc.fclose;
    pub const fcntl = libc.fcntl;
    pub const fdopen = libc.fdopen;
    pub const fflush = libc.fflush;
    pub const fgets = libc.fgets;
    pub const fmemopen = libc.fmemopen;
    pub const fopen = libc.fopen;
    pub const fork = libc.fork;
    pub const fprintf = libc.fprintf;
    pub const fputc = libc.fputc;
    pub const fputs = libc.fputs;
    pub const free = libc.free;
    pub const fseek = libc.fseek;
    pub const ftell = libc.ftell;
    pub const getenv = libc.getenv;
    pub const isatty = libc.isatty;
    pub const lseek = libc.lseek;
    pub const mkdtemp = libc.mkdtemp;
    pub const mkstemp = libc.mkstemp;
    pub const open = libc.open;
    pub const opendir = libc.opendir;
    pub const printf = libc.printf;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const pthread_mutex_t = libc.pthread_mutex_t;
    pub const pthread_t = libc.pthread_t;
    pub const readdir = libc.readdir;
    pub const remove = libc.remove;
    pub const renameat = libc.renameat;
    pub const rmdir = libc.rmdir;
    pub const setlinebuf = libc.setlinebuf;
    pub const setsid = libc.setsid;
    pub const shutdown = libc.shutdown;
    pub const sigaction = libc.sigaction;
    pub const signal = libc.signal;
    pub const sleep = libc.sleep;
    pub const snprintf = libc.snprintf;
    pub const socketpair = libc.socketpair;
    // stderr / stdin / stdout are `extern "c" var` in libc. Aliasing an
    // extern var via `pub const = libc.stderr` triggers a comptime-value
    // error when the aliased var is used as a runtime value. Re-declare the
    // extern var directly — the linker resolves all three to the same glibc
    // symbol regardless of which Zig module declares it.
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdin: *libc.FILE;
    pub extern "c" var stdout: *libc.FILE;
    pub const strlen = libc.strlen;
    pub const strtoul = libc.strtoul;
    pub const struct_dirent = libc.struct_dirent;
    pub const struct_sigaction = libc.struct_sigaction;
    pub const unlink = libc.unlink;
    pub const unlinkat = libc.unlinkat;
    pub const write = libc.write;

    // ── shmif (arcan_shmif.h / arcan_shmif_server.h) ────────────────────────
    pub const arcan_event = shmif.arcan_event;
    pub const kill = shmif.kill;
    pub const pid_t = shmif.pid_t;
    pub const SEGID_HANDOVER = shmif.SEGID_HANDOVER;
    pub const SIGUSR1 = shmif.SIGUSR1;
    pub const struct_arcan_shmif_cont = shmif.struct_arcan_shmif_cont;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const waitpid = shmif.waitpid;
    pub const WEXITSTATUS = shmif.WEXITSTATUS;
    pub const WIFEXITED = shmif.WIFEXITED;
    pub const WNOHANG = shmif.WNOHANG;

    // ── a12 (a12.h / a12_int.h) ─────────────────────────────────────────────
    pub const A12_BHANDLER_CANCELLED = a12.A12_BHANDLER_CANCELLED;
    pub const A12_BHANDLER_COMPLETED = a12.A12_BHANDLER_COMPLETED;
    pub const A12_BHANDLER_DONTWANT = a12.A12_BHANDLER_DONTWANT;
    pub const A12_BHANDLER_INITIALIZE = a12.A12_BHANDLER_INITIALIZE;
    pub const A12_BHANDLER_NEWFD = a12.A12_BHANDLER_NEWFD;
    pub const A12_BTYPE_APPL = a12.A12_BTYPE_APPL;
    pub const A12_BTYPE_APPL_CONTROLLER = a12.A12_BTYPE_APPL_CONTROLLER;
    pub const A12_BTYPE_CRASHDUMP = a12.A12_BTYPE_CRASHDUMP;
    pub const A12_BTYPE_STATE = a12.A12_BTYPE_STATE;
    pub const EVENT_EXTERNAL = a12.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_IDENT = a12.EVENT_EXTERNAL_IDENT;
    pub const EVENT_EXTERNAL_MESSAGE = a12.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = a12.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_EXTERNAL_REGISTER = a12.EVENT_EXTERNAL_REGISTER;
    pub const EVENT_EXTERNAL_SEGREQ = a12.EVENT_EXTERNAL_SEGREQ;
    pub const EVENT_EXTERNAL_STREAMSTATUS = a12.EVENT_EXTERNAL_STREAMSTATUS;
    pub const EVENT_TARGET = a12.EVENT_TARGET;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const SEGID_ENCODER = a12.SEGID_ENCODER;
    pub const SEGID_NETWORK_CLIENT = a12.SEGID_NETWORK_CLIENT;
    pub const TARGET_COMMAND_BCHUNK_IN = a12.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = a12.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_MESSAGE = a12.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_NEWSEGMENT = a12.TARGET_COMMAND_NEWSEGMENT;
    pub const TARGET_COMMAND_REQFAIL = a12.TARGET_COMMAND_REQFAIL;
    pub const struct_a12_bhandler_meta = a12.struct_a12_bhandler_meta;
    pub const struct_a12_bhandler_res = a12.struct_a12_bhandler_res;
    pub const struct_a12_context_options = a12.struct_a12_context_options;
    pub const struct_a12_dynreq = a12.struct_a12_dynreq;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_a12_unpack_cfg = a12.struct_a12_unpack_cfg;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_pk_response = a12.struct_pk_response;

    // ── anet (anet_helper.h / a12_helper.h / directory.h) ───────────────────
    pub const MONITOR_ADMIN = anet.MONITOR_ADMIN;
    pub const MONITOR_DEBUGGER = anet.MONITOR_DEBUGGER;
    pub const MONITOR_SIMPLE = anet.MONITOR_SIMPLE;
    pub const PATH_MAX = anet.PATH_MAX;
    pub const struct_anet_cl_connection = anet.struct_anet_cl_connection;
    pub const struct_anet_dircl_opts = anet.struct_anet_dircl_opts;
    pub const struct_anet_options = anet.struct_anet_options;
    pub const struct_dircl_nameent = anet.struct_dircl_nameent;
    pub const struct_directory_meta = anet.struct_directory_meta;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_ioloop_shared = anet.struct_ioloop_shared;
    pub const struct_launcher_meta = anet.struct_launcher_meta;
};

// External declarations

extern var global: c.struct_global_cfg;

extern "c" fn anet_authenticate(S: *c.struct_a12_state, fdin: c_int, fdout: c_int, err: *?[*:0]u8) bool;
extern "c" fn anet_cl_setup(opts: *c.struct_anet_options) c.struct_anet_cl_connection;
extern "c" fn anet_directory_ioloop(S: *c.struct_ioloop_shared) void;
extern "c" fn anet_directory_tunnel_thread(ios: *c.struct_ioloop_shared, chid: u8) void;
extern "c" fn anet_client_lua_getpath(key: [*:0]const u8) ?[*:0]const u8;
extern "c" fn anet_client_execargs(name: [*:0]const u8, path: [*:0]const u8, meta: *c.struct_launcher_meta, manifest: ?*c.struct_arg_arr) bool;
extern "c" fn a12_client(opts: *c.struct_a12_context_options) *c.struct_a12_state;
extern "c" fn a12_free(S: *c.struct_a12_state) void;
extern "c" fn a12_remote_mode(S: *c.struct_a12_state) c_int;
extern "c" fn a12_set_bhandler(S: *c.struct_a12_state, handler: ?*const fn (*c.struct_a12_state, c.struct_a12_bhandler_meta, ?*anyopaque) callconv(.c) c.struct_a12_bhandler_res, tag: ?*anyopaque) void;
extern "c" fn a12_set_channel(S: *c.struct_a12_state, chid: u8) void;
extern "c" fn a12_find_free_channel(S: *c.struct_a12_state, chid: *u8) void;
extern "c" fn a12_channel_enqueue(S: *c.struct_a12_state, ev: *c.arcan_event) c_int;
extern "c" fn a12_channel_bprogress_hook(S: *c.struct_a12_state, chid: u8, step: usize, cb: ?*const fn (c_int, usize, usize, usize, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) void;
extern "c" fn a12_enqueue_bstream(S: *c.struct_a12_state, fd: c_int, btype: c_int, id: u16, streaming: bool, sz: c_long, ext: [*c]u8) void;
extern "c" fn a12_enqueue_blob(S: *c.struct_a12_state, buf: [*c]u8, buf_sz: usize, id: u16, btype: c_int, name: [*:0]const u8) void;
extern "c" fn a12_set_tunnel_sink(S: *c.struct_a12_state, chid: u8, fd: c_int) void;
extern "c" fn a12_set_session(auth: *c.struct_pk_response, pk: [*:0]const u8, privk: [*:0]const u8) void;
extern "c" fn a12_request_dynamic_resource(S: *c.struct_a12_state, pubk: [*c]u8, tunnel: bool, handler: ?*const fn (*c.struct_a12_state, c.struct_a12_dynreq, ?*anyopaque) callconv(.c) void, tag: ?*anyopaque) void;
extern "c" fn a12_request_file(S: *c.struct_a12_state, chid: u8, ns: u16, id: u32, ext: [*:0]const u8) void;
extern "c" fn a12_set_destination_raw(S: *c.struct_a12_state, chid: u8, cfg: c.struct_a12_unpack_cfg, sz: usize) void;
extern "c" fn a12_set_signing_pair(S: *c.struct_a12_state, pubk: [*c]u8, privk: [*c]u8) void;
extern "c" fn a12_shutdown_id(S: *c.struct_a12_state, id: u16) void;
extern "c" fn a12int_trace(mask: c_int, fmt: [*:0]const u8, ...) void;
extern "c" fn a12int_request_dirlist(S: *c.struct_a12_state, active: bool) void;
extern "c" fn a12helper_a12srv_shmifcl(prealloc: ?*c.struct_arcan_shmif_cont, S: *c.struct_a12_state, cp: ?[*:0]const u8, fd_in: c_int, fd_out: c_int) c_int;
extern "c" fn a12helper_tob64(data: [*c]const u8, inl: usize, outl: *usize) [*c]u8;
extern "c" fn a12helper_keystore_get_sigkey(tag: [*:0]const u8, pubk: [*c]u8, privk: [*c]u8) void;
extern "c" fn arcan_shmif_poll(cont: *c.struct_arcan_shmif_cont, ev: *c.arcan_event) c_int;
extern "c" fn arcan_shmif_enqueue(cont: *c.struct_arcan_shmif_cont, ev: *const c.arcan_event) void;
extern "c" fn arcan_shmif_acquireloop(cont: *c.struct_arcan_shmif_cont, acq: *c.arcan_event, pqueue: *[*]c.arcan_event, pqueue_sz: *isize) bool;
extern "c" fn arcan_shmif_drop(cont: *c.struct_arcan_shmif_cont) void;
extern "c" fn arcan_shmif_connect(path: [*:0]const u8, pass: ?[*:0]const u8, dfd: *c_int) ?[*:0]u8;
extern "c" fn arcan_shmif_acquire(cont: ?*c.struct_arcan_shmif_cont, key: [*:0]const u8, segid: c_int, flags: c_int) c.struct_arcan_shmif_cont;
extern "c" fn arcan_shmif_handover_exec(cont: *c.struct_arcan_shmif_cont, ev: c.arcan_event, path: [*:0]const u8, argv: [*c][*c]const u8, envv: [*c][*c]const u8, flags: c_int) void;
extern "c" fn arcan_shmif_eventstr(ev: *const c.arcan_event, buf: ?[*]u8, buf_sz: usize) [*:0]const u8;
extern "c" fn verify_appl_pkg(buf: [*]u8, buf_sz: usize, insig_pk: [*c]u8, outsig_pk: [*c]u8, errmsg: *?[*:0]const u8) ?[*:0]u8;
extern "c" fn extract_appl_pkg(fin: *c.FILE, dirfd: c_int, basename: [*:0]const u8, msg: *?[*:0]const u8, manifest: *?*c.struct_arg_arr) bool;
extern "c" fn file_to_membuf(applin: *c.FILE, out: *?[*]u8, out_sz: *usize) ?*c.FILE;
extern "c" fn arg_cleanup(arr: *c.struct_arg_arr) void;

// Module-level state

const ClGlobal = struct {
    die_on_tunnel: bool = false,
    child_signal: std.atomic.Value(i32) = std.atomic.Value(i32).init(-1),
};

var cl_global = ClGlobal{};

const ApplState = struct {
    fd: c_int = -1,
    fpek: ?*c.FILE = null,
    active: bool = false,
};

const ApplRunnerState = struct {
    ios: ?*c.struct_ioloop_shared = null,
    manifest: ?*c.struct_arg_arr = null,
    state: ApplState = .{},
    pid: c.pid_t = 0,
    pf_stdin: ?*c.FILE = null,
    pf_stdout: ?*c.FILE = null,
    queue_terminate: bool = false,
    fail_state: bool = false,
    n_keys_in: usize = 0,
    join_event: c.arcan_event = c.arcan_event.zeroes(),
    p_stdout: c_int = -1,
    p_stdin: c_int = -1,
    applid: u16 = 0,
};

const TunnelState = struct {
    opts: c.struct_a12_context_options,
    req: c.struct_a12_dynreq,
    handover: ?*c.struct_arcan_shmif_cont,
    ios: *c.struct_ioloop_shared,
    parent: *c.struct_a12_state,
    shutdown: *volatile bool,
    fd: c_int,
};

var active_appls = struct {
    active: ApplRunnerState = .{},
    n_active: std.atomic.Value(i32) = std.atomic.Value(i32).init(0),
}{};

// Progress output

fn output_progress(status: c_int, in: usize, out: usize, total: usize, tag: ?*anyopaque) callconv(.c) void {
    _ = tag;
    const eol: [*:0]const u8 = if (c.isatty(c.STDIN_FILENO) != 0) blk: {
        _ = c.fprintf(c.stdout, "\r\x1b[K");
        break :blk "";
    } else "\n";

    switch (status) {
        -1 => _ = c.fprintf(c.stdout, "[Progress] : Cancel || Error\n"),
        0 => {
            if (total != 0) {
                _ = c.fprintf(
                    c.stdout,
                    "[Progress] %.2f%% In %zu KiB, Out %zu KiB / %zu KiB%s",
                    @as(f64, @floatCast(@as(f32, @floatFromInt(in)) / @as(f32, @floatFromInt(total)) * 100.0)),
                    in >> 10, out >> 10, total >> 10, eol,
                );
            } else {
                _ = c.fprintf(
                    c.stdout,
                    "[Progress] (Streaming) In %zu KiB, Out %zu KiB%s",
                    in >> 10, out >> 10, eol,
                );
            }
        },
        1 => _ = c.fprintf(c.stdout, "[Progress] Completed, Waiting for Ack%s", eol),
        2 => _ = c.fprintf(c.stdout, "[Progress] Done\n"),
        else => {},
    }
    _ = c.fflush(c.stdout);
}

// SIGCHLD handler

fn child_signal_handler(signo: c_int) callconv(.c) void {
    _ = signo;
    var pret: c_int = undefined;
    if (c.waitpid(-1, &pret, c.WNOHANG) == -1) return;
    cl_global.child_signal.store(pret, .monotonic);
}

// Tunnel runner thread

fn tunnel_runner(t: ?*anyopaque) callconv(.c) ?*anyopaque {
    const ts: *TunnelState = @ptrCast(@alignCast(t.?));
    var err: ?[*:0]u8 = null;
    const S = a12_client(&ts.opts);

    if (anet_authenticate(S, ts.fd, ts.fd, &err)) {
        _ = a12helper_a12srv_shmifcl(ts.handover, S, null, ts.fd, ts.fd);
    }

    if (cl_global.die_on_tunnel) {
        ts.ios.shutdown = true;
    }

    _ = c.shutdown(ts.fd, c.SHUT_RDWR);
    _ = c.close(ts.fd);
    const wakeup = ts.ios.wakeup;
    if (err) |e| c.free(@ptrCast(e));

    const gpa = std.heap.c_allocator;
    gpa.destroy(ts);

    const wake_byte = [1]u8{0};
    _ = c.write(wakeup, &wake_byte, 1);
    return null;
}

fn detach_tunnel_runner(
    I: *c.struct_ioloop_shared,
    fd: c_int,
    aopt: *c.struct_a12_context_options,
    req: *c.struct_a12_dynreq,
) void {
    const gpa = std.heap.c_allocator;
    const ts = gpa.create(TunnelState) catch return;
    ts.* = .{
        .opts = aopt.*,
        .req = req.*,
        .handover = I.handover,
        .ios = I,
        .parent = undefined,
        .shutdown = &I.shutdown,
        .fd = fd,
    };
    ts.opts.pk_lookup_tag = &ts.req;

    var pth: c.pthread_t = undefined;
    var pthattr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&pthattr);
    _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);
    _ = c.pthread_create(&pth, &pthattr, tunnel_runner, ts);
}

// Debug event handler

fn on_debug_event(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = cont;
    _ = chid;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    _ = I;
    const event = ev orelse return;
    if (event.unnamed_0.unnamed_0.unnamed_0.tgt.kind != @as(c_uint, @bitCast(c.TARGET_COMMAND_MESSAGE)))
        return;

    _ = c.fputs(@as([*c]u8, @ptrCast(@alignCast(&event.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0]))), c.stdout);
    if (event.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv == 0)
        _ = c.fputc(0, c.stdout);
    _ = c.fflush(c.stdout);
}

// Hex encoding helper

fn hexenc(allocator: std.mem.Allocator, buf: []const u8) ![]u8 {
    const hex = "0123456789abcdef";
    var out = try allocator.alloc(u8, buf.len * 2 + 1);
    for (buf, 0..) |byte, i| {
        out[i * 2] = hex[byte >> 4];
        out[i * 2 + 1] = hex[byte & 0x0f];
    }
    out[buf.len * 2] = 0;
    return out[0 .. buf.len * 2 :0];
}

// Appl directory cleanup using Zig's directory walker

/// Recursively remove all files and directories under [path].
/// Returns true if the top-level path itself was also removed.
fn remove_tree(dir_path: [:0]const u8) bool {
    // Use opendir / readdir to walk depth-first and remove entries.
    // We do a simple iterative approach: collect entries, recurse, then unlink.
    const d = c.opendir(dir_path.ptr) orelse return false;
    defer _ = c.closedir(d);

    while (c.readdir(d)) |ent_raw| {
        const ent: *c.struct_dirent = @ptrCast(ent_raw);
        const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&ent.d_name)), 0);
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        // Build child path on the stack.
        var child_buf: [std.fs.max_path_bytes]u8 = undefined;
        const child = std.fmt.bufPrintZ(&child_buf, "{s}/{s}", .{ dir_path, name }) catch continue;

        if (ent.d_type == c.DT_DIR) {
            _ = remove_tree(child);
            _ = c.rmdir(child.ptr);
        } else {
            if (c.remove(child.ptr) != 0) {
                _ = c.fprintf(c.stderr, "error during cleanup of %s\n", child.ptr);
            }
        }
    }
    return c.rmdir(dir_path.ptr) == 0;
}

fn clean_appldir(name: [*:0]const u8, basedir: c_int) bool {
    if (basedir != -1) {
        _ = c.fchdir(basedir);
    }

    const name_slice = std.mem.sliceTo(name, 0);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const n_active = active_appls.n_active.load(.monotonic);

    if (n_active > 0) {
        const new_name = std.fmt.bufPrintZ(&buf, "{s}.new", .{name_slice}) catch return false;
        _ = remove_tree(new_name);
    }

    const status = remove_tree(std.mem.sliceTo(name, 0));
    if (status) {
        _ = c.unlinkat(basedir, "pulse", c.AT_REMOVEDIR);
        _ = c.unlinkat(basedir, ".", c.AT_REMOVEDIR);
    }
    return status;
}

fn swap_appldir(name: [*:0]const u8, basedir: c_int) void {
    if (basedir != -1) {
        _ = c.fchdir(basedir);
    }

    const name_slice = std.mem.sliceTo(name, 0);
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    const new_name = std.fmt.bufPrintZ(&buf, "{s}.new", .{name_slice}) catch return;

    _ = remove_tree(std.mem.sliceTo(name, 0));
    _ = c.renameat(basedir, new_name.ptr, basedir, name);
}

// Application executor

fn alloc_cpath(
    S: ?*c.struct_a12_state,
    dir: ?*c.struct_directory_meta,
    name: ?[*:0]const u8,
) callconv(.c) ?*anyopaque {
    const A = &active_appls.active;
    const gpa = std.heap.c_allocator;
    const res = gpa.create(c.struct_launcher_meta) catch return null;
    res.* = std.mem.zeroes(c.struct_launcher_meta);

    const name_z = name.?;
    const name_slice = std.mem.span(name_z);
    var pbuf: [std.fs.max_path_bytes]u8 = undefined;
    const pbuf_z = std.fmt.bufPrintZ(&pbuf, "./{s}", .{name_slice}) catch {
        gpa.destroy(res);
        return null;
    };

    const override: ?[*:0]const u8 = if (dir != null and dir.?.clopt != null)
        @as(?[*:0]const u8, @ptrCast(dir.?.clopt.*.appl_override))
    else
        null;
    const path: [*:0]const u8 = override orelse pbuf_z.ptr;

    if (!anet_client_execargs(name_z, path, res, A.manifest)) {
        _ = c.fprintf(c.stderr, "allocator: couldn't build launcher arguments\n");
        gpa.destroy(res);
        return null;
    }
    _ = S;
    return res;
}

fn exec_cpath(
    S: ?*c.struct_a12_state,
    dir: ?*c.struct_directory_meta,
    name: ?[*:0]const u8,
    tag: ?*anyopaque,
    inf: ?*c_int,
    outf: ?*c_int,
) callconv(.c) c.pid_t {
    _ = S;
    _ = name;
    const ctx: *c.struct_launcher_meta = @ptrCast(@alignCast(tag.?));
    const d: *c.struct_directory_meta = dir.?;

    cl_global.child_signal.store(-1, .monotonic);
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    // struct sigaction: on glibc Linux the first field is the handler pointer
    // (sa_handler / sa_sigaction as an anonymous union). Our libc shim
    // represents the struct as an opaque 152-byte blob; write the handler
    // function pointer directly at offset 0.
    const SigHandlerPtr = *const fn (c_int) callconv(.c) void;
    @as(*SigHandlerPtr, @ptrCast(@alignCast(&sa))).* = &child_signal_handler;
    _ = c.sigaction(c.SIGCHLD, &sa, null);

    const pid = c.fork();
    if (pid == 0) {
        // Child process
        _ = c.fchdir(d.clopt.*.basedir);
        _ = c.setsid();
        _ = c.dup2(ctx.pstdin[0], c.STDIN_FILENO);
        _ = c.close(ctx.pstdin[0]);
        _ = c.close(ctx.pstdin[1]);
        _ = c.close(ctx.pstdout[0]);

        if (!d.clopt.*.stderr_log) {
            _ = c.close(c.STDERR_FILENO);
            _ = c.open("/dev/null", c.O_WRONLY);
        }

        const SIGUNUSED: c_int = 31;
        var i: c_int = 1;
        while (i < SIGUNUSED) : (i += 1) {
            // SIG_DFL is a compileError in the cimport (macro with cast of 0)
            _ = c.signal(i, null);
        }

        _ = c.execvpe(
            ctx.bin.?,
            @ptrCast(ctx.argv.?),
            @ptrCast(ctx.env.?),
        );
        c.exit(c.EXIT_FAILURE);
    }

    _ = c.close(ctx.pstdin[0]);
    _ = c.close(ctx.pstdout[1]);

    inf.?.* = ctx.pstdin[1];
    outf.?.* = ctx.pstdout[0];

    _ = c.fcntl(ctx.pstdin[1], c.F_SETFD, c.FD_CLOEXEC);
    _ = c.fcntl(ctx.pstdout[0], c.F_SETFD, c.FD_CLOEXEC);

    // Free env and argv strings
    if (ctx.env) |env| {
        var ei: usize = 0;
        while (env[ei] != null) : (ei += 1) c.free(env[ei]);
        c.free(@ptrCast(env));
    }
    if (ctx.argv) |argv| {
        var ai: usize = 0;
        while (argv[ai] != null) : (ai += 1) c.free(argv[ai]);
        c.free(@ptrCast(argv));
    }

    return pid;
}

// Source encoder setup

fn setup_source_encoder(C: *c.struct_arcan_shmif_cont, ev: *c.arcan_event) void {
    const encode_path = anet_client_lua_getpath("encode_path") orelse return;
    const encode_arg = anet_client_lua_getpath("encode_arg") orelse return;

    var env_buf: [512]u8 = undefined;
    const env_str = std.fmt.bufPrintZ(&env_buf, "ARCAN_ARG=protocol=a12:{s}", .{std.mem.sliceTo(encode_arg, 0)}) catch return;

    var env2_buf: [512]u8 = undefined;
    const statepath = c.getenv("ARCAN_STATEPATH");
    const env2_str = std.fmt.bufPrintZ(&env2_buf, "ARCAN_STATEPATH={s}", .{if (statepath) |s| std.mem.sliceTo(s, 0) else ""}) catch return;

    const envv = [_]?[*:0]const u8{ env_str.ptr, env2_str.ptr, null };
    const argv = [_]?[*:0]const u8{ encode_path, "test", null };

    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[2].iv = c.SEGID_HANDOVER;
    arcan_shmif_handover_exec(
        C,
        ev.*,
        encode_path,
        @constCast(@ptrCast(&argv)),
        @constCast(@ptrCast(&envv)),
        1 | 2 | 4 | 8,
    );
}

// Shmif event pump for appl runner

fn runner_shmif(I_raw: [*c]c.struct_ioloop_shared, ok: bool) callconv(.c) void {
    const I: *c.struct_ioloop_shared = @ptrCast(I_raw);
    const A = &active_appls.active;
    const S = I.S;
    var ev: c.arcan_event = undefined;

    while (arcan_shmif_poll(&I.shmif, &ev) > 0) {
        if (ev.unnamed_0.unnamed_0.category != @as(u8, @intCast(c.EVENT_TARGET)))
            continue;

        const tgt = &ev.unnamed_0.unnamed_0.unnamed_0.tgt;

        if (tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_OUT)) or
            tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_IN)))
        {
            // Flip direction: OUT becomes IN and vice versa
            if (tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_OUT)))
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_IN))
            else
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_OUT));

            var dch: u8 = 0;
            if (tgt.ioevs[3].iv != 0) {
                ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @as(c_int, A.applid);
            }
            if (tgt.ioevs[4].iv & 1 != 0) {
                a12_find_free_channel(S.?, &dch);
            }
            a12_set_channel(S.?, dch);
            _ = a12_channel_enqueue(S.?, &ev);
            a12_set_channel(S.?, 0);
        } else if (tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_NEWSEGMENT)) and
            tgt.ioevs[2].iv == c.SEGID_ENCODER)
        {
            setup_source_encoder(&I.shmif, &ev);
        } else if (tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_MESSAGE))) {
            var out: c.arcan_event = c.arcan_event.zeroes();
            out.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
            out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart =
                @as(u8, @intFromBool(tgt.ioevs[0].iv != 0));
            @memcpy(
                &out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data,
                &tgt.unnamed_0.message,
            );
            _ = a12_channel_enqueue(S.?, &out);
        }
    }

    const rv = arcan_shmif_poll(&I.shmif, &ev);
    if (rv == -1 or !ok) {
        arcan_shmif_drop(&I.shmif);
        I.shmif.epipe = -1;
        I.on_shmif = null;
    }
}

// State file setup

fn setup_statefd(A: *ApplRunnerState) void {
    const cbt = A.ios.?.cbt.?;

    if (cbt.clopt.*.dump_state) |ds| {
        const ds_slice = std.mem.sliceTo(ds, 0);
        if (std.mem.eql(u8, ds_slice, "-")) {
            A.state.fpek = c.stderr;
            A.state.active = true;
            return;
        }
        A.state.fpek = c.fopen(ds, "we");
        A.state.active = A.state.fpek != null;
        return;
    }

    var template = "statetemp-XXXXXX".*;
    A.state.fd = c.mkstemp(&template);

    if (A.state.fd == -1) {
        _ = c.fprintf(c.stderr, "Couldn't create temp-store, state transfer disabled\n");
        return;
    }
    _ = c.unlink(&template);

    // Switch to blocking
    _ = c.fcntl(A.p_stdout, c.F_SETFL, @as(c_int, 0));
    A.state.fpek = c.fdopen(A.state.fd, "we");
    _ = c.fcntl(A.state.fd, c.F_SETFD, c.FD_CLOEXEC);
    A.state.active = true;
}

// Process stdin (admin / debug interface)

fn process_stdin(I_raw: [*c]c.struct_ioloop_shared, ok: bool) callconv(.c) void {
    const I: *c.struct_ioloop_shared = @ptrCast(I_raw);
    _ = ok;
    var buf: [4096]u8 = undefined;
    if (c.fgets(&buf, 4096, c.stdin) == null) return;

    var out: c.arcan_event = c.arcan_event.zeroes();
    out.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));

    var ntc = c.strlen(&buf);
    if (ntc <= 1) return;
    ntc -= 1;
    buf[ntc] = 0;

    const msg_sz = @sizeOf(@TypeOf(out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data));
    var ofs: usize = 0;
    while (ntc > 0) {
        const len: usize = if (ntc > msg_sz) msg_sz - 1 else ntc;
        @memcpy(
            out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0..len],
            buf[ofs .. ofs + len],
        );
        out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[len] = 0;
        ntc -= len;
        ofs += len;
        out.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart = @intFromBool(ntc > 0);
        _ = a12_channel_enqueue(I.S.?, &out);
    }
}

// Appl runner cleanup

fn cleanup_runner(
    I: *c.struct_ioloop_shared,
    A: *ApplRunnerState,
    cbt: *c.struct_directory_meta,
    S: *c.struct_a12_state,
    n_memb: usize,
) void {
    // Block until child exits
    while (true) {
        const v = cl_global.child_signal.load(.monotonic);
        if (v != -1) break;
    }
    const pret = cl_global.child_signal.load(.monotonic);

    if (!cbt.clopt.*.keep_appl)
        _ = clean_appldir(@ptrCast(&cbt.clopt.*.applname), cbt.clopt.*.basedir);

    var exec_res = false;
    if (c.WIFEXITED(pret)) {
        _ = c.fprintf(c.stderr, "arcan(%s) exited\n", @as([*c]const u8, @ptrCast(&cbt.clopt.*.applname)));
        exec_res = true;
        if (c.WEXITSTATUS(pret) != 0)
            _ = c.fprintf(c.stderr, "script/execution error, generating report\n");
    }

    if (A.state.fpek == null and cbt.clopt.*.block_state)
        return cleanup_runner_out(I, A, cbt, S);

    const sz = if (A.state.fpek) |fp| c.ftell(fp) else 0;
    var empty_ext = [_]u8{0} ** 16;

    if (A.fail_state or exec_res) {
        a12_enqueue_bstream(
            S,
            A.state.fd,
            c.A12_BTYPE_CRASHDUMP,
            cbt.clopt.*.applid,
            false,
            sz,
            &empty_ext,
        );
    } else if (n_memb > 0 or A.n_keys_in > 0) {
        a12_enqueue_bstream(
            S,
            A.state.fd,
            c.A12_BTYPE_STATE,
            cbt.clopt.*.applid,
            false,
            sz,
            &empty_ext,
        );
    }

    if (A.state.fpek) |fp| {
        if (fp != c.stderr) _ = c.fclose(fp);
    }

    a12_shutdown_id(S, cbt.clopt.*.applid);

    cleanup_runner_out(I, A, cbt, S);
}

fn cleanup_runner_out(
    I: *c.struct_ioloop_shared,
    A: *ApplRunnerState,
    cbt: *c.struct_directory_meta,
    S: *c.struct_a12_state,
) void {
    _ = S;
    if (cbt.clopt.*.reload) {
        a12int_request_dirlist(I.S.?, true);
    } else {
        I.shutdown = A.state.fpek == null;
    }

    if (A.pf_stdin) |pf| {
        _ = c.fclose(pf);
        A.pf_stdin = null;
        A.p_stdin = -1;
    }
    if (A.pf_stdout) |pf| {
        _ = c.fclose(pf);
        A.pf_stdout = null;
        A.p_stdout = -1;
    }

    A.pid = 0;
    I.on_event = null;
    I.userfd = -1;
    I.on_userfd = null;
    _ = active_appls.n_active.fetchSub(1, .monotonic);
}

// Process thread: monitor arcan process stdout

fn process_thread(I_raw: [*c]c.struct_ioloop_shared, ok: bool) callconv(.c) void {
    const I: *c.struct_ioloop_shared = @ptrCast(I_raw);
    const A = &active_appls.active;
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);
    const S = I.S.?;

    var buf: [4096]u8 = undefined;
    var n_memb: usize = 0;

    if (A.state.active) {
        while (c.fgets(&buf, 4096, A.pf_stdout.?) != null) {
            _ = c.fputs(@as([*:0]const u8, @ptrCast(&buf)), A.state.fpek.?);
            if (std.mem.eql(u8, std.mem.sliceTo(&buf, 0), "#ENDKV\n")) {
                A.state.active = false;
                _ = c.fflush(A.state.fpek.?);
                _ = c.fprintf(
                    A.pf_stdin.?,
                    if (A.queue_terminate) "terminate\n" else "continue\n",
                );
                _ = c.fcntl(A.p_stdout, c.F_SETFL, c.O_NONBLOCK);
                break;
            } else {
                n_memb += 1;
            }
        }

        if (!ok) cleanup_runner(I, A, cbt, S, n_memb);
        return;
    }

    if (!ok) return cleanup_runner(I, A, cbt, S, n_memb);

    const enable_dump = if (cbt.clopt.*.dump_state != null)
        true
    else
        !cbt.clopt.*.block_state;

    while (c.fgets(&buf, 4096, A.pf_stdout.?) != null) {
        const line = std.mem.sliceTo(&buf, 0);

        if (std.mem.eql(u8, line, "#LOCKED\n")) {
            swap_appldir(@ptrCast(&cbt.clopt.*.applname), cbt.clopt.*.basedir);
            _ = c.fprintf(A.pf_stdin.?, "reload\n");
            _ = c.fprintf(A.pf_stdin.?, "continue\n");
            _ = c.fprintf(A.pf_stdin.?, "continue\n");
        } else if (std.mem.eql(u8, line, "#FINISH\n")) {
            _ = c.fprintf(A.pf_stdin.?, if (enable_dump) "dumpkeys\n" else "continue\n");
            return;
        } else if (std.mem.eql(u8, line, "#WAITING\n")) {
            if (A.queue_terminate)
                _ = c.fprintf(A.pf_stdin.?, "terminate\n");
        } else if (std.mem.eql(u8, line, "#FAIL\n") or std.mem.eql(u8, line, "#BEGINBACKTRACE\n")) {
            if (!enable_dump) {
                _ = c.fprintf(A.pf_stdin.?, "terminate\n");
            } else {
                A.queue_terminate = true;
                A.fail_state = true;
                setup_statefd(A);
                _ = c.fprintf(A.pf_stdin.?, "dumpstate\n");
                return process_thread(I, ok);
            }
        } else if (std.mem.eql(u8, line, "#BEGINKV\n")) {
            setup_statefd(A);
            _ = c.fputs(@as([*:0]const u8, @ptrCast(&buf)), A.state.fpek.?);
            return process_thread(I, ok);
        } else if (std.mem.startsWith(u8, line, "join ")) {
            if (I.shmif.addr != null)
                arcan_shmif_drop(&I.shmif);

            // Strip the trailing newline and extract path
            var cbuf: [4096]u8 = undefined;
            const rest = line[5..];
            const trimmed = std.mem.trimRight(u8, rest, "\n");
            @memcpy(cbuf[0..trimmed.len], trimmed);
            cbuf[trimmed.len] = 0;

            var dfd: c_int = undefined;
            const key = arcan_shmif_connect(@ptrCast(&cbuf), null, &dfd) orelse return;
            _ = c.fcntl(dfd, c.F_SETFD, c.FD_CLOEXEC);

            I.shmif = arcan_shmif_acquire(null, key, c.SEGID_NETWORK_CLIENT, 0);
            I.shmif.epipe = dfd;
            I.on_shmif = runner_shmif;

            if (I.shmif.addr == null) return;

            send_join_ident(I, cbt);
            runner_shmif(I, true);
        }
    }
}

// State injection into child process

fn send_state(dst: *c.FILE, src: ?*c.FILE) usize {
    const s = src orelse return 0;
    _ = c.fseek(s, 0, c.SEEK_SET);

    var buf: [4096]u8 = undefined;
    var in_kv = false;
    var n_keys: usize = 0;

    while (c.fgets(&buf, 4096, s) != null) {
        const line = std.mem.sliceTo(&buf, 0);
        if (in_kv) {
            if (std.mem.eql(u8, line, "#ENDKV\n")) {
                in_kv = false;
                continue;
            }
            n_keys += 1;
            _ = c.fputs("loadkey ", dst);
            _ = c.fputs(@as([*:0]const u8, @ptrCast(&buf)), dst);
        } else {
            if (std.mem.eql(u8, line, "#BEGINKV\n"))
                in_kv = true;
        }
    }
    return n_keys;
}

// Reconnect on directory loss

pub export fn retry_directory_connection(I_raw: [*c]c.struct_ioloop_shared) bool {
    const I: *c.struct_ioloop_shared = @ptrCast(I_raw);
    {
        var lost = c.arcan_event.zeroes();
        lost.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
        lost.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
        lost.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 6;
        lost.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 0;
        arcan_shmif_enqueue(&I.shmif, &lost);
    }

    _ = c.fprintf(c.stderr, "connection lost, reconnecting\n");
    global.dircl.last_connection.retry_count = 1;

    while (true) {
        const con = anet_cl_setup(&global.dircl.last_connection);

        var ev: c.arcan_event = undefined;
        if (arcan_shmif_poll(&I.shmif, &ev) < 0) {
            _ = c.fprintf(c.stderr, "runner terminated during reconnect\n");
            I.shutdown = true;
            return false;
        }

        if (con.state) |state| {
            a12_free(I.S.?);
            I.S = state;
            I.fdin = con.fd;
            I.fdout = con.fd;

            {
                var rejoin = c.arcan_event.zeroes();
                rejoin.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
                rejoin.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_NETSTATE));
                rejoin.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.space = 6;
                rejoin.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 1;
                arcan_shmif_enqueue(&I.shmif, &rejoin);
            }

            _ = a12_channel_enqueue(I.S.?, &active_appls.active.join_event);
            return true;
        } else {
            _ = c.sleep(1);
        }
    }
}

// Handover execution of appl in child process

fn handover_exec(A: *ApplRunnerState, sin: ?*c.FILE) bool {
    const I = A.ios.?;
    const dir: *c.struct_directory_meta = @ptrCast(I.cbt);
    const opts = dir.clopt;

    const tag = opts.*.allocator.?(I.S, dir, @ptrCast(&opts.*.applname)) orelse {
        I.shutdown = true;
        _ = c.fprintf(c.stderr, "executor-alloc failed");
        if (sin) |s| _ = c.fclose(s);
        return false;
    };

    A.p_stdin = -1;
    A.p_stdout = -1;

    const pid = opts.*.executor.?(I.S, dir, @ptrCast(&opts.*.applname), tag, &A.p_stdin, &A.p_stdout);

    if (pid <= 0) {
        c.free(tag);
        if (sin) |s| _ = c.fclose(s);
        _ = c.fprintf(c.stderr, "executor-failed");
        return false;
    }

    if (pid == -1) {
        _ = clean_appldir(@ptrCast(&opts.*.applname), opts.*.basedir);
        _ = c.fprintf(c.stderr, "Couldn't spawn child process");
        return false;
    }

    _ = c.fcntl(A.p_stdout, c.F_SETFL, c.O_NONBLOCK);

    A.pid = pid;
    A.pf_stdin = c.fdopen(A.p_stdin, "w");
    A.pf_stdout = c.fdopen(A.p_stdout, "r");
    _ = c.setlinebuf(A.pf_stdin.?);
    _ = c.setlinebuf(A.pf_stdout.?);

    if (!opts.*.block_state) {
        A.n_keys_in = send_state(A.pf_stdin.?, sin);
    }
    _ = c.fprintf(A.pf_stdin.?, "continue\n");

    I.userfd = A.p_stdout;
    I.on_userfd = process_thread;
    I.tag = A;

    if (opts.*.reconnect)
        I.on_disconnected = retry_directory_connection;

    return true;
}

// Appl runner (called from main thread or detached thread)

pub export fn appl_runner(tag: ?*anyopaque) ?*anyopaque {
    const S: *ApplRunnerState = @ptrCast(@alignCast(tag.?));
    const cbt: *c.struct_directory_meta = @ptrCast(S.ios.?.cbt);

    var state_in: ?*c.FILE = null;
    if (cbt.state_in != -1) {
        _ = c.lseek(cbt.state_in, 0, c.SEEK_SET);
        state_in = c.fdopen(cbt.state_in, "r");
        cbt.state_in = -1;
        cbt.state_in_complete = false;
    }

    swap_appldir(@ptrCast(&cbt.clopt.*.applname), cbt.clopt.*.basedir);
    _ = handover_exec(S, state_in);
    return null;
}

// Binary transfer completion

pub export fn dircl_xfer_complete(I: *c.struct_ioloop_shared, M: c.struct_a12_bhandler_meta) void {
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);

    if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_STATE))) {
        cbt.state_in_complete = true;
    } else if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_APPL))) {
        cbt.appl_out_complete = true;
    }

    if (cbt.state_in != -1 and !cbt.state_in_complete) return;
    if (!cbt.appl_out_complete) return;

    const has_override = cbt.clopt.*.appl_override != null;

    if (cbt.appl_out == null and !has_override) {
        _ = c.fprintf(c.stderr, "xfer completed on blob without an active state\n");
        I.shutdown = true;
        return;
    }

    var manifest: ?*c.struct_arg_arr = null;

    if (!has_override) {
        var buf_ptr: ?[*]u8 = null;
        var buf_sz: usize = 0;
        const fin = file_to_membuf(cbt.appl_out.?, &buf_ptr, &buf_sz) orelse {
            _ = c.fprintf(c.stderr, "unpack appl failed: couldn't read into memory\n");
            I.shutdown = true;
            return;
        };
        _ = c.fclose(fin);

        const buf = buf_ptr orelse {
            I.shutdown = true;
            return;
        };

        var err_msg_ptr: ?[*:0]const u8 = null;
        var nullsig = [_]u8{0} ** 32;
        const verified_name = verify_appl_pkg(buf, buf_sz, &nullsig, &nullsig, &err_msg_ptr);
        if (verified_name == null) {
            _ = c.fprintf(c.stderr, "verify appl failed: %s\n", err_msg_ptr orelse @as([*:0]const u8, "(no error reason)"));
            c.free(buf);
            I.shutdown = true;
            return;
        }
        c.free(@ptrCast(verified_name));

        const fextract = c.fmemopen(buf, buf_sz, "r") orelse {
            c.free(buf);
            I.shutdown = true;
            return;
        };

        const name_slice = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&cbt.clopt.*.applname)), 0);
        var newname_buf: [32]u8 = undefined;
        const newname = std.fmt.bufPrintZ(&newname_buf, "{s}.new", .{name_slice}) catch {
            _ = c.fclose(fextract);
            I.shutdown = true;
            return;
        };

        var msg: ?[*:0]const u8 = null;
        if (!extract_appl_pkg(fextract, cbt.clopt.*.basedir, newname.ptr, &msg, &manifest)) {
            _ = c.fprintf(c.stderr, "unpack appl failed: %s\n", msg);
            _ = c.fclose(fextract);
            if (manifest) |m| arg_cleanup(m);
            I.shutdown = true;
            return;
        }
        _ = c.fclose(fextract);
    }

    cbt.appl_out = null;
    cbt.appl_out_complete = false;

    if (active_appls.n_active.load(.monotonic) > 0) {
        _ = c.fprintf(active_appls.active.pf_stdin.?, "lock\n");
        _ = c.kill(active_appls.active.pid, c.SIGUSR1);
        _ = c.fprintf(c.stderr, "signalling=%d\n", active_appls.active.pid);
        return;
    }

    _ = active_appls.n_active.fetchAdd(1, .monotonic);
    active_appls.active.ios = I;
    active_appls.active.manifest = manifest;

    _ = appl_runner(&active_appls.active);
}

// Binary handlers

fn anet_directory_cl_stdiofeed(
    S: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) callconv(.c) c.struct_a12_bhandler_res {
    _ = S;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const res = c.struct_a12_bhandler_res{
        .fd = c.STDOUT_FILENO,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD)),
    };

    switch (M.state) {
        @as(c_uint, @bitCast(c.A12_BHANDLER_INITIALIZE)) => {},
        else => {
            // CANCELLED or COMPLETED
            I.shutdown = true;
        },
    }
    return res;
}

fn dircl_event(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = cont;
    _ = chid;
    const event = ev orelse return;
    if (event.unnamed_0.unnamed_0.unnamed_0.ext.kind == @as(c_uint, @bitCast(c.EVENT_EXTERNAL_STREAMSTATUS))) {
        const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
        I.shutdown = true;
    }
}

fn on_cl_event(
    cont: ?*c.struct_arcan_shmif_cont,
    chid: c_int,
    ev: ?*c.arcan_event,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = cont;
    _ = chid;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const S = I.S.?;
    const event = ev orelse return;

    // State file request failed — synthesize completion
    if (event.unnamed_0.unnamed_0.category == @as(u8, @intCast(c.EVENT_TARGET)) and
        event.unnamed_0.unnamed_0.unnamed_0.tgt.kind == @as(c_uint, @bitCast(c.TARGET_COMMAND_REQFAIL)) and
        event.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].uiv == 0xf00f00f)
    {
        dircl_xfer_complete(I, .{ .type = @as(c_uint, @bitCast(c.A12_BTYPE_STATE)) });
        return;
    }

    if (I.shmif.addr == null) {
        _ = c.fprintf(
            c.stdout,
            "%s%s",
            @as([*:0]const u8, @ptrCast(&event.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0])),
            @as([*c]const u8, if (event.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart != 0) "" else "\n"),
        );
        return;
    }

    if (event.unnamed_0.unnamed_0.category == @as(u8, @intCast(c.EVENT_EXTERNAL)) and
        event.unnamed_0.unnamed_0.unnamed_0.ext.kind == @as(c_uint, @bitCast(c.EVENT_EXTERNAL_MESSAGE)))
    {
        arcan_shmif_enqueue(&I.shmif, event);
    }
    _ = S;
}

fn anet_directory_cl_upload(
    S: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) callconv(.c) c.struct_a12_bhandler_res {
    _ = S;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_DONTWANT)),
    };

    switch (M.state) {
        @as(c_uint, @bitCast(c.A12_BHANDLER_INITIALIZE)) => {},
        @as(c_uint, @bitCast(c.A12_BHANDLER_CANCELLED)) => {
            _ = c.fprintf(c.stderr, "Error: Server rejected upload\n");
        },
        else => {},
    }

    I.shutdown = true;
    return res;
}

fn anet_directory_cl_download(
    S: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) callconv(.c) c.struct_a12_bhandler_res {
    _ = S;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const dir: *c.struct_directory_meta = @ptrCast(I.cbt);
    const opts = dir.clopt;

    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_DONTWANT)),
    };

    switch (M.state) {
        @as(c_uint, @bitCast(c.A12_BHANDLER_INITIALIZE)) => {
            const dl_path_ptr = opts.*.download.path.?;
            const dl_path = std.mem.sliceTo(dl_path_ptr, 0);
            if (std.mem.eql(u8, dl_path, "-")) {
                res.fd = c.STDOUT_FILENO;
                res.flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD));
            } else {
                const fd = c.open(dl_path_ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o600));
                if (fd != -1) {
                    res.fd = fd;
                    res.flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD));
                }
            }
        },
        @as(c_uint, @bitCast(c.A12_BHANDLER_CANCELLED)) => {},
        @as(c_uint, @bitCast(c.A12_BHANDLER_COMPLETED)) => {
            I.shutdown = true;
        },
        else => {},
    }

    return res;
}

fn initialize_state_download(
    S: ?*c.struct_a12_state,
    M: *c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) c.struct_a12_bhandler_res {
    _ = S;
    _ = M;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);
    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_DONTWANT)),
    };

    if (cbt.state_in != -1) {
        _ = c.fprintf(c.stderr, "Server sent multiple state blocks, ignoring\n");
        return res;
    }

    var template = "statetemp-XXXXXX".*;
    cbt.state_in = c.mkstemp(&template);
    if (cbt.state_in == -1) {
        _ = c.fprintf(c.stderr, "Couldn't allocate temp-store, ignoring state\n");
        return res;
    }
    _ = c.fcntl(cbt.state_in, c.F_SETFD, c.FD_CLOEXEC);

    cbt.state_in_complete = true;
    res.fd = cbt.state_in;
    res.flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD));
    _ = c.unlink(&template);
    return res;
}

fn initialize_appl_download(
    S: ?*c.struct_a12_state,
    M: *c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) c.struct_a12_bhandler_res {
    _ = S;
    _ = M;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);

    var res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_DONTWANT)),
    };

    if (cbt.appl_out != null) {
        _ = c.fprintf(c.stderr, "Appl transfer initiated while one was pending\n");
        return res;
    }

    var fn_ptr: ?[*:0]u8 = null;
    const appl_fd = dircl_apphash_cached(cbt.appl_hash[0..4], @ptrCast(&cbt.clopt.*.applname), &fn_ptr);

    if (appl_fd > 0) {
        // Cache hit
        cbt.appl_out = c.fdopen(appl_fd, "r");
        if (fn_ptr) |fp| c.free(fp);
        return res;
    } else if (appl_fd == 0) {
        // Open for caching
        const fd = c.open(fn_ptr.?, c.O_CREAT | c.O_RDWR | c.O_TRUNC, @as(c_uint, 0o600));
        if (fn_ptr) |fp| c.free(fp);
        cbt.appl_out = c.fdopen(fd, "rw");
        res.flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD));
        res.fd = fd;
    } else {
        // Temporary file, no cache
        if (fn_ptr) |fp| c.free(fp);
        var template = "appltemp-XXXXXX".*;
        const fd = c.mkstemp(&template);
        if (fd == -1) {
            _ = c.fprintf(c.stderr, "Couldn't create temporary appl- unpack store\n");
            return res;
        }
        _ = c.unlink(&template);
        cbt.appl_out = c.fdopen(fd, "rw");
        res.flag = @as(c_uint, @bitCast(c.A12_BHANDLER_NEWFD));
        res.fd = fd;
    }

    return res;
}

pub export fn anet_directory_cl_bhandler(
    S: ?*c.struct_a12_state,
    M: c.struct_a12_bhandler_meta,
    tag: ?*anyopaque,
) c.struct_a12_bhandler_res {
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);

    const res = c.struct_a12_bhandler_res{
        .fd = -1,
        .flag = @as(c_uint, @bitCast(c.A12_BHANDLER_DONTWANT)),
    };

    var M_mut = M;

    switch (M.state) {
        @as(c_uint, @bitCast(c.A12_BHANDLER_COMPLETED)) => {
            dircl_xfer_complete(I, M);
        },
        @as(c_uint, @bitCast(c.A12_BHANDLER_INITIALIZE)) => {
            if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_STATE)))
                return initialize_state_download(S, &M_mut, tag)
            else if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_APPL)))
                return initialize_appl_download(S, &M_mut, tag);
        },
        @as(c_uint, @bitCast(c.A12_BHANDLER_CANCELLED)) => {
            if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_STATE))) {
                _ = c.fprintf(c.stderr, "appl state transfer cancelled\n");
                _ = c.close(cbt.state_in);
                cbt.state_in = -1;
                cbt.state_in_complete = false;
            } else if (M.type == @as(c_uint, @bitCast(c.A12_BTYPE_APPL))) {
                _ = c.fprintf(c.stderr, "appl download cancelled\n");
                if (cbt.appl_out != null) {
                    cbt.appl_out = null;
                    cbt.appl_out_complete = false;
                }
                _ = clean_appldir(@ptrCast(&cbt.clopt.*.applname), cbt.clopt.*.basedir);
            }
        },
        else => {},
    }

    return res;
}

// File upload

fn upload_file(S: *c.struct_a12_state, path: [*:0]const u8, ns: usize, name: [*:0]const u8) void {
    a12_channel_bprogress_hook(S, 0, 1024 * 1024, output_progress, null);

    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_TARGET));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @as(c_uint, @bitCast(c.TARGET_COMMAND_BCHUNK_OUT));
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].uiv = @as(c_uint, @intCast(ns));
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0])),
        68,
        "%s",
        name,
    );

    const path_slice = std.mem.sliceTo(path, 0);
    if (std.mem.eql(u8, path_slice, "-")) {
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = c.STDIN_FILENO;
    } else {
        const infd = c.open(path, c.O_RDONLY, @as(c_uint, 0));
        if (infd == -1) {
            _ = c.fprintf(c.stderr, "couldn't open %s\n", path);
            return;
        }
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = infd;
        _ = a12_channel_enqueue(S, &ev);
        _ = c.close(infd);
    }
}

// Dynamic resource discovery

fn cl_got_dyn(
    S: [*c]c.struct_a12_state,
    type_: u8,
    petname: [*c]const u8,
    state: u8,
    pubk: [*c]u8,
    id: u16,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = id;
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);

    const add_ch: u8 = switch (type_) {
        2 => '+',
        5 => '/',
        else => '<',
    };
    const found = state > 0;

    _ = c.printf(
        "source-%s=%c%s\n",
        @as([*c]const u8, if (found) "found" else "lost"),
        @as(c_int, add_ch),
        petname,
    );

    if (state == 2) {
        a12_request_dynamic_resource(S, pubk, true, dircl_source_handler, I);
        return;
    }

    const appl_name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&cbt.clopt.*.applname)), 0);
    if (appl_name.len == 0 or appl_name[0] != '<') return;
    if (petname == null) return;
    const pname = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(petname)), 0);
    if (!std.mem.eql(u8, appl_name[1..], pname)) return;

    var outl: usize = 0;
    const req_b64 = a12helper_tob64(pubk, 32, &outl);
    defer if (req_b64 != null) c.free(req_b64);

    a12_request_dynamic_resource(S, pubk, cbt.clopt.*.request_tunnel, dircl_source_handler, I);
}

// Appl list scanning

fn scan_for_appl(C: [*c]c.struct_appl_meta, name: ?[*:0]const u8) [*c]c.struct_appl_meta {
    var node = C;
    while (node != null) {
        const n = node;
        const nm = if (name) |p| std.mem.sliceTo(p, 0) else "";
        if (nm.len == 0) {
            _ = c.printf(
                "id=%u:size=%llu:name=%s%s%s\n",
                @as(c_uint, n.*.identifier),
                @as(c_ulonglong, n.*.buf_sz),
                @as([*c]const u8, &n.*.appl.name[0]),
                @as([*c]const u8, if (n.*.appl.short_descr[0] != 0) ":description=" else ""),
                if (n.*.appl.short_descr[0] != 0) @as([*c]const u8, &n.*.appl.short_descr[0]) else @as([*c]const u8, ""),
            );
        } else if (std.mem.eql(u8, nm, std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&n.*.appl.name)), 0))) {
            return n;
        }
        node = n.*.next;
    }
    return null;
}

fn cl_send_appl_update(I: *c.struct_ioloop_shared, dir: [*c]c.struct_appl_meta) bool {
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);
    const S = I.S.?;
    var C = dir;

    const out_name = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(&cbt.clopt.*.outapp.appl.name)), 0);
    if (out_name.len > 0)
        C = scan_for_appl(C, @as([*:0]const u8, @ptrCast(&cbt.clopt.*.outapp.appl.name[0])));

    if (C == null) {
        cbt.clopt.*.outapp.identifier = 65535;
    } else {
        cbt.clopt.*.outapp.identifier = C.*.identifier;
    }

    cbt.transfer_id = cbt.clopt.*.outapp.identifier;
    cbt.in_transfer = true;
    I.on_event = dircl_event;

    if (cbt.clopt.*.sign_tag) |st| {
        var pubk: [32]u8 = undefined;
        var privk: [64]u8 = undefined;
        a12helper_keystore_get_sigkey(st, &pubk, &privk);
        a12_set_signing_pair(S, &pubk, &privk);
    }

    a12_channel_bprogress_hook(S, 0, 1024 * 1024, output_progress, null);
    a12_enqueue_blob(
        S,
        cbt.clopt.*.outapp.buf,
        cbt.clopt.*.outapp.buf_sz,
        cbt.clopt.*.outapp.identifier,
        if (cbt.clopt.*.outapp_ctrl) c.A12_BTYPE_APPL_CONTROLLER else c.A12_BTYPE_APPL,
        @ptrCast(&cbt.clopt.*.outapp.appl.name[0]),
    );

    cbt.clopt.*.outapp.appl.name[0] = 0;
    cbt.clopt.*.outapp.buf = null;
    return true;
}

fn ensure_appl_basedir(cbt: *c.struct_directory_meta) bool {
    if (cbt.clopt.*.basedir != -1) return true;

    const dst = anet_client_lua_getpath("unpack_temp") orelse "/tmp";
    const dst_slice = std.mem.sliceTo(dst, 0);

    const written = c.snprintf(
        &cbt.clopt.*.basedir_path,
        c.PATH_MAX,
        "%s/appltemp-XXXXXX",
        dst_slice.ptr,
    );
    if (written < 0) return false;

    if (c.mkdtemp(@as([*:0]u8, @ptrCast(&cbt.clopt.*.basedir_path))) == null) {
        _ = c.fprintf(c.stderr, "Couldn't build a temporary storage base\n");
        return false;
    }

    cbt.clopt.*.basedir = c.open(@as([*:0]const u8, @ptrCast(&cbt.clopt.*.basedir_path)), c.O_DIRECTORY | c.O_CLOEXEC, @as(c_uint, 0));
    return cbt.clopt.*.basedir != -1;
}

fn cl_got_dir(I_raw: [*c]c.struct_ioloop_shared, dir: [*c]c.struct_appl_meta) callconv(.c) bool {
    const I: *c.struct_ioloop_shared = @ptrCast(I_raw);
    const cbt: *c.struct_directory_meta = @ptrCast(I.cbt);
    const req = cbt.clopt;

    if (req.*.outapp.buf != null)
        return cl_send_appl_update(I, dir);

    var name: ?[*:0]const u8 = if (req.*.applname[0] != 0) @ptrCast(&req.*.applname[0]) else null;
    if (req.*.download.srvname[0] != 0)
        name = @ptrCast(&req.*.download.srvname[0])
    else if (req.*.upload.srvname[0] != 0)
        name = @ptrCast(&req.*.upload.srvname[0]);

    const matched = scan_for_appl(dir, name);
    if (matched == null) {
        const appl_name_first = if (req.*.applname[0] != 0) req.*.applname[0] else 0;
        return !(req.*.die_on_list and appl_name_first != '<');
    }
    const d: *c.struct_appl_meta = @ptrCast(matched);

    req.*.applid = d.identifier;

    if (req.*.monitor_mode == c.MONITOR_SIMPLE) {
        send_join_ident(I, cbt);
        return true;
    } else if (req.*.monitor_mode == c.MONITOR_DEBUGGER) {
        attach_appl_debug(I, cbt);
        return true;
    }

    if (req.*.upload.name != null) {
        upload_file(I.S.?, req.*.upload.path.?, req.*.applid, req.*.upload.name.?);
        a12_set_bhandler(I.S.?, anet_directory_cl_upload, I);
        I.on_event = dircl_event;
        return true;
    } else if (req.*.download.name != null) {
        a12_channel_bprogress_hook(I.S.?, 0, 1024 * 1024, output_progress, null);
        a12_set_bhandler(I.S.?, anet_directory_cl_download, I);
        a12_request_file(I.S.?, 0, req.*.applid, 0xfeedface, req.*.download.name.?);
        I.on_event = dircl_event;
        return true;
    }

    if (req.*.applhost) {
        a12_request_file(I.S.?, 0, d.identifier, 0xfeedface, ".applhost");
        cl_global.die_on_tunnel = true;
        return true;
    }

    a12_set_bhandler(I.S.?, anet_directory_cl_bhandler, I);

    if (!ensure_appl_basedir(cbt)) return false;

    // Check cache (or skip cache + download entirely when --force-appl is set).
    const cfd = dircl_apphash_cached(&d.hash, &req.*.applname, null);
    if (cfd > 0 or req.*.appl_override != null) {
        cbt.appl_out_complete = true;

        if (req.*.appl_override == null) {
            cbt.appl_out = c.fdopen(cfd, "r");
            if (cbt.appl_out == null) return false;
        }

        if (req.*.block_state) {
            dircl_xfer_complete(I, .{ .type = @as(c_uint, @bitCast(c.A12_BTYPE_APPL)) });
            return true;
        }
        a12_request_file(I.S.?, 0, d.identifier, 0xf00f00f, ".state");
        return true;
    }

    @memcpy(&cbt.appl_hash, d.hash[0..4]);

    a12_channel_bprogress_hook(I.S.?, 0, 1024 * 1024, output_progress, null);
    a12_request_file(I.S.?, 0, d.identifier, 0xfeedface, "");
    return true;
}

// Attach appl debug / join ident

fn attach_appl_debug(I: *c.struct_ioloop_shared, cbt: *c.struct_directory_meta) void {
    a12_request_file(I.S.?, 0, cbt.clopt.*.applid, 0xcafebabe, ".monitor");
    _ = c.setlinebuf(c.stdin);
    I.userfd = c.STDIN_FILENO;
    I.on_userfd = process_stdin;
    I.on_event = on_debug_event;
    a12_set_bhandler(I.S.?, null, I);
}

fn send_join_ident(I: *c.struct_ioloop_shared, cbt: *c.struct_directory_meta) void {
    var ev: c.arcan_event = c.arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_IDENT));

    const lim = @sizeOf(@TypeOf(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data));
    const A = &active_appls.active;
    A.applid = cbt.clopt.*.applid;

    if (cbt.clopt.*.ident[0] != 0) {
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0])),
            lim,
            "%d:%s",
            @as(c_int, cbt.clopt.*.applid),
            @as([*c]const u8, &cbt.clopt.*.ident[0]),
        );
    } else {
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0])),
            lim,
            "%d",
            @as(c_int, cbt.clopt.*.applid),
        );
    }

    A.join_event = ev;
    _ = a12_channel_enqueue(I.S.?, &ev);
}

// Key authentication callback

fn key_auth_fixed(
    S: [*c]c.struct_a12_state,
    pk: [*c]u8,
    tag: ?*anyopaque,
) callconv(.c) c.struct_pk_response {
    _ = S;
    const key_auth_req: *c.struct_a12_dynreq = @ptrCast(@alignCast(tag.?));
    var auth = std.mem.zeroes(c.struct_pk_response);

    const pk_slice: *const [32]u8 = @ptrCast(pk);
    if (std.mem.eql(u8, &key_auth_req.pubk, pk_slice)) {
        a12_set_session(&auth, @ptrCast(&pk[0]), @ptrCast(&key_auth_req.local_private_key[0]));
        auth.authentic = true;
    }
    return auth;
}

// Source handler

pub export fn dircl_source_handler(
    S: ?*c.struct_a12_state,
    req: c.struct_a12_dynreq,
    tag: ?*anyopaque,
) void {
    const I: *c.struct_ioloop_shared = @ptrCast(@alignCast(tag.?));
    var req_mut = req;

    var a12opts = c.struct_a12_context_options{};
    a12opts.local_role = c.ROLE_SINK;
    a12opts.pk_lookup = key_auth_fixed;
    a12opts.pk_lookup_tag = &req_mut;
    a12opts.disable_ephemeral_k = true;

    var port_buf: [6]u8 = undefined;
    _ = c.snprintf(&port_buf, port_buf.len, "%u", @as(c_uint, req.port));
    _ = c.snprintf(&a12opts.secret, @sizeOf(@TypeOf(a12opts.secret)), "%s", &req.authk[0]);

    var net_opts = c.struct_anet_options{};
    net_opts.retry_count = 10;
    net_opts.opts = &a12opts;
    net_opts.host = @as([*:0]const u8, @ptrCast(&req_mut.host[0]));
    net_opts.port = @as([*:0]const u8, @ptrCast(&port_buf));
    net_opts.keystore = global.meta.keystore;

    if (req.proto == 4) {
        var sv: [2]c_int = undefined;
        if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) != 0) return;
        _ = c.fcntl(sv[0], c.F_SETFD, c.FD_CLOEXEC);
        _ = c.fcntl(sv[1], c.F_SETFD, c.FD_CLOEXEC);

        const tid: u8 = @intCast(c.strtoul(@as([*:0]const u8, @ptrCast(&req_mut.host[0])), null, 10) & 0xff);
        a12_set_tunnel_sink(S.?, tid, sv[0]);

        if (I.shmif.addr != null) {
            arcan_shmif_enqueue(&I.shmif, &.{
                .unnamed_0 = .{
                    .unnamed_0 = .{
                        .unnamed_0 = .{
                            .ext = .{
                                .kind = @as(c_uint, @bitCast(@as(c_int, c.EVENT_EXTERNAL_SEGREQ))),
                                .source = 0,
                                .unnamed_0 = .{
                                    .segreq = .{
                                        .kind = c.SEGID_HANDOVER,
                                        .id = 0,
                                        .width = 0,
                                        .height = 0,
                                        .xofs = 0,
                                        .yofs = 0,
                                        .dir = 0,
                                        .hints = 0,
                                    },
                                },
                                .frame_id = 0,
                            },
                        },
                        .category = @as(u8, @intCast(c.EVENT_EXTERNAL)),
                    },
                },
            });
            var acqev: c.arcan_event = undefined;
            var pqueue: [*]c.arcan_event = undefined;
            var pqueue_sz: isize = 0;
            _ = arcan_shmif_acquireloop(&I.shmif, &acqev, &pqueue, &pqueue_sz);
        }

        anet_directory_tunnel_thread(I, tid);
        detach_tunnel_runner(I, sv[1], &a12opts, &req_mut);
        I.handover = null;
        return;
    }

    const con = anet_cl_setup(&net_opts);
    if (con.errmsg != null or con.state == null) {
        _ = c.fprintf(c.stderr, "%s", if (con.errmsg) |e| e else @as([*c]const u8, "broken connection state\n"));
        return;
    }

    if (a12_remote_mode(con.state.?) != c.ROLE_SOURCE) {
        _ = c.fprintf(c.stderr, "remote endpoint is not a source\n");
        _ = c.shutdown(con.fd, c.SHUT_RDWR);
        return;
    }

    _ = a12helper_a12srv_shmifcl(I.handover, con.state.?, null, con.fd, con.fd);
    I.handover = null;
    _ = c.shutdown(con.fd, c.SHUT_RDWR);
}

// Cached appl hash lookup

pub export fn dircl_apphash_cached(
    checksum: [*c]u8,
    prefix: [*c]const u8,
    outname: ?*?[*:0]u8,
) c_int {
    const cache_path = anet_client_lua_getpath("fap_cache") orelse return -1;

    const gpa = std.heap.c_allocator;
    const hash_hex = hexenc(gpa, checksum[0..4]) catch return 0;
    // hexenc returns a sentinel-terminated slice typed as []u8; the
    // backing allocation is len+1 bytes (sentinel included), but the
    // []u8 view's .len is just the hex chars. c_allocator.free only
    // looks at .ptr (libc free knows the block size), so passing the
    // view slice frees the full allocation correctly without an OOB
    // re-slice.
    defer gpa.free(hash_hex);

    const prefix_slice = std.mem.sliceTo(prefix, 0);
    const cache_slice = std.mem.sliceTo(cache_path, 0);

    var path_buf: [std.fs.max_path_bytes + 1]u8 = undefined;
    const full_path = std.fmt.bufPrintZ(
        &path_buf,
        "{s}/{s}_{s}.fap",
        .{ cache_slice, prefix_slice, hash_hex },
    ) catch return 0;

    const fd = c.open(full_path.ptr, c.O_RDONLY | c.O_CLOEXEC, @as(c_uint, 0));

    if (outname) |p| {
        const dup = gpa.dupeZ(u8, full_path) catch {
            if (fd != -1) _ = c.close(fd);
            return 0;
        };
        p.* = dup.ptr;
    }

    if (fd == -1) return 0;
    return fd;
}

// Directory path traversal

const DpathMeta = struct {
    I: *c.struct_ioloop_shared,
    dp: *c.struct_dircl_nameent,
    pending: c.struct_anet_cl_connection = std.mem.zeroes(c.struct_anet_cl_connection),
};

fn request_dpath_handler(
    S: ?*c.struct_a12_state,
    req: c.struct_a12_dynreq,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = S;
    const target: *DpathMeta = @ptrCast(@alignCast(tag.?));
    var req_mut = req;

    var a12opts = c.struct_a12_context_options{};
    a12opts.local_role = c.ROLE_SINK;
    a12opts.pk_lookup = key_auth_fixed;
    a12opts.pk_lookup_tag = &req_mut;
    a12opts.disable_ephemeral_k = false;

    var buf: [7]u8 = undefined;
    _ = c.snprintf(&buf, buf.len, "%u", @as(c_uint, req.port));

    var net_opts = c.struct_anet_options{};
    net_opts.retry_count = 1;
    net_opts.opts = &a12opts;
    net_opts.host = @as([*:0]const u8, @ptrCast(&req_mut.host[0]));
    net_opts.port = @as([*:0]const u8, @ptrCast(&buf));
    net_opts.keystore = global.meta.keystore;

    target.pending = anet_cl_setup(&net_opts);
    global.dircl.last_connection = net_opts;
    target.I.shutdown = true;
}

fn traverse_directory_enumerate(
    S: [*c]c.struct_a12_state,
    type_: u8,
    petname: [*c]const u8,
    state: u8,
    pubk: [*c]u8,
    id: u16,
    tag: ?*anyopaque,
) callconv(.c) void {
    _ = id;
    const target: *DpathMeta = @ptrCast(@alignCast(tag.?));
    const srv_name = std.mem.sliceTo(&target.dp.srvname, 0);
    if (petname == null) return;
    const pname = std.mem.sliceTo(@as([*:0]const u8, @ptrCast(petname)), 0);

    if (!std.mem.eql(u8, srv_name, pname)) return;

    if (type_ != c.ROLE_DIRREF) {
        target.I.shutdown = true;
        return;
    }

    if (state == 0) return;

    a12_request_dynamic_resource(S, pubk, false, request_dpath_handler, target);
}

fn resolve_dpath(
    S_in: *c.struct_a12_state,
    dp: *c.struct_dircl_nameent,
    opts: c.struct_anet_dircl_opts,
    fdin: *c_int,
    fdout: *c_int,
    keepalive: bool,
) ?*c.struct_a12_state {
    _ = opts;
    _ = keepalive;
    if (dp.srvname[0] == 0) return S_in;

    var cbt = DpathMeta{
        .I = undefined,
        .dp = dp,
    };

    var ioloop = c.struct_ioloop_shared{
        .S = S_in,
        .fdin = fdin.*,
        .fdout = fdout.*,
        .userfd = -1,
        .userfd2 = -1,
        .lock = std.mem.zeroes(c.pthread_mutex_t),
    };
    cbt.I = &ioloop;

    a12_set_destination_raw(S_in, 0, .{
        .on_discover_tag = &cbt,
        .on_discover = traverse_directory_enumerate,
    }, @sizeOf(c.struct_a12_unpack_cfg));

    a12int_request_dirlist(S_in, true);
    anet_directory_ioloop(&ioloop);

    if (dp.next) |next| {
        fdin.* = cbt.pending.fd;
        fdout.* = cbt.pending.fd;
        return resolve_dpath(cbt.pending.state.?, next, std.mem.zeroes(c.struct_anet_dircl_opts), fdin, fdout, false);
    }
    return cbt.pending.state;
}

// Main directory client entry point

pub export fn anet_directory_cl(
    S_in: ?*c.struct_a12_state,
    opts_in: c.struct_anet_dircl_opts,
    fdin_in: c_int,
    fdout_in: c_int,
) void {
    var opts = opts_in;
    var fdin = fdin_in;
    var fdout = fdout_in;

    var cbt = c.struct_directory_meta{
        .S = S_in,
        .clopt = &opts,
        .state_in = -1,
    };

    if (opts.allocator == null or opts.executor == null) {
        opts.allocator = alloc_cpath;
        opts.executor = exec_cpath;
    }

    // Ignore SIGPIPE — SIG_IGN = (__sighandler_t)1 in glibc. Our libc shim
    // represents struct sigaction as an opaque 152-byte blob; write the
    // SIG_IGN sentinel directly at offset 0 (where sa_handler lives).
    var sig_ign: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    @as(*usize, @ptrCast(@alignCast(&sig_ign))).* = 1;
    _ = c.sigaction(c.SIGPIPE, &sig_ign, null);

    // Traverse any intermediate directory path hops
    var S = S_in.?;
    const resolved = resolve_dpath(S, &opts.dpath, opts, &fdin, &fdout, false);
    if (resolved == null) return;
    S = resolved.?;

    var ioloop = c.struct_ioloop_shared{
        .S = S,
        .fdin = fdin,
        .fdout = fdout,
        .userfd = -1,
        .userfd2 = -1,
        .on_event = on_cl_event,
        .on_directory = cl_got_dir,
        .lock = std.mem.zeroes(c.pthread_mutex_t),
        .cbt = &cbt,
    };

    // Short-path: private store upload
    if (opts.upload.name != null) {
        const srv_name = std.mem.sliceTo(&opts.upload.srvname, 0);
        if (std.mem.eql(u8, srv_name, ".priv")) {
            upload_file(S, opts.upload.path.?, 0, opts.upload.name.?);
            a12_set_bhandler(S, anet_directory_cl_upload, &ioloop);
            ioloop.on_event = dircl_event;
            anet_directory_ioloop(&ioloop);
            return;
        }
    }

    // Short-path: private store download
    if (opts.download.name != null) {
        const srv_name = std.mem.sliceTo(&opts.download.srvname, 0);
        if (std.mem.eql(u8, srv_name, ".priv")) {
            a12_set_bhandler(S, anet_directory_cl_download, &ioloop);
            a12_request_file(S, 0, 0, 0xfeedface, opts.download.name.?);
            ioloop.on_event = dircl_event;
            anet_directory_ioloop(&ioloop);
            return;
        }
    }

    // Short-path: admin control channel
    if (opts.monitor_mode == c.MONITOR_ADMIN) {
        a12_set_bhandler(S, anet_directory_cl_stdiofeed, &ioloop);
        a12_request_file(S, 0, 0, 0xfeedface, ".admin");
        _ = c.setlinebuf(c.stdin);
        ioloop.userfd = c.STDIN_FILENO;
        ioloop.on_userfd = process_stdin;
        anet_directory_ioloop(&ioloop);
        return;
    }

    a12_set_destination_raw(S, 0, .{
        .on_discover = cl_got_dyn,
        .on_discover_tag = &ioloop,
    }, @sizeOf(c.struct_a12_unpack_cfg));

    // Register as directory source if configured
    if (opts.dir_source) |dir_src| {
        var nk = [_]u8{0} ** 32;
        var ev: c.arcan_event = c.arcan_event.zeroes();
        ev.unnamed_0.unnamed_0.category = @as(u8, @intCast(c.EVENT_EXTERNAL));
        ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_REGISTER));
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.registr.title[0])),
            64,
            "%s",
            @as([*c]const u8, &opts.ident[0]),
        );
        _ = a12_channel_enqueue(S, &ev);
        a12_request_dynamic_resource(S, &nk, false, dir_src, opts.dir_source_tag);
    } else {
        a12int_request_dirlist(S, !opts.die_on_list or opts.applname[0] != 0);
    }

    anet_directory_ioloop(&ioloop);

    // Clean up temp basedir if we created it
    if (opts.basedir_path[0] != 0) {
        _ = c.rmdir(@as([*:0]const u8, @ptrCast(&opts.basedir_path)));
        _ = c.close(opts.basedir);
        opts.basedir = -1;
        opts.basedir_path[0] = 0;
    }
}
