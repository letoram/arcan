// Zig port of a12/net/dir_lua.c — Lua bindings for the directory server.
// Exposes directory operations (list, open, register, state) to Lua scripts
// running in the directory server VM.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport` block. Each alias routes
// to the appropriate hand-written replacement module. Lua C API calls
// continue to flow through `lua.X` via lua54_api — they are NOT aliased
// through `c` here.
const shmif = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");
const lua = @import("lua_api");

const c = struct {
    // libc — errno / fcntl / poll / pthread / signal / socket / stdio / string / unistd
    pub const AF_UNIX = libc.AF_UNIX;
    pub const close = libc.close;
    pub const EAGAIN = libc.EAGAIN;
    pub const EINTR = libc.EINTR;
    pub const fclose = libc.fclose;
    pub const fdopen = libc.fdopen;
    pub const ferror = libc.ferror;
    pub const FILE = libc.FILE;
    pub const fputc = libc.fputc;
    pub const fputs = libc.fputs;
    pub const free = libc.free;
    pub const isalnum = libc.isalnum;
    pub const kill = shmif.kill;
    pub const lseek = libc.lseek;
    pub const malloc = libc.malloc;
    pub const memcpy = libc.memcpy;
    pub const O_CLOEXEC = libc.O_CLOEXEC;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_TRUNC = libc.O_TRUNC;
    pub const openat = libc.openat;
    pub const pipe = libc.pipe;
    pub const poll = libc.poll;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const pthread_attr_init = libc.pthread_attr_init;
    pub const pthread_attr_setdetachstate = libc.pthread_attr_setdetachstate;
    pub const pthread_attr_t = libc.pthread_attr_t;
    pub const pthread_create = libc.pthread_create;
    pub const PTHREAD_CREATE_DETACHED = libc.PTHREAD_CREATE_DETACHED;
    pub const pthread_mutex_init = libc.pthread_mutex_init;
    pub const pthread_mutex_lock = libc.pthread_mutex_lock;
    pub const pthread_mutex_unlock = libc.pthread_mutex_unlock;
    pub const pthread_t = libc.pthread_t;
    pub const read = libc.read;
    pub const SEEK_END = libc.SEEK_END;
    pub const setenv = libc.setenv;
    pub const snprintf = libc.snprintf;
    pub const socketpair = libc.socketpair;
    pub const SOCK_STREAM = libc.SOCK_STREAM;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const unsetenv = libc.unsetenv;
    pub const write = libc.write;

    // shmif — event category/kind constants + shmifsrv envp struct
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_MESSAGE = shmif.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_TARGET = shmif.EVENT_TARGET;
    pub const ROLE_DIR = a12.ROLE_DIR;
    pub const ROLE_DIRREF = a12.ROLE_DIRREF;
    pub const ROLE_SINK = a12.ROLE_SINK;
    pub const ROLE_SOURCE = a12.ROLE_SOURCE;
    pub const struct_arcan_event = shmif.struct_arcan_event;
    pub const struct_arg_arr = shmif.struct_arg_arr;
    pub const struct_shmifsrv_client = shmif.struct_shmifsrv_client;
    pub const struct_shmifsrv_envp = shmif.struct_shmifsrv_envp;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_MESSAGE = shmif.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_REQFAIL = shmif.TARGET_COMMAND_REQFAIL;

    // a12 — trace mask, shmifsrv spawn, client liveness, server-appl flags,
    // a12 state machine, appl meta, public-key response
    pub const A12_TRACE_DIRECTORY = a12.A12_TRACE_DIRECTORY;
    pub const a12_trace_targets = a12.a12_trace_targets;
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const CLIENT_IDLE = a12.CLIENT_IDLE;
    pub const SERVER_APPL_NONE = a12.SERVER_APPL_NONE;
    pub const SERVER_APPL_TEMP = a12.SERVER_APPL_TEMP;
    pub const shmifsrv_spawn_client = a12.shmifsrv_spawn_client;
    pub const struct_a12_state = a12.struct_a12_state;
    pub const struct_appl_meta = a12.struct_appl_meta;
    pub const struct_pk_response = a12.struct_pk_response;

    // anet — directory-server types and link/revert/event constants
    pub const DIRLINK_REFERENCE = anet.DIRLINK_REFERENCE;
    pub const DIRLINK_RESOLVER = anet.DIRLINK_RESOLVER;
    pub const DIRLINK_UNIFIED = anet.DIRLINK_UNIFIED;
    pub const DIRLUA_EVENT_LOST = anet.DIRLUA_EVENT_LOST;
    pub const REVERT_STEP_APPL = anet.REVERT_STEP_APPL;
    pub const REVERT_STEP_CTRL = anet.REVERT_STEP_CTRL;
    pub const struct_dircl = anet.struct_dircl;
    pub const struct_dirlua_event = anet.struct_dirlua_event;
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_runner_state = anet.struct_runner_state;
};

// Module-level state (mirrors the C file-scope statics)

// arcan_db.h only forward-declares `struct arcan_dbh;` so translate-c doesn't
// emit a Zig alias.  Use anyopaque so the type can appear in extern C signatures.
const struct_arcan_dbh = anyopaque;

// struct arcan_strarr contains a union so translate-c flags it opaque.
// Mirror its layout (see src/engine/arcan_mem.h) so we can return by value.
const ArcanStrarr = extern struct {
    count: usize = 0,
    limit: usize = 0,
    data: [*c][*c]u8 = null,
};

// arcan_targetid/configid are typedef'd to `long` in arcan_db.h but that
// header isn't cImport'd here; mirror the typedef locally.
const arcan_targetid = c_long;
const arcan_configid = c_long;

// union arcan_dbtrans_id is opaque to translate-c.  Mirror the C layout:
//   union { arcan_configid cid; arcan_targetid tid; const char* applname; }
const ArcanDbtransId = extern union {
    cid: arcan_configid,
    tid: arcan_targetid,
    applname: [*c]const u8,
};

var gL: ?*lua.lua_State = null;
var gDB: ?*struct_arcan_dbh = null;
var gCFG: ?*c.struct_global_cfg = null;

// Trace helpers
// a12int_trace is a varargs macro that requires `S` in scope; we call through
// the C symbol when the trace target is active so we don't need to reproduce
// the full macro here.

extern "c" fn a12int_trace(mask: c_uint, fmt: [*c]const u8, ...) void;
extern "c" fn dirsrv_global_lock(file: [*c]const u8, line: c_int) void;
extern "c" fn dirsrv_global_unlock(file: [*c]const u8, line: c_int) void;

inline fn dirtrace_locked(fmt: [*c]const u8, arg: anytype) void {
    if (c.a12_trace_targets & c.A12_TRACE_DIRECTORY == 0) return;
    a12int_trace(c.A12_TRACE_DIRECTORY, fmt, arg);
}

// Extern declarations for functions defined in other translation units

extern "c" fn arcan_db_open(path: [*c]const u8, appl: [*c]const u8) ?*struct_arcan_dbh;
extern "c" fn arcan_db_close(dbh: *?*struct_arcan_dbh) void;
extern "c" fn arcan_db_appl_val(dbh: *struct_arcan_dbh, appl: [*c]const u8, key: [*c]const u8) [*c]u8;
extern "c" fn arcan_db_applkeys(dbh: *struct_arcan_dbh, appl: [*c]const u8, pattern: [*c]const u8) ArcanStrarr;
extern "c" fn arcan_db_begin_transaction(dbh: *struct_arcan_dbh, kind: c_int, id: ArcanDbtransId) void;
extern "c" fn arcan_db_end_transaction(dbh: *struct_arcan_dbh) void;
extern "c" fn arcan_db_add_kvpair(dbh: *struct_arcan_dbh, key: [*c]const u8, val: [*c]const u8) void;
extern "c" fn arcan_db_targetid(dbh: *struct_arcan_dbh, name: [*c]const u8, outname: [*c][*c]u8) arcan_targetid;
extern "c" fn arcan_db_configid(dbh: *struct_arcan_dbh, tid: arcan_targetid, cfg: [*c]const u8) arcan_configid;
extern "c" fn arcan_db_targetexec(dbh: *struct_arcan_dbh, cid: arcan_configid, bfmt: *c_int, argv: *ArcanStrarr, env: *ArcanStrarr, libs: *ArcanStrarr) [*c]u8;
extern "c" fn arcan_mem_freearr(arr: *ArcanStrarr) void;

extern "c" fn shmifsrv_enqueue_event(C: *c.struct_shmifsrv_client, ev: *const c.struct_arcan_event, fd: c_int) c_int;
extern "c" fn shmifsrv_free(C: *c.struct_shmifsrv_client, full: bool) void;
extern "c" fn shmifsrv_poll(C: *c.struct_shmifsrv_client) c_int;
extern "c" fn shmifsrv_dequeue_events(C: *c.struct_shmifsrv_client, ev: *c.struct_arcan_event, n: c_int) c_int;
extern "c" fn shmifsrv_client_handle(C: *c.struct_shmifsrv_client, pid: ?*c_int) c_int;
extern "c" fn shmifsrv_client_memory_handle(C: *c.struct_shmifsrv_client) c_int;
extern "c" fn shmifsrv_spawn_client(env: c.struct_shmifsrv_envp, clsock: *c_int, inherit: ?*c.struct_shmifsrv_client, n: c_int) ?*c.struct_shmifsrv_client;
extern "c" fn shmifsrv_inherit_connection(fd: c_int, sec: c_int, sc: *c_int) ?*c.struct_shmifsrv_client;
extern "c" fn shmifsrv_monotonic_rebase() void;

extern "c" fn a12helper_keystore_hostkey(tag: [*c]const u8, index: c_uint, privk: [*c]u8, host: *?[*c]u8, port: *c_ushort) bool;

extern "c" fn anet_directory_shmifsrv_thread(S: *c.struct_shmifsrv_client, state: ?*c.struct_a12_state, link_type: c_int) ?*c.struct_dircl;
extern "c" fn anet_directory_appl_runner() void;
extern "c" fn anet_directory_ephemeral_source(id: c_ushort, name: [*c]const u8, dstname: [*c]const u8, refid: usize) bool;
extern "c" fn anet_directory_dirsrv_exec_source(dst: ?*c.struct_dircl, applid: c_ushort, ident: [*c]const u8, exec: [*c]u8, argv: *ArcanStrarr, envv: *ArcanStrarr) bool;
extern "c" fn anet_directory_merge_multipart(ev: ?*c.struct_arcan_event, out: *?*c.struct_arg_arr, outchar: ?*?[*c]u8, err: *c_int) bool;
extern "c" fn anet_directory_srv_revert(slot: c_ushort, steps: c_int, dmask: c_int) bool;
// anet_directory_lua_spawn_runner and anet_directory_lua_notify_source are defined later as pub export

extern "c" fn dirsrv_find_cl_ident(appid: c_int, name: [*c]const u8, lock: bool) ?*c.struct_dircl;
extern "c" fn dirsrv_flush_report(applname: [*c]const u8) void;

extern "c" fn alt_nbio_release() void;

extern "c" fn arg_lookup(arr: [*c]c.struct_arg_arr, key: [*c]const u8, index: c_uint, out: ?*?[*c]const u8) bool;
extern "c" fn arg_unpack(msg: [*c]const u8) [*c]c.struct_arg_arr;
extern "c" fn arg_cleanup(arr: [*c]c.struct_arg_arr) void;

// asprintf is a GNU extension; declare it directly to avoid cImport macro issues.
extern "c" fn asprintf(strp: *[*c]u8, fmt: [*c]const u8, ...) c_int;

extern "c" fn extract_appl_pkg(fin: *c.FILE, dirfd: c_int, basename: [*c]const u8, msg: *?[*c]const u8, manifest: ?*?*c.struct_arg_arr) bool;

// Userdata tag for the "dircl" metatable

const ClientUserdata = extern struct {
    C: ?*c.struct_dircl,
    directory_link: bool,
    directory_reference: bool,
    directory_resolver: bool,
    client_ref: isize,
};

// StrrrepMeta: background thread writes strarr to a pipe

const StrrrepMeta = struct {
    res: ArcanStrarr,
    dst: c_int,
};

// Internal helpers

fn fdifd_event(
    cl: *c.struct_shmifsrv_client,
    base_ev: c.struct_arcan_event,
    fd: c_int,
    idstr: [*c]const u8,
    prefix: [*c]const u8,
) void {
    var ev = base_ev;
    const idlen: usize = std.fmt.parseUnsigned(usize, std.mem.sliceTo(idstr, 0), 10) catch 0;
    _ = std.fmt.bufPrintZ(
        @as([*]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))[0..ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len],
        "{s}",
        .{prefix},
    ) catch {};
    // Re-encode the idlen into the prefix format string via libc snprintf
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        prefix,
        idlen,
    );
    _ = shmifsrv_enqueue_event(cl, &ev, fd);
}

fn deallocRunner(runner: *c.struct_runner_state) void {
    if (runner.store_dfd > 0) {
        _ = c.close(runner.store_dfd);
    }
    c.free(runner);
}

fn runDetachedThread(ptr: *const fn (?*anyopaque) callconv(.c) ?*anyopaque, arg: ?*anyopaque) void {
    var pth: c.pthread_t = undefined;
    var pthattr: c.pthread_attr_t = undefined;
    _ = c.pthread_attr_init(&pthattr);
    _ = c.pthread_attr_setdetachstate(&pthattr, c.PTHREAD_CREATE_DETACHED);
    _ = c.pthread_create(&pth, &pthattr, ptr, arg);
}

fn sendRunnerAppl(runner: *c.struct_runner_state) void {
    var outev = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;

    if (runner.appl == null) return;
    const appl: *c.struct_appl_meta = @ptrCast(runner.appl);
    const cfg = gCFG orelse return;

    const srcdir: c_int = if (appl.server_appl == c.SERVER_APPL_TEMP)
        cfg.dirsrv.appl_server_temp_dfd
    else
        cfg.dirsrv.appl_server_dfd;

    const dfd = c.openat(srcdir, @as([*c]const u8, @ptrCast(&appl.appl.name)), c.O_RDONLY | c.O_DIRECTORY);
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&outev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        "%s",
        @as([*c]const u8, @ptrCast(&appl.appl.name)),
    );
    _ = shmifsrv_enqueue_event(runner.cl.?, &outev, dfd);
}

// strarr_copy thread: writes null-terminated strings to pipe

fn strarr_copy_thread(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const M: *StrrrepMeta = @ptrCast(@alignCast(arg.?));
    const fout = c.fdopen(M.dst, "w");
    if (fout == null) {
        arcan_mem_freearr(&M.res);
        c.free(M);
        return null;
    }
    var curr = M.res.data;
    while (curr.* != null and c.ferror(fout.?) == 0) {
        _ = c.fputs(curr.*, fout.?);
        _ = c.fputc(0, fout.?);
        curr += 1;
    }
    _ = c.fclose(fout.?);
    arcan_mem_freearr(&M.res);
    c.free(M);
    return null;
}

// process_file_request

fn processFileRequest(runner: *c.struct_runner_state, ev: *c.struct_arcan_event) void {
    if (runner.resolver != null) {
        var ppair: [2]c_int = undefined;
        _ = c.pipe(&ppair);

        var resev = c.struct_arcan_event.zeroes();
        resev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        resev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier);
        resev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns);
        resev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[5].iv = if (runner.appl != null) runner.appl.?.identifier else 0;
        _ = c.snprintf(
            @as([*c]u8, @ptrCast(&resev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
            resev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
            "%s",
            @as([*c]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions)),
        );

        if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input != 0) {
            resev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
            _ = shmifsrv_enqueue_event(runner.resolver.?.C.?, &resev, ppair[1]);
            resev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
            _ = shmifsrv_enqueue_event(runner.cl.?, &resev, ppair[0]);
        } else {
            resev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
            _ = shmifsrv_enqueue_event(runner.resolver.?.C.?, &resev, ppair[0]);
            resev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
            _ = shmifsrv_enqueue_event(runner.cl.?, &resev, ppair[1]);
        }

        _ = c.close(ppair[0]);
        _ = c.close(ppair[1]);
        return;
    }

    if (runner.store_dfd == -1) return sendReqfail(runner, ev);

    // Only alnum permitted (and '.' for extension, not as first char)
    const ext = @as([*c]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions));
    var i: usize = 0;
    while (i < ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len and ext[i] != 0) : (i += 1) {
        if (c.isalnum(ext[i]) == 0 and !(i > 0 and ext[i] == '.')) {
            return sendReqfail(runner, ev);
        }
    }
    if (i == ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len) return sendReqfail(runner, ev);

    const input = ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input != 0;
    const fd = if (input)
        c.openat(runner.store_dfd, ext, c.O_RDONLY | c.O_CLOEXEC)
    else
        c.openat(runner.store_dfd, ext, c.O_RDWR | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o600));
    if (fd == -1) return sendReqfail(runner, ev);

    var reply = c.struct_arcan_event.zeroes();
    reply.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    reply.unnamed_0.unnamed_0.unnamed_0.tgt.kind = if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input != 0) c.TARGET_COMMAND_BCHUNK_IN else c.TARGET_COMMAND_BCHUNK_OUT;
    reply.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier);
    reply.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns);
    _ = shmifsrv_enqueue_event(runner.cl.?, &reply, fd);
    _ = c.close(fd);
    return;
}

fn sendReqfail(runner: *c.struct_runner_state, ev: *c.struct_arcan_event) void {
    var fail_ev = c.struct_arcan_event.zeroes();
    fail_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_REQFAIL;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier);
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns);
    _ = shmifsrv_enqueue_event(runner.cl.?, &fail_ev, -1);
}

// handle_sink_client / handle_source_client

fn handleSinkClient(name: [*c]const u8, runner: *c.struct_runner_state, arr: *c.struct_arg_arr) void {
    var dst_raw: ?[*c]const u8 = null;
    if (!arg_lookup(arr, "dst", 0, &dst_raw)) return;
    const dst = dst_raw orelse return;

    dirsrv_global_lock("dir_lua.zig", @src().line);
    const appl_id: c_int = if (runner.appl != null) runner.appl.?.identifier else 0;
    const dst_cl = dirsrv_find_cl_ident(appl_id, dst, true);
    const src_cl = dirsrv_find_cl_ident(appl_id, name, true);

    if (dst_cl == null or src_cl == null) {
        dirsrv_global_unlock("dir_lua.zig", @src().line);
        return;
    }

    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_NETSTATE;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.state = 2;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type = c.ROLE_SOURCE;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.ns = @intCast(appl_id);

    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)),
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name.len,
        "%s",
        name,
    );
    const nl = c.strlen(@as([*c]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)));
    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name.len - nl < 33) {
        dirsrv_global_unlock("dir_lua.zig", @src().line);
        return;
    }
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl] = ':';
    @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name[nl + 1 ..][0..32], src_cl.?.pubk[0..32]);

    _ = shmifsrv_enqueue_event(dst_cl.?.C.?, &ev, -1);
    dirsrv_global_unlock("dir_lua.zig", @src().line);
}

fn handleSourceClient(name: [*c]const u8, runner: *c.struct_runner_state, arr: *c.struct_arg_arr) void {
    var idstr_raw: ?[*c]const u8 = null;
    if (!arg_lookup(arr, "id", 0, &idstr_raw)) return;
    const idstr = idstr_raw orelse return;

    const id = std.fmt.parseUnsigned(usize, std.mem.sliceTo(idstr, 0), 10) catch 0;
    if (id == 0) return;

    var dst_raw: ?[*c]const u8 = null;
    if (runner.appl == null) return;
    const appl: *c.struct_appl_meta = @ptrCast(runner.appl);
    if (!(arg_lookup(arr, "dst", 0, &dst_raw) and dst_raw != null) or
        dirsrv_find_cl_ident(appl.identifier, dst_raw.?, false) == null)
    {
        anet_directory_lua_notify_source(appl, dst_raw orelse "", "fail", id);
        return;
    }

    if (anet_directory_ephemeral_source(appl.identifier, name, dst_raw.?, id)) {
        anet_directory_lua_notify_source(appl, dst_raw.?, "ok", id);
    } else {
        anet_directory_lua_notify_source(appl, dst_raw.?, "fail", id);
    }
}

// launchtarget (internal helper)

fn launchtarget(
    runner: *c.struct_runner_state,
    db: *struct_arcan_dbh,
    tgt: [*c]const u8,
    ident: [*c]const u8,
    id: c_int,
    dircl: ?*c.struct_dircl,
) void {
    _ = ident;
    var argv_arr = std.mem.zeroes(ArcanStrarr);
    var env_arr = std.mem.zeroes(ArcanStrarr);
    var libs_arr = std.mem.zeroes(ArcanStrarr);
    var bfmt: c_int = undefined;

    const cid = arcan_db_configid(db, arcan_db_targetid(db, tgt, null), "default");
    const exec = arcan_db_targetexec(db, cid, &bfmt, &argv_arr, &env_arr, &libs_arr);
    if (exec == null) return;

    const appl_ident: c_ushort = if (runner.appl != null) @intCast(runner.appl.?.identifier) else 0;
    const appl_name: [*c]const u8 = if (runner.appl != null) @as([*c]const u8, @ptrCast(&runner.appl.?.appl.name)) else "?";
    _ = anet_directory_dirsrv_exec_source(dircl, appl_ident, appl_name, exec, &argv_arr, &env_arr);

    c.free(exec);
    arcan_mem_freearr(&argv_arr);
    arcan_mem_freearr(&libs_arr);
    arcan_mem_freearr(&env_arr);
    _ = id;
}

// controllerDispatch

fn controllerDispatch(runner: *c.struct_runner_state, arr: *c.struct_arg_arr, db: *struct_arcan_dbh) void {
    if (runner.appl == null) {
        arg_cleanup(arr);
        return;
    }
    const appl: *c.struct_appl_meta = @ptrCast(runner.appl);

    var dbid = std.mem.zeroes(ArcanDbtransId);
    dbid.applname = @as([*c]const u8, @ptrCast(&appl.appl.name));

    var arg_raw: ?[*c]const u8 = null;
    var val_raw: ?[*c]const u8 = null;

    if (arg_lookup(arr, "begin_kv_transaction", 0, null)) {
        arcan_db_begin_transaction(db, 0, dbid);
    } else if (arg_lookup(arr, "setkey", 0, &arg_raw) and arg_raw != null and
        arg_lookup(arr, "value", 0, &val_raw) and val_raw != null)
    {
        arcan_db_add_kvpair(db, arg_raw.?, val_raw.?);
    } else if (arg_lookup(arr, "end_kv_transaction", 0, null)) {
        arcan_db_end_transaction(db);
    } else if (arg_lookup(arr, "report_collect", 0, null)) {
        // no-op
    } else if (arg_lookup(arr, "source_client", 0, &arg_raw) and arg_raw != null) {
        handleSourceClient(arg_raw.?, runner, arr);
    } else if (arg_lookup(arr, "sink_client", 0, &arg_raw) and arg_raw != null) {
        handleSinkClient(arg_raw.?, runner, arr);
    } else if (arg_lookup(arr, "launch", 0, &arg_raw) and arg_raw != null and
        arg_lookup(arr, "id", 0, &val_raw) and val_raw != null)
    {
        const id = std.fmt.parseInt(c_int, std.mem.sliceTo(val_raw.?, 0), 10) catch 0;
        var dst_raw: ?[*c]const u8 = null;
        var dst_cl: ?*c.struct_dircl = null;
        if (arg_lookup(arr, "dst", 0, &dst_raw) and dst_raw != null) {
            dst_cl = dirsrv_find_cl_ident(appl.identifier, dst_raw.?, false);
            if (dst_cl == null) {
                arg_cleanup(arr);
                return;
            }
        }
        launchtarget(runner, db, arg_raw.?, "testsource", id, dst_cl);
    } else if (arg_lookup(arr, "reload", 0, null)) {
        sendRunnerAppl(runner);
    } else if (arg_lookup(arr, "match", 0, &arg_raw) and arg_raw != null and
        arg_lookup(arr, "domain", 0, null) and
        arg_lookup(arr, "id", 0, &val_raw) and val_raw != null)
    {
        const res = arcan_db_applkeys(db, @as([*c]const u8, @ptrCast(&appl.appl.name)), arg_raw.?);
        if (res.count > 0) {
            var ppair: [2]c_int = undefined;
            if (c.pipe(&ppair) == -1) {
                var fail_ev = c.struct_arcan_event.zeroes();
                fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
                fdifd_event(runner.cl.?, fail_ev, -1, val_raw.?, "fail:id=%zu");
                var res_copy = res;
                arcan_mem_freearr(&res_copy);
            } else {
                var reply_ev = c.struct_arcan_event.zeroes();
                reply_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
                reply_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
                fdifd_event(runner.cl.?, reply_ev, ppair[0], val_raw.?, ".reply=%zu");

                const M: *StrrrepMeta = @ptrCast(@alignCast(c.malloc(@sizeOf(StrrrepMeta)).?));
                M.res = res;
                M.dst = ppair[1];
                _ = c.close(ppair[0]);
                runDetachedThread(strarr_copy_thread, M);
            }
        } else {
            var ok_ev = c.struct_arcan_event.zeroes();
            ok_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
            fdifd_event(runner.cl.?, ok_ev, -1, val_raw.?, "ok:id=%zu");
            var res_copy = res;
            arcan_mem_freearr(&res_copy);
        }
    }

    arg_cleanup(arr);
}

// controller_runner thread

fn controller_runner_thread(inarg: ?*anyopaque) callconv(.c) ?*anyopaque {
    const runner: *c.struct_runner_state = @ptrCast(@alignCast(inarg.?));

    _ = c.pthread_mutex_lock(&runner.lock);
    runner.alive = true;

    const cfg = gCFG.?;
    const tl_db = arcan_db_open(cfg.db_file, @as([*c]const u8, @ptrCast(&runner.appl.?.appl.name)));

    // Wait for shmif setup
    var pv: c_int = shmifsrv_poll(runner.cl.?);
    while (pv != c.CLIENT_DEAD) {
        if (pv == c.CLIENT_IDLE) break;
        pv = shmifsrv_poll(runner.cl.?);
    }

    if (pv == c.CLIENT_DEAD) {
        shmifsrv_free(runner.cl.?, false);
        runner.alive = false;
        _ = c.pthread_mutex_unlock(&runner.lock);
        return null;
    }

    // Open appl log if path configured
    if (cfg.dirsrv.appl_logpath != null) {
        var msg_buf: [256]u8 = undefined;
        const log_name = std.fmt.bufPrintZ(&msg_buf, "{s}.log", .{std.mem.sliceTo(@as([*c]const u8, @ptrCast(&runner.appl.?.appl.name)), 0)}) catch null;
        if (log_name) |ln| {
            const log_fd = c.openat(cfg.dirsrv.appl_logdfd, ln.ptr, c.O_RDWR | c.O_CREAT, @as(c_uint, 0o700));
            if (log_fd != -1) {
                _ = c.lseek(log_fd, 0, c.SEEK_END);
                var log_ev = c.struct_arcan_event.zeroes();
                log_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
                log_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
                _ = c.memcpy(@as(*anyopaque, @ptrCast(&log_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)), ".log", 5);
                _ = shmifsrv_enqueue_event(runner.cl.?, &log_ev, log_fd);
                _ = c.close(log_fd);
            }
        }
    }

    sendRunnerAppl(runner);
    @atomicStore(bool, &runner.appl_sent, true, .seq_cst);
    shmifsrv_monotonic_rebase();
    _ = c.pthread_mutex_unlock(&runner.lock);

    var sv: c_int = shmifsrv_poll(runner.cl.?);
    while (sv != c.CLIENT_DEAD) {
        const pfd = c.struct_pollfd{
            .fd = shmifsrv_client_handle(runner.cl.?, null),
            .events = c.POLLIN | c.POLLERR | c.POLLHUP,
            .revents = 0,
        };
        var ev = c.struct_arcan_event.zeroes();
        while (shmifsrv_dequeue_events(runner.cl.?, &ev, 1) == 1) {
            if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_MESSAGE) {
                var out_arr: ?*c.struct_arg_arr = null;
                var err: c_int = 0;
                if (!anet_directory_merge_multipart(&ev, &out_arr, null, &err)) {
                    continue;
                }
                if (out_arr) |arr| {
                    if (tl_db) |db| {
                        controllerDispatch(runner, arr, db);
                    }
                }
            } else if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_BCHUNKSTATE) {
                processFileRequest(runner, &ev);
            }
        }

        var pfd_copy = pfd;
        const rv = c.poll(@as([*]c.struct_pollfd, @ptrCast(&pfd_copy)), 1, -1);
        if (rv & (c.POLLERR | c.POLLHUP) != 0) break;
        if (rv & c.POLLIN != 0) {
            var buf: [256]u8 = undefined;
            _ = c.read(pfd_copy.fd, &buf, 256);
        }
        sv = shmifsrv_poll(runner.cl.?);
    }

    runner.alive = false;
    _ = c.pthread_mutex_lock(&runner.lock);
    runner.appl.?.server_tag = null;
    _ = c.pthread_mutex_unlock(&runner.lock);

    if (tl_db != null) {
        var db_mut: ?*struct_arcan_dbh = tl_db;
        arcan_db_close(&db_mut);
    }
    // Flush TLS-state for the multipart merger on thread exit
    var cleanup_arr: ?*c.struct_arg_arr = null;
    var cleanup_err: c_int = 0;
    _ = anet_directory_merge_multipart(null, &cleanup_arr, null, &cleanup_err);
    deallocRunner(runner);
    return null;
}

// find_appl_by_name

fn findApplByName(name: [*c]const u8) ?*c.struct_appl_meta {
    const cfg = gCFG orelse return null;
    var res: ?*c.struct_appl_meta = &cfg.dirsrv.dir;
    while (res) |r| {
        if (c.strcmp(name, @as([*c]const u8, @ptrCast(&r.appl.name))) == 0) return r;
        res = r.next;
    }
    return null;
}

// push_dircl: retrieve the Lua userdata for a client

fn pushDircl(L: *lua.lua_State, C: *c.struct_dircl) void {
    const ud: *ClientUserdata = @ptrCast(@alignCast(C.userdata.?));
    _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, @intCast(ud.client_ref));
    if (lua.lua_type(L, -1) != lua.LUA_TUSERDATA) {
        _ = lua.luaL_error(L, "invalid reference in client\n");
    }
}

// ctrl_dirfd

fn ctrlDirfd(appl: *c.struct_appl_meta) c_int {
    const cfg = gCFG orelse return -1;
    if (cfg.dirsrv.appl_server_datadfd == -1) return -1;
    return c.openat(
        cfg.dirsrv.appl_server_datadfd,
        @as([*c]const u8, @ptrCast(&appl.appl.name)),
        c.O_RDONLY | c.O_DIRECTORY,
    );
}

// validate_key

fn validateKey(key: [*c]const u8) bool {
    var i: usize = 0;
    while (key[i] != 0) : (i += 1) {
        const ch = key[i];
        if (c.isalnum(ch) == 0 and ch != '_' and ch != '+' and ch != '/' and ch != '=')
            return false;
    }
    return true;
}

// ═══════════════════════════════════════════════════════════════
// Exported Lua C functions
// ═══════════════════════════════════════════════════════════════

/// db_get_key(key) → string|nil
/// Not exported; used internally via set_client_config_mode
fn db_get_key(L: *lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 1, null);
    const db = gDB orelse {
        lua.lua_pushnil(L);
        return 1;
    };
    const val = arcan_db_appl_val(db, "a12", key);
    if (val) |v| {
        _ = lua.lua_pushstring(L, v);
    } else {
        lua.lua_pushnil(L);
    }
    return 1;
}

/// dir_write(client, msg) → bool
pub export fn dir_write(L: *lua.lua_State) c_int {
    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "dircl")));
    const cl = ud.C orelse {
        _ = lua.luaL_error(L, ":write(ud) not bound to a client");
        return 0;
    };
    const msg_z = lua.luaL_checklstring(L, 2, null);
    if (cl.admin_fdout <= 0) {
        _ = lua.luaL_error(L, ":write(ud) client does not have a write channel");
        return 0;
    }

    var ntw: usize = c.strlen(msg_z) + 1;
    var msg = msg_z;
    while (ntw > 0) {
        const nw = c.write(cl.admin_fdout, msg, ntw);
        if (nw == -1) {
            const en = std.c._errno().*;
            if (en != c.EINTR and en != c.EAGAIN) break;
            continue;
        }
        msg += @intCast(nw);
        ntw -= @intCast(nw);
    }

    lua.lua_pushboolean(L, @intFromBool(ntw == 0));
    return 1;
}

/// dir_endpoint(client) → string
pub export fn dir_endpoint(L: *lua.lua_State) c_int {
    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.luaL_checkudata(L, 1, "dircl")));
    const cl = ud.C orelse {
        _ = lua.luaL_error(L, ":endpoint(ud) not bound to a client");
        return 0;
    };
    _ = lua.lua_pushstring(L, @as([*c]const u8, @ptrCast(&cl.endpoint.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)));
    return 1;
}

/// dir_matchkeys(pattern) → table
pub export fn dir_matchkeys(L: *lua.lua_State) c_int {
    const pattern = lua.luaL_checklstring(L, 1, null);
    const db = gDB orelse {
        lua.lua_newtable(L);
        return 1;
    };
    const res = arcan_db_applkeys(db, "directory", pattern);

    lua.lua_newtable(L);
    if (res.data != null) {
        var curr = res.data;
        var count: usize = 1;
        while (curr.* != null) {
            lua.lua_pushnumber(L, @floatFromInt(count));
            _ = lua.lua_pushstring(L, curr.*);
            lua.lua_rawset(L, -3);
            count += 1;
            curr += 1;
        }
        var res_copy = res;
        arcan_mem_freearr(&res_copy);
    }
    return 1;
}

/// dir_storekey(key, value) or dir_storekey(table)
pub export fn dir_storekey(L: *lua.lua_State) c_int {
    const db = gDB orelse return 0;
    var dbid = std.mem.zeroes(ArcanDbtransId);
    dbid.applname = "directory";
    arcan_db_begin_transaction(db, 0, dbid);

    if (lua.lua_type(L, 1) == lua.LUA_TTABLE) {
        lua.lua_pushnil(L);
        while (lua.lua_next(L, 1) != 0) {
            const key = lua.lua_tolstring(L, -2, null);
            if (!validateKey(key)) {
                _ = lua.luaL_error(L, "store_keys(>tbl<, %s - invalid key (alphanum, no +/_=", key);
                return 0;
            }
            const val = lua.lua_tolstring(L, -1, null);
            arcan_db_add_kvpair(db, key, val);
            lua.lua_pop(L, 1);
        }
        arcan_db_end_transaction(db);
        return 0;
    }

    const key = lua.luaL_checklstring(L, 1, null);
    const value = lua.luaL_checklstring(L, 2, null);
    arcan_db_add_kvpair(db, key, value);
    arcan_db_end_transaction(db);
    return 0;
}

/// dir_getkey(key) → string|nil
pub export fn dir_getkey(L: *lua.lua_State) c_int {
    const db = gDB orelse {
        lua.lua_pushnil(L);
        return 1;
    };
    const val = arcan_db_appl_val(db, "directory", lua.luaL_checklstring(L, 1, null));
    if (val) |v| {
        _ = lua.lua_pushstring(L, v);
        c.free(v);
    } else {
        lua.lua_pushnil(L);
    }
    return 1;
}

/// dir_flushreport(applname)
pub export fn dir_flushreport(L: *lua.lua_State) c_int {
    dirsrv_flush_report(lua.luaL_checklstring(L, 1, null));
    return 0;
}

/// dir_appllist() → table
pub export fn dir_appllist(L: *lua.lua_State) c_int {
    const cfg = gCFG orelse {
        lua.lua_newtable(L);
        return 1;
    };
    lua.lua_newtable(L);
    var M: ?*c.struct_appl_meta = &cfg.dirsrv.dir;
    while (M) |m| {
        _ = lua.lua_pushstring(L, "id");
        lua.lua_pushnumber(L, @floatFromInt(m.identifier));
        lua.lua_rawset(L, -3);

        _ = lua.lua_pushstring(L, "name");
        _ = lua.lua_pushstring(L, @as([*c]const u8, @ptrCast(&m.appl.name)));
        lua.lua_rawset(L, -3);

        _ = lua.lua_pushstring(L, "timestamp");
        lua.lua_pushnumber(L, @floatFromInt(m.update_ts));
        lua.lua_rawset(L, -3);

        _ = lua.lua_pushstring(L, "runner_active");
        lua.lua_pushboolean(L, @intFromBool(m.server_tag != null));
        lua.lua_rawset(L, -3);

        M = m.next;
    }
    return 1;
}

/// dir_applrevert(name [, steps]) → bool [, string]
pub export fn dir_applrevert(L: *lua.lua_State) c_int {
    const name = lua.luaL_checklstring(L, 1, null);
    const M = findApplByName(name) orelse {
        lua.lua_pushboolean(L, 0);
        _ = lua.lua_pushstring(L, "no matching appl slot");
        return 2;
    };
    const steps: c_int = @intFromFloat(lua.luaL_optnumber(L, 2, -1.0));

    dirsrv_global_unlock("dir_lua.zig", @src().line);
    lua.lua_pushboolean(L, @intFromBool(anet_directory_srv_revert(M.identifier, steps, c.REVERT_STEP_APPL)));
    dirsrv_global_lock("dir_lua.zig", @src().line);
    return 1;
}

/// dir_ctrlrevert(name [, steps]) → bool [, string]
pub export fn dir_ctrlrevert(L: *lua.lua_State) c_int {
    const name = lua.luaL_checklstring(L, 1, null);
    const M = findApplByName(name) orelse {
        lua.lua_pushboolean(L, 0);
        _ = lua.lua_pushstring(L, "no matching appl slot");
        return 1;
    };
    const steps: c_int = @intFromFloat(lua.luaL_optnumber(L, 2, -1.0));

    dirsrv_global_unlock("dir_lua.zig", @src().line);
    lua.lua_pushboolean(L, @intFromBool(anet_directory_srv_revert(M.identifier, steps, c.REVERT_STEP_CTRL)));
    dirsrv_global_lock("dir_lua.zig", @src().line);
    return 1;
}

/// dir_messagealias(name, aliasname)
pub export fn dir_messagealias(L: *lua.lua_State) c_int {
    const name = lua.luaL_checklstring(L, 1, null);
    const aliasname = lua.luaL_checklstring(L, 2, null);
    const cfg = gCFG orelse return 0;

    var M: ?*c.struct_appl_meta = &cfg.dirsrv.dir;
    var source: ?*c.struct_appl_meta = null;
    var alias: ?*c.struct_appl_meta = null;

    while (M != null and (source == null or alias == null)) {
        if (c.strcmp(name, @as([*c]const u8, @ptrCast(&M.?.appl.name))) == 0) source = M;
        if (c.strcmp(aliasname, @as([*c]const u8, @ptrCast(&M.?.appl.name))) == 0) alias = M;
        M = M.?.next;
    }

    const src = source orelse {
        _ = lua.luaL_error(L, "alias: source-appl not found");
        return 0;
    };

    if (alias == null or src == alias.?) {
        src.alias_identifier = 0;
    } else {
        src.alias_identifier = if (alias.?.alias_identifier != 0)
            alias.?.alias_identifier
        else
            alias.?.identifier;
    }
    return 0;
}

/// dir_applresolver(applname, resolver_userdata)
pub export fn dir_applresolver(L: *lua.lua_State) c_int {
    const name = lua.luaL_checklstring(L, 1, null);
    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.luaL_checkudata(L, 2, "dircl")));

    if (!ud.directory_resolver) {
        _ = lua.luaL_error(L, "appl_set_resolver(applname, >resolver<) invalid resolver");
        return 0;
    }

    const source = findApplByName(name) orelse {
        _ = lua.luaL_error(L, "resolver: destination appl not found");
        return 0;
    };

    const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(source.server_tag));
    const r = runner orelse {
        _ = lua.luaL_error(L, "appl_set_resolver(>applname<) appl doesn't have a controller");
        return 0;
    };

    r.resolver = ud.C;
    return 0;
}

/// dir_launchtarget(name, options_table)
pub export fn dir_launchtarget(L: *lua.lua_State) c_int {
    const name = lua.luaL_checklstring(L, 1, null);
    if (lua.lua_type(L, 2) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "launch_target(name, >option table<, ...) no table provided");
        return 0;
    }

    var appl = std.mem.zeroes(c.struct_appl_meta);
    var runner = c.struct_runner_state{ .appl = &appl, .store_dfd = -1 };
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&appl.appl.name)),
        appl.appl.name.len,
        "%s",
        name,
    );

    const db = gDB orelse return 0;
    launchtarget(&runner, db, name, "_config", 0, null);
    return 0;
}

/// dir_hookresource(resname, nsid, tag, bin, ...argv) → nil
/// Register an external process handler for a '.' prefixed resource in a given
/// namespace.  Stored in registry["resource_hooks"][ns:resname] = {tag, bin, argv}.
pub export fn dir_hookresource(L: *lua.lua_State) c_int {
    const resname = lua.luaL_checklstring(L, 1, null);
    const nargs = lua.lua_gettop(L);

    if (resname[0] != '.') {
        _ = lua.luaL_error(L,
            "hook_resource(>name<, ...) only names with a . prefix are allowed");
        return 0;
    }

    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "resource_hooks");

    // Create on first use.
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        lua.lua_newtable(L);
        _ = lua.lua_pushstring(L, "resource_hooks");
        lua.lua_pushvalue(L, -2);
        lua.lua_rawset(L, lua.LUA_REGISTRYINDEX);
    }

    // Resolve the nsid argument: 0 / known identifier / appl name.
    const cfg = gCFG orelse {
        _ = lua.luaL_error(L, "hook_resource: global cfg not initialised");
        return 0;
    };
    var M: ?*c.struct_appl_meta = &cfg.dirsrv.dir;
    var ns: usize = 0;

    if (lua.lua_type(L, 2) == lua.LUA_TSTRING) {
        const name = lua.lua_tolstring(L, 2, null);
        var found = false;
        while (M) |m| {
            if (c.strcmp(@as([*c]const u8, @ptrCast(&m.appl.name)), name) == 0) {
                found = true;
                ns = @intCast(m.identifier);
                break;
            }
            M = m.next;
        }
        if (!found) {
            _ = lua.luaL_error(L,
                "hook_resource(name, >string:nsid<, ...) identifier not found");
            return 0;
        }
    } else if (lua.lua_type(L, 2) == lua.LUA_TNUMBER) {
        const num = lua.lua_tonumber(L, 2);
        if (num == 0) {
            // don't need to do anything
        } else {
            const num_u: usize = @intFromFloat(num);
            while (M) |m| {
                if (@as(usize, m.identifier) == num_u) {
                    ns = num_u;
                    break;
                }
                M = m.next;
            }
            if (ns != num_u) {
                _ = lua.luaL_error(L,
                    "hook_resource(name, >number:nsid<, ...) identifier not found");
                return 0;
            }
        }
    } else {
        _ = lua.luaL_error(L,
            "hook_resource(name, >nsid<, ...) expected STRING or NUMBER");
        return 0;
    }

    // Build the composite key "<ns>:<resname>".
    var key_ptr: [*c]u8 = null;
    if (asprintf(&key_ptr, "%zu:%s", ns, resname) <= 0) {
        lua.lua_pop(L, 1);
        return 0;
    }
    defer c.free(key_ptr);

    _ = lua.lua_pushstring(L, key_ptr);
    lua.lua_newtable(L);

    _ = lua.lua_pushstring(L, "tag");
    _ = lua.lua_pushstring(L, lua.luaL_checklstring(L, 3, null));
    lua.lua_rawset(L, -3); // {tag = arg[3]}

    _ = lua.lua_pushstring(L, "bin");
    _ = lua.lua_pushstring(L, lua.luaL_checklstring(L, 4, null));
    lua.lua_rawset(L, -3); // {bin = arg[4]}

    // Convert rest of [nargs] into n-indexed table stored as argv.
    _ = lua.lua_pushstring(L, "argv");
    lua.lua_newtable(L);
    var i: c_int = 5;
    while (i <= nargs) : (i += 1) {
        lua.lua_pushnumber(L, @as(lua.lua_Number, @floatFromInt(i - 4)));
        _ = lua.lua_pushstring(L, lua.luaL_checklstring(L, i, null));
        lua.lua_rawset(L, -3);
    }
    lua.lua_rawset(L, -3); // {argv = {...}}
    lua.lua_rawset(L, -3); // registry["resource_hooks"][key] = table
    lua.lua_pop(L, 1);

    return 0;
}

/// dir_launchresolver(executable [, ...args], callback) → userdata
pub export fn dir_launchresolver(L: *lua.lua_State) c_int {
    const nargs = lua.lua_gettop(L);
    if (nargs == 0) {
        _ = lua.luaL_error(L, "launch_resolver(...) missing executable argument");
        return 0;
    }
    if (lua.lua_type(L, nargs) != lua.LUA_TFUNCTION) {
        _ = lua.luaL_error(L, "launch_resolver(..., >callback<) missing callback");
        return 0;
    }

    lua.lua_pushvalue(L, nargs);
    const ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    const argc = nargs - 1;

    // Build argv on the heap (luaL_checkstring returns C-side strings; copy is safe
    // for the duration of this function)
    const argv: [*c][*c]u8 = @ptrCast(@alignCast(c.malloc(@sizeOf([*c]u8) * @as(usize, @intCast(argc + 2)))));
    argv[0] = c.strdup(lua.luaL_checklstring(L, 1, null));
    var i: c_int = 1;
    while (i <= argc) : (i += 1) {
        argv[@intCast(i)] = c.strdup(lua.luaL_checklstring(L, i, null));
    }
    argv[@intCast(argc + 1)] = null;

    const env = c.struct_shmifsrv_envp{
        .init_w = 32,
        .init_h = 32,
        .path = argv[0],
        .envv = null,
        .argv = @ptrCast(argv),
        .detach = 0,
    };

    var cs: c_int = 0;
    const S = c.shmifsrv_spawn_client(env, &cs, null, 0);
    dirsrv_global_unlock("dir_lua.zig", @src().line);
    const cl = anet_directory_shmifsrv_thread(S.?, null, c.DIRLINK_RESOLVER);
    dirsrv_global_lock("dir_lua.zig", @src().line);

    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.lua_newuserdata(L, @sizeOf(ClientUserdata))));
    ud.* = .{ .C = cl, .directory_link = false, .directory_reference = false, .directory_resolver = true, .client_ref = 0 };
    cl.?.lua_cb = ref;
    cl.?.userdata = ud;

    _ = lua.luaL_getmetatable(L, "dircl");
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_pushvalue(L, -1);
    ud.client_ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    i = 0;
    while (i <= argc) : (i += 1) {
        c.free(argv[@intCast(i)]);
    }
    c.free(@as(?*anyopaque, @ptrCast(argv)));

    return 1;
}

// spawn_dirwork: common helper for link/ref directory

fn spawnDirwork(
    L: *lua.lua_State,
    argi: c_int,
    tag: [*c]u8,
    argv: [*c][*c]u8,
    pref: [*c]const u8,
    unified: bool,
) c_int {
    var private: [32]u8 = undefined;
    var tmp: ?[*c]u8 = null;
    var tmpport: c_ushort = 0;

    if (!a12helper_keystore_hostkey(tag, 0, &private, &tmp, &tmpport)) {
        _ = lua.luaL_error(L, "%s: >tag=%s< not found in keystore", pref, tag);
        return 0;
    }

    if (lua.lua_type(L, argi) != lua.LUA_TFUNCTION) {
        _ = lua.luaL_error(L, "%s: tag, >callback< missing", pref);
        return 0;
    }

    lua.lua_pushvalue(L, argi);
    const ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    const cfg = gCFG.?;

    const env = c.struct_shmifsrv_envp{
        .init_w = 32,
        .init_h = 32,
        .path = cfg.path_self,
        .envv = null,
        .argv = @ptrCast(argv),
        .detach = 2 | 4 | 8,
    };

    var clsock: c_int = 0;
    const S = c.shmifsrv_spawn_client(env, &clsock, null, 0);
    c.free(tag);

    if (S == null) {
        lua.luaL_unref(L, lua.LUA_REGISTRYINDEX, ref);
        return 0;
    }

    dirsrv_global_unlock("dir_lua.zig", @src().line);
    const cl = anet_directory_shmifsrv_thread(
        S.?,
        null,
        if (unified) c.DIRLINK_UNIFIED else c.DIRLINK_REFERENCE,
    );
    dirsrv_global_lock("dir_lua.zig", @src().line);

    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.lua_newuserdata(L, @sizeOf(ClientUserdata))));
    ud.* = .{
        .C = cl,
        .directory_link = unified,
        .directory_reference = !unified,
        .directory_resolver = false,
        .client_ref = 0,
    };
    cl.?.lua_cb = ref;
    cl.?.userdata = ud;

    lua.lua_pushvalue(L, -1);
    ud.client_ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    _ = lua.luaL_getmetatable(L, "dircl");
    _ = lua.lua_setmetatable(L, -2);

    return 1;
}

/// dir_refdirectory(tag, ident, callback) → userdata
pub export fn dir_refdirectory(L: *lua.lua_State) c_int {
    const tag = c.strdup(lua.luaL_checklstring(L, 1, null));
    const ident = c.strdup(lua.luaL_checklstring(L, 2, null));
    const cfg = gCFG.?;

    var argv: [5][*c]u8 = .{ cfg.path_self, c.strdup("dirref"), ident, tag, null };
    const rv = spawnDirwork(L, 3, tag, &argv, "reference_directory", false);
    c.free(ident);
    return rv;
}

/// dir_linkdirectory(tag, callback) → userdata
pub export fn dir_linkdirectory(L: *lua.lua_State) c_int {
    const tag = c.strdup(lua.luaL_checklstring(L, 1, null));
    const cfg = gCFG.?;

    var argv: [5][*c]u8 = .{ cfg.path_self, c.strdup("dirlink"), c.strdup("dirlink"), tag, null };
    return spawnDirwork(L, 2, tag, &argv, "link_directory", true);
}

// ═══════════════════════════════════════════════════════════════
// Non-Lua exported functions (called from C)
// ═══════════════════════════════════════════════════════════════

pub export fn anet_directory_lua_exit() void {
    if (gL) |L| {
        lua.lua_close(L);
        alt_nbio_release();
        gL = null;
    }
}

pub export fn anet_directory_lua_event(C: *c.struct_dircl, ev: *c.struct_dirlua_event) void {
    const L = gL orelse return;
    if (C.lua_cb == lua.LUA_NOREF) return;

    _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, @intCast(C.lua_cb));
    if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
        _ = lua.luaL_error(L, "client-to-lua: reference is not a function");
        lua.lua_pop(L, 1);
        return;
    }

    if (ev.kind == c.DIRLUA_EVENT_LOST) {
        pushDircl(L, C);
        lua.lua_newtable(L);
        _ = lua.lua_pushstring(L, "kind");
        _ = lua.lua_pushstring(L, "terminated");
        lua.lua_rawset(L, -3);
        _ = lua.lua_pushstring(L, "last_words");
        _ = lua.lua_pushstring(L, ev.msg);
        lua.lua_rawset(L, -3);
        lua.lua_call(L, 2, 0);
    }
}

pub export fn anet_directory_lua_notify_source(
    appl: *c.struct_appl_meta,
    name: [*c]const u8,
    msg: [*c]const u8,
    ref_id: usize,
) void {
    const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(appl.server_tag));
    const r = runner orelse return;

    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        "source:name=%s:status=%s:id=%zu",
        name,
        msg,
        ref_id,
    );
    _ = shmifsrv_enqueue_event(r.cl.?, &ev, -1);
}

pub export fn anet_directory_lua_trigger_auto(appl: *c.struct_appl_meta) void {
    const L = gL orelse return;
    _ = lua.lua_getglobal(L, "autostart");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_pop(L, 1);
        return;
    }

    const len = lua.lua_objlen(L, -1);
    var i: usize = 0;
    while (i < len) : (i += 1) {
        _ = lua.lua_rawgeti(L, -1, @intCast(i + 1));
        const name = lua.luaL_checklstring(L, -1, null);
        var cur: ?*c.struct_appl_meta = appl;
        while (cur) |cu| {
            if (c.strcmp(@as([*c]const u8, @ptrCast(&cu.appl.name)), name) == 0) {
                if (cu.server_appl != c.SERVER_APPL_NONE and cu.server_tag == null) {
                    _ = anet_directory_lua_spawn_runner(cu, gCFG.?.dirsrv.runner_process);
                }
                break;
            }
            cur = cu.next;
        }
        lua.lua_pop(L, 1);
    }
    lua.lua_pop(L, 1);
}

pub export fn anet_directory_lua_admin_command(C: *c.struct_dircl, msg: [*c]const u8) bool {
    const L = gL orelse return false;
    _ = lua.lua_getglobal(L, "admin_command");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return false;
    }

    const arg = arg_unpack(msg);
    if (arg == null) {
        lua.lua_pop(L, 1);
        return false;
    }

    pushDircl(L, C);

    var pos: usize = 0;
    lua.lua_newtable(L);

    while (arg[pos].key != null) : (pos += 1) {
        _ = lua.lua_getfield(L, -1, arg[pos].key);
        if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
            lua.lua_pop(L, 1);
            _ = lua.lua_pushstring(L, arg[pos].key);
            lua.lua_newtable(L);
            lua.lua_rawset(L, -3);
            _ = lua.lua_getfield(L, -1, arg[pos].key);
        }

        const len = lua.lua_objlen(L, -1);
        lua.lua_pushnumber(L, @floatFromInt(len + 1));
        if (arg[pos].value != null and arg[pos].value[0] != 0) {
            _ = lua.lua_pushstring(L, arg[pos].value);
        } else {
            lua.lua_pushboolean(L, 1);
        }
        lua.lua_rawset(L, -3);
        lua.lua_pop(L, 1);
    }

    arg_cleanup(arg);
    lua.lua_call(L, 2, 0);
    return true;
}

pub export fn anet_directory_lua_forced_source(C: *c.struct_dircl) bool {
    const cfg = gCFG orelse return false;
    var M: ?*c.struct_appl_meta = &cfg.dirsrv.dir;
    while (M) |m| {
        const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(m.server_tag));
        if (runner == null) {
            M = m.next;
            continue;
        }
        const S = runner.?;
        _ = c.pthread_mutex_lock(&S.lock);
        for (&S.pending_sources) |*SM| {
            if (std.mem.eql(u8, SM.pubk[0..32], C.pubk[0..32])) {
                C.in_appl = m.identifier;
                @memcpy(C.identity[0..], SM.force_ident[0..]);
                C.ref_id = SM.ref_id;
                anet_directory_lua_notify_source(m, @as([*c]const u8, @ptrCast(&C.identity)), "join", C.ref_id);
                SM.* = std.mem.zeroes(@TypeOf(SM.*));
                _ = c.pthread_mutex_unlock(&S.lock);
                return true;
            }
        }
        _ = c.pthread_mutex_unlock(&S.lock);
        M = m.next;
    }
    return false;
}

pub export fn anet_directory_lua_filter_source(C: *c.struct_dircl, ev: *c.struct_arcan_event) c_int {
    const L = gL orelse return 0;
    _ = lua.lua_getglobal(L, "new_source");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return 0;
    }

    pushDircl(L, C);
    _ = lua.lua_pushstring(L, @as([*c]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.name)));

    switch (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.type) {
        c.ROLE_DIR => _ = lua.lua_pushstring(L, "directory"),
        c.ROLE_SOURCE => _ = lua.lua_pushstring(L, "source"),
        c.ROLE_SINK => _ = lua.lua_pushstring(L, "sink"),
        c.ROLE_DIRREF => _ = lua.lua_pushstring(L, "reference"),
        else => _ = lua.lua_pushstring(L, "unknown_role"),
    }

    lua.lua_call(L, 3, 1);
    const pass = lua.lua_toboolean(L, -1);
    lua.lua_pop(L, 1);
    return if (pass != 0) 1 else 0;
}

pub export fn anet_directory_lua_register_unknown(
    C: *c.struct_dircl,
    base: c.struct_pk_response,
    pubk: [*c]const u8,
) c.struct_pk_response {
    const L = gL orelse return base;
    _ = lua.lua_getglobal(L, "register_unknown");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return base;
    }

    // Track a reference in the client structure, used for metatable functions.
    // register_unknown runs before the client has been "registered" so
    // C->userdata is still NULL — we can't go through pushDircl here.
    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.lua_newuserdata(L, @sizeOf(ClientUserdata))));
    ud.* = .{
        .C = C,
        .directory_link = false,
        .directory_reference = false,
        .directory_resolver = false,
        .client_ref = 0,
    };
    C.userdata = ud;

    lua.lua_pushvalue(L, -1);
    ud.client_ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    // Assign the table of client actions.
    _ = lua.luaL_getmetatable(L, "dircl");
    _ = lua.lua_setmetatable(L, -2);
    _ = lua.lua_pushstring(L, pubk);

    lua.lua_call(L, 2, 1);

    var result = base;
    if (lua.lua_type(L, -1) == lua.LUA_TBOOLEAN) {
        result.authentic = lua.lua_toboolean(L, -1) != 0;
    }
    lua.lua_pop(L, 1);
    return result;
}

pub export fn anet_directory_signal_runner(appl: *c.struct_appl_meta, sig: c_int) bool {
    const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(appl.server_tag));
    const r = runner orelse return false;
    var pid: c_int = 0;
    _ = shmifsrv_client_handle(r.cl.?, &pid);
    return c.kill(pid, sig) == 0;
}

pub export fn anet_directory_lua_update(appl: *c.struct_appl_meta, newappl: c_int) void {
    const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(appl.server_tag));

    // Copy name before potential mutation
    var name: [18]u8 = undefined;
    @memcpy(&name, &appl.appl.name);

    if (newappl != -1) {
        const applf = c.fdopen(newappl, "r") orelse return;
        var err: ?[*c]const u8 = null;
        if (!extract_appl_pkg(applf, gCFG.?.dirsrv.appl_server_temp_dfd, &name, &err, null)) {
            _ = c.fclose(applf);
            return;
        }
    }

    const r = runner orelse return;

    var outev = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;

    const srcdir: c_int = if (appl.server_appl == c.SERVER_APPL_TEMP)
        gCFG.?.dirsrv.appl_server_temp_dfd
    else
        gCFG.?.dirsrv.appl_server_dfd;

    const dfd = c.openat(srcdir, &name, c.O_RDONLY | c.O_DIRECTORY);
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&outev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        outev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        "%s",
        @as([*c]const u8, @ptrCast(&appl.appl.name)),
    );

    _ = c.pthread_mutex_lock(&r.lock);
    _ = shmifsrv_enqueue_event(r.cl.?, &outev, dfd);
    _ = c.pthread_mutex_unlock(&r.lock);
}

pub export fn anet_directory_lua_spawn_runner(appl: *c.struct_appl_meta, external: bool) bool {
    const cfg = gCFG.?;
    const runner: *c.struct_runner_state = @ptrCast(@alignCast(
        c.malloc(@sizeOf(c.struct_runner_state)) orelse return false,
    ));
    runner.* = std.mem.zeroes(c.struct_runner_state);
    runner.appl = appl;
    runner.store_dfd = ctrlDirfd(appl);

    if (external) {
        const namelen = c.strlen(@as([*c]const u8, @ptrCast(&appl.appl.name)));
        // "dirappl-" + name + NUL
        const named_arg: [*c]u8 = @ptrCast(c.malloc(9 + namelen) orelse {
            deallocRunner(runner);
            return false;
        });
        _ = c.snprintf(named_arg, 9 + namelen, "dirappl-%s", @as([*c]const u8, @ptrCast(&appl.appl.name)));

        var argv: [4][*c]u8 = .{ cfg.path_self, named_arg, null, null };
        const env = c.struct_shmifsrv_envp{
            .init_w = 32,
            .init_h = 32,
            .path = cfg.path_self,
            .envv = null,
            .argv = @ptrCast(&argv),
            .detach = 2 | 4 | 8,
        };

        var clsock: c_int = 0;
        runner.cl = c.shmifsrv_spawn_client(env, &clsock, null, 0);
        c.free(named_arg);
        if (runner.cl == null) {
            deallocRunner(runner);
            return false;
        }

        appl.server_tag = runner;
        _ = c.pthread_mutex_init(&runner.lock, null);
        runDetachedThread(controller_runner_thread, runner);

        // Block until the appl has been sent to the worker
        while (!@atomicLoad(bool, &runner.appl_sent, .seq_cst)) {
            _ = c.pthread_mutex_lock(&runner.lock);
            _ = c.pthread_mutex_unlock(&runner.lock);
        }
        return true;
    }

    // In-process thread mode
    var sv: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) == -1) {
        deallocRunner(runner);
        return false;
    }

    var sc: c_int = 0;
    runner.cl = shmifsrv_inherit_connection(sv[0], -1, &sc);
    if (runner.cl == null) {
        _ = c.close(sv[0]);
        deallocRunner(runner);
        return false;
    }

    // Safety note: mutating env vars from a thread is not POSIX-safe.
    // This path is for debug convenience only, matching the C original.
    _ = c.unsetenv("ARCAN_CONNPATH");
    var buf: [8]u8 = undefined;
    _ = c.snprintf(&buf, 8, "%d", sv[1]);
    _ = c.setenv("ARCAN_SOCKIN_FD", @as([*:0]const u8, @ptrCast(&buf)), 1);
    _ = c.snprintf(&buf, 8, "%d", shmifsrv_client_memory_handle(runner.cl.?));
    _ = c.setenv("ARCAN_SOCKIN_SHMFD", @as([*:0]const u8, @ptrCast(&buf)), 1);

    runDetachedThread(thread_appl_runner_wrapper, null);
    appl.server_tag = runner;
    _ = c.pthread_mutex_init(&runner.lock, null);
    runDetachedThread(controller_runner_thread, runner);

    return true;
}

fn thread_appl_runner_wrapper(arg: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = arg;
    anet_directory_appl_runner();
    return null;
}

fn sendJoinPair(
    C: *c.struct_dircl,
    appl: *c.struct_appl_meta,
    msg: [*c]const u8,
    workmsg: [*c]const u8,
) bool {
    const runner: ?*c.struct_runner_state = @ptrCast(@alignCast(appl.server_tag));
    const r = runner orelse return false;

    var sv: [2]c_int = undefined;
    if (c.socketpair(c.AF_UNIX, c.SOCK_STREAM, 0, &sv) == -1) return false;

    var ev = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        "%s",
        msg,
    );

    _ = c.pthread_mutex_lock(&r.lock);
    _ = shmifsrv_enqueue_event(r.cl.?, &ev, sv[0]);
    C.in_appl = appl.identifier;
    if (c.strcmp(msg, ".monitor") == 0) C.in_monitor = true;
    _ = c.pthread_mutex_unlock(&r.lock);

    var ev2 = c.struct_arcan_event.zeroes();
    ev2.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    ev2.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_IN;
    _ = c.snprintf(
        @as([*c]u8, @ptrCast(&ev2.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message)),
        ev2.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message.len,
        "%s",
        workmsg,
    );
    _ = shmifsrv_enqueue_event(C.C.?, &ev2, sv[1]);

    _ = c.close(sv[0]);
    _ = c.close(sv[1]);
    return true;
}

pub export fn anet_directory_lua_monitor(C: *c.struct_dircl, appl: *c.struct_appl_meta) bool {
    return sendJoinPair(C, appl, ".monitor", ".monitor");
}

pub export fn anet_directory_lua_join(C: *c.struct_dircl, appl: *c.struct_appl_meta) bool {
    var buf: [32]u8 = undefined;
    var wbuf: [32]u8 = undefined;
    const appl_msg = std.fmt.bufPrintZ(&buf, ".appl-{s}", .{std.mem.sliceTo(@as([*c]const u8, @ptrCast(&appl.appl.name)), 0)}) catch return false;
    const work_msg = std.fmt.bufPrintZ(&wbuf, ".worker-{s}", .{std.mem.sliceTo(@as([*c]const u8, @ptrCast(&C.identity)), 0)}) catch return false;
    return sendJoinPair(C, appl, work_msg.ptr, appl_msg.ptr);
}

pub export fn anet_directory_lua_unregister(C: *c.struct_dircl) void {
    if (C.userdata == null) return;
    const L = gL orelse return;

    _ = lua.lua_getglobal(L, "unregister");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return;
    }

    pushDircl(L, C);
    lua.lua_call(L, 1, 0);

    const ud: *ClientUserdata = @ptrCast(@alignCast(C.userdata.?));
    ud.C = null;
    C.userdata = null;

    if (ud.client_ref == lua.LUA_NOREF) return;
    lua.luaL_unref(L, lua.LUA_REGISTRYINDEX, @intCast(ud.client_ref));
    ud.client_ref = lua.LUA_NOREF;
}

pub export fn anet_directory_lua_register(C: *c.struct_dircl) void {
    const L = gL orelse return;
    _ = lua.lua_getglobal(L, "register");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return;
    }

    const ud: *ClientUserdata = @ptrCast(@alignCast(lua.lua_newuserdata(L, @sizeOf(ClientUserdata))));
    ud.* = .{ .C = C, .directory_link = false, .directory_reference = false, .directory_resolver = false, .client_ref = 0 };
    C.userdata = ud;

    lua.lua_pushvalue(L, -1);
    ud.client_ref = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    _ = lua.luaL_getmetatable(L, "dircl");
    _ = lua.lua_setmetatable(L, -2);

    lua.lua_call(L, 1, 0);
}

pub export fn anet_directory_lua_init(cfg: *c.struct_global_cfg, ctx: *lua.lua_State) void {
    gCFG = cfg;
    gL = ctx;

    gDB = arcan_db_open(cfg.db_file, null);
    if (gDB == null) {
        _ = lua.luaL_error(ctx, "database failure - check config.paths.database and file permissions");
    }
}

pub export fn anet_directory_lua_ready(cfg: *c.struct_global_cfg) void {
    _ = cfg;
    const L = gL orelse return;
    _ = lua.lua_getglobal(L, "ready");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_pop(L, 1);
        return;
    }
    lua.lua_call(L, 0, 0);
}

/// Look up an ns:ext entry in registry["resource_hooks"].  On success returns
/// true with freshly allocated tag/bin/argv (caller frees).  argv is padded
/// with `argv_reserve` extra NULL slots past the populated entries so the
/// caller can append trailing launch arguments without reallocating.
/// `argv_used` receives the number of populated argv slots on success.
pub export fn anet_directory_lua_resource_hooked(
    ext: [*c]const u8,
    ns: usize,
    argv_reserve: usize,
    tag: *?[*c]u8,
    bin: *?[*c]u8,
    argv: *[*c][*c]u8,
    argv_used: *usize,
) bool {
    const L = gL orelse return false;
    const top = lua.lua_gettop(L);
    var rv: bool = false;
    var key_ptr: [*c]u8 = null;

    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "resource_hooks");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        lua.lua_settop(L, top);
        return false;
    }

    // verify:
    //   table(resource_hooks)
    //   table(ns:ext)
    if (asprintf(&key_ptr, "%zu:%s", ns, ext) <= 0) {
        lua.lua_settop(L, top);
        return false;
    }

    _ = lua.lua_getfield(L, -1, key_ptr);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        c.free(key_ptr);
        lua.lua_settop(L, top);
        return false;
    }

    // extract:
    //  tag
    //  bin
    //  argv[]
    _ = lua.lua_getfield(L, -1, "tag");
    if (lua.lua_type(L, -1) != lua.LUA_TSTRING) {
        _ = lua.luaL_error(L,
            "config.lua corrupted, registry['resource_hooks'] tag bad");
        c.free(key_ptr);
        lua.lua_settop(L, top);
        return false;
    }
    tag.* = c.strdup(lua.lua_tolstring(L, -1, null));
    lua.lua_pop(L, 1);

    _ = lua.lua_getfield(L, -1, "bin");
    if (lua.lua_type(L, -1) != lua.LUA_TSTRING) {
        _ = lua.luaL_error(L,
            "config.lua corrupted, registry['resource_hooks'] bin bad");
        c.free(key_ptr);
        lua.lua_settop(L, top);
        return false;
    }
    bin.* = c.strdup(lua.lua_tolstring(L, -1, null));
    lua.lua_pop(L, 1);

    // table(resource_hooks) / table(ns:ext) / table(argv)
    _ = lua.lua_getfield(L, -1, "argv");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L,
            "config.lua corrupted, registry['resource_hooks'] argv bad");
        c.free(key_ptr);
        lua.lua_settop(L, top);
        return false;
    }

    const len: usize = lua.lua_objlen(L, -1); // Lua 5.1 equivalent of lua_rawlen
    const nb: usize = @sizeOf([*c]u8) * (len + argv_reserve);
    const argv_mem: [*c][*c]u8 = @ptrCast(@alignCast(c.malloc(nb) orelse {
        c.free(key_ptr);
        lua.lua_settop(L, top);
        return false;
    }));
    argv.* = argv_mem;

    // Zero the whole allocation, including the argv_reserve trailing slots.
    const argv_slice: [][*c]u8 = @as([*][*c]u8, @ptrCast(argv_mem))[0 .. len + argv_reserve];
    @memset(argv_slice, null);

    var i: usize = 0;
    while (i < len) : (i += 1) {
        _ = lua.lua_rawgeti(L, -1, @intCast(i + 1));
        argv_mem[i] = c.strdup(lua.lua_tolstring(L, -1, null));
        lua.lua_pop(L, 1);
    }

    lua.lua_pop(L, 1);
    rv = true;
    argv_used.* = len;

    c.free(key_ptr);
    lua.lua_settop(L, top);
    return rv;
}
