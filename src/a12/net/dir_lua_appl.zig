// Zig port of a12/net/dir_lua_appl.c — directory appl runner (Lua VM + worker loop)
// Copyright: Björn Ståhl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. All non-Lua `c.X` references are aliased here from the hand-written
// replacement modules (zero `@cImport` left). Lua bindings come from lua54_api.
// `shmif` is renamed to `shmif_mod` because this file has local variables
// named `shmif` that would otherwise shadow the import.
const shmif_mod = @import("shmif_types");
const a12 = @import("a12_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc
    pub const close = libc.close;
    pub const fchdir = libc.fchdir;
    pub const fdopen = libc.fdopen;
    pub const FILE = libc.FILE;
    pub const fprintf = libc.fprintf;
    pub const fputs = libc.fputs;
    pub const free = libc.free;
    pub const fseek = libc.fseek;
    pub const isalnum = libc.isalnum;
    pub const openat = libc.openat;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const O_RDWR = libc.O_RDWR;
    pub const O_WRONLY = libc.O_WRONLY;
    pub const pipe = libc.pipe;
    pub const poll = libc.poll;
    pub const POLLERR = libc.POLLERR;
    pub const POLLHUP = libc.POLLHUP;
    pub const POLLIN = libc.POLLIN;
    pub const POLLNVAL = libc.POLLNVAL;
    pub const POLLOUT = libc.POLLOUT;
    pub const read = libc.read;
    pub const SEEK_SET = libc.SEEK_SET;
    pub const setlinebuf = libc.setlinebuf;
    pub const sigaction = libc.sigaction;
    pub const strlen = libc.strlen;
    pub const strtoul = libc.strtoul;
    pub const strtoull = libc.strtoull;
    pub const struct_pollfd = libc.struct_pollfd;
    pub const struct_sigaction = libc.struct_sigaction;

    // shmif — SIGUSR1 lives here (shared with a12 trace toggles)
    pub const SIGUSR1 = shmif_mod.SIGUSR1;
    pub const struct_arcan_shmif_cont = shmif_mod.struct_arcan_shmif_cont;
    pub const struct_arcan_event = shmif_mod.struct_arcan_event;
    pub const struct_arg_arr = shmif_mod.struct_arg_arr;
    pub const struct_shmifsrv_client = shmif_mod.struct_shmifsrv_client;
    pub const EVENT_EXTERNAL = shmif_mod.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_BCHUNKSTATE = shmif_mod.EVENT_EXTERNAL_BCHUNKSTATE;
    pub const EVENT_EXTERNAL_MESSAGE = shmif_mod.EVENT_EXTERNAL_MESSAGE;
    pub const EVENT_EXTERNAL_NETSTATE = shmif_mod.EVENT_EXTERNAL_NETSTATE;
    pub const EVENT_TARGET = shmif_mod.EVENT_TARGET;
    pub const SEGID_NETWORK_SERVER = shmif_mod.SEGID_NETWORK_SERVER;
    pub const SHMIF_ACQUIRE_FATALFAIL = shmif_mod.SHMIF_ACQUIRE_FATALFAIL;
    pub const SHMIF_NOACTIVATE = shmif_mod.SHMIF_NOACTIVATE;
    pub const SHMIF_NOAUTO_RECONNECT = shmif_mod.SHMIF_NOAUTO_RECONNECT;
    pub const SHMIF_NOREGISTER = shmif_mod.SHMIF_NOREGISTER;
    pub const SHMIF_SOCKET_PINGEVENT = shmif_mod.SHMIF_SOCKET_PINGEVENT;
    pub const SHMIFSRV_FREE_FULL = shmif_mod.SHMIFSRV_FREE_FULL;
    pub const TARGET_COMMAND_BCHUNK_IN = shmif_mod.TARGET_COMMAND_BCHUNK_IN;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif_mod.TARGET_COMMAND_BCHUNK_OUT;
    pub const TARGET_COMMAND_EXIT = shmif_mod.TARGET_COMMAND_EXIT;
    pub const TARGET_COMMAND_MESSAGE = shmif_mod.TARGET_COMMAND_MESSAGE;
    pub const TARGET_COMMAND_REQFAIL = shmif_mod.TARGET_COMMAND_REQFAIL;
    pub const TARGET_COMMAND_STEPFRAME = shmif_mod.TARGET_COMMAND_STEPFRAME;

    // a12 — CLIENT_DEAD / CLIENT_IDLE status codes
    pub const CLIENT_DEAD = a12.CLIENT_DEAD;
    pub const CLIENT_IDLE = a12.CLIENT_IDLE;

    // anet — directory worker + entrypoint trigger indices
    pub const EP_TRIGGER_CLOCK = anet.EP_TRIGGER_CLOCK;
    pub const EP_TRIGGER_INDEX = anet.EP_TRIGGER_INDEX;
    pub const EP_TRIGGER_JOIN = anet.EP_TRIGGER_JOIN;
    pub const EP_TRIGGER_LEAVE = anet.EP_TRIGGER_LEAVE;
    pub const EP_TRIGGER_LOAD = anet.EP_TRIGGER_LOAD;
    pub const EP_TRIGGER_MAIN = anet.EP_TRIGGER_MAIN;
    pub const EP_TRIGGER_MESSAGE = anet.EP_TRIGGER_MESSAGE;
    pub const EP_TRIGGER_RESET = anet.EP_TRIGGER_RESET;
    pub const EP_TRIGGER_STORE = anet.EP_TRIGGER_STORE;
    pub const struct_dirlua_monitor_state = anet.struct_dirlua_monitor_state;
};

// stderr / stdout are extern vars — not compile-time constants, so they can't
// live inside the dispatch struct. Accessors keep the `stderr()` feel at use
// sites (rewritten to `stderr()` / `stdout()`).
inline fn stderr() *libc.FILE {
    return libc.stderr;
}
inline fn stdout() *libc.FILE {
    return libc.stdout;
}

const lua = @import("lua_api");

// Forward declarations for C functions we call that @cImport can't see

extern "c" fn arcan_shmif_open(segid: c_int, flags: c_int, args: ?*?*c.struct_arg_arr) c.struct_arcan_shmif_cont;
extern "c" fn arcan_shmif_last_words(C: *c.struct_arcan_shmif_cont, words: [*:0]const u8) void;
extern "c" fn arcan_shmif_drop(C: *c.struct_arcan_shmif_cont) void;
extern "c" fn arcan_shmif_enqueue(C: *c.struct_arcan_shmif_cont, ev: *const c.struct_arcan_event) c_int;
extern "c" fn arcan_shmif_pushutf8(C: *c.struct_arcan_shmif_cont, ev: *const c.struct_arcan_event, msg: [*]const u8, len: usize) c_int;
extern "c" fn arcan_shmif_wait(C: *c.struct_arcan_shmif_cont, ev: *c.struct_arcan_event) bool;
extern "c" fn arcan_shmif_poll(C: *c.struct_arcan_shmif_cont, ev: *c.struct_arcan_event) c_int;
extern "c" fn arcan_shmif_dupfd(fd: c_int, dstfd: c_int, nonblock: bool) c_int;
extern "c" fn arcan_shmif_eventstr(ev: *const c.struct_arcan_event, buf: ?[*]u8, buf_sz: usize) [*:0]const u8;
// data_source / map_region mirror arcan_general.h — not exposed through our
// cImport (engine-only header). Declare the ABI here.
const data_source = extern struct {
    fd: c_int,
    source: [*:0]const u8,
};
const map_region = extern struct {
    ptr: ?[*]u8,
    sz: usize,
    fd: c_int,
    rst: bool,
};
extern "c" fn arcan_map_resource(src: *data_source, writable: bool) map_region;
extern "c" fn arcan_release_map(reg: map_region) void;
extern "c" fn arcan_release_resource(src: *data_source) void;
extern "c" fn arg_unpack(msg: [*:0]const u8) ?*c.struct_arg_arr;
extern "c" fn arg_lookup(arr: *c.struct_arg_arr, key: [*:0]const u8, ind: usize, out: *?[*:0]const u8) bool;
extern "c" fn arg_cleanup(arr: *c.struct_arg_arr) void;
extern "c" fn a12helper_tob64(data: [*]const u8, len: usize, out_len: *usize) [*:0]u8;
extern "c" fn shmifsrv_monotonic_rebase() void;
extern "c" fn shmifsrv_monotonic_tick(left: *c_int) c_int;
extern "c" fn shmifsrv_inherit_connection(sockin: c_int, memin: c_int, sc: *c_int) ?*c.struct_shmifsrv_client;
extern "c" fn shmifsrv_poll(cl: *c.struct_shmifsrv_client) c_int;
extern "c" fn shmifsrv_free(cl: *c.struct_shmifsrv_client, mode: c_int) void;
extern "c" fn shmifsrv_enqueue_event(cl: *c.struct_shmifsrv_client, ev: *const c.struct_arcan_event, fd: c_int) bool;
extern "c" fn shmifsrv_enqueue_multipart_message(cl: *c.struct_shmifsrv_client, ev: *const c.struct_arcan_event, msg: [*]const u8, msg_sz: usize) bool;
extern "c" fn shmifsrv_dequeue_events(cl: *c.struct_shmifsrv_client, ev: *c.struct_arcan_event, limit: usize) usize;
extern "c" fn anet_directory_merge_multipart(ev: ?*c.struct_arcan_event, arr: ?*?*c.struct_arg_arr, out: ?*?[*:0]u8, err: ?*c_int) bool;
extern "c" fn dirlua_monitor_watchdog(L: ?*lua.lua_State, D: [*c]lua.lua_Debug) callconv(.c) void;
extern "c" fn dirlua_monitor_getstate() ?*c.struct_dirlua_monitor_state;
extern "c" fn dirlua_monitor_allocstate(C: *c.struct_arcan_shmif_cont) void;
extern "c" fn dirlua_monitor_releasestate(L: ?*lua.lua_State) void;
extern "c" fn dirlua_monitor_flush(out_buf: *?[*]u8) usize;
extern "c" fn dirlua_monitor_command(cmd: [*:0]const u8, L: ?*lua.lua_State, D: ?*anyopaque) bool;
extern "c" fn dirlua_setup_entrypoint(L: ?*lua.lua_State, ep: c_int) bool;
extern "c" fn dirlua_pcall(L: ?*lua.lua_State, nargs: c_int, nret: c_int, panic_fn: *const fn (?*lua.lua_State) callconv(.c) c_int) void;
extern "c" fn dirlua_pcall_prefix(L: ?*lua.lua_State, name: [*:0]const u8) void;
extern "c" fn dirlua_loadfile(L: ?*lua.lua_State, dirfd: c_int, filename: [*:0]const u8, dieonfail: bool) c_int;
extern "c" fn alt_nbio_register(
    L: ?*lua.lua_State,
    add: *const fn (fd: c_int, mode: c_uint, tag: isize) callconv(.c) bool,
    remove: *const fn (fd: c_int, mode: c_uint, out: *isize) callconv(.c) bool,
    err: *const fn (L: ?*lua.lua_State, fd: c_int, tag: isize, src: [*:0]const u8) callconv(.c) void,
) void;
extern "c" fn alt_nbio_import(L: ?*lua.lua_State, fd: c_int, mode: c_int, tag1: ?*anyopaque, tag2: ?*anyopaque) void;
extern "c" fn alt_nbio_data_in(L: ?*lua.lua_State, tag: isize) void;
extern "c" fn alt_nbio_data_out(L: ?*lua.lua_State, tag: isize) void;

// arcan_bootstrap_lua / arcan_bootstrap_lua_len are defined in a generated C file
extern "c" const arcan_bootstrap_lua: [*]const u8;
extern "c" const arcan_bootstrap_lua_len: usize;

// tbldynstr / tblbool are helper macros expanded from dir_lua_support
extern "c" fn tbldynstr(L: ?*lua.lua_State, key: [*:0]const u8, val: [*:0]const u8, top: c_int) void;
extern "c" fn tblbool(L: ?*lua.lua_State, key: [*:0]const u8, val: bool, top: c_int) void;

// Constants

const GROW_SLOTS: usize = 7;
const LIMIT_JOBS: usize = 32;

// Namespace selector tags (for bchunk routing)
const NS_CLID: c_int = 1;
const NS_NONBLOCK: c_int = 2;

// shmif open flags
const shmifopen_flags: c_int =
    c.SHMIF_ACQUIRE_FATALFAIL |
    c.SHMIF_NOACTIVATE |
    c.SHMIF_NOAUTO_RECONNECT |
    c.SHMIF_NOREGISTER |
    c.SHMIF_SOCKET_PINGEVENT;

// Client

const Client = struct {
    name: [64]u8 = std.mem.zeroes([64]u8),
    keyid: [45]u8 = std.mem.zeroes([45]u8), // 4 * 32 / 3, align %4 + NUL
    clid: usize = 0,
    msgbuf: [128]usize = std.mem.zeroes([128]usize),
    msgbuf_ofs: usize = 0,
    shmif: ?*c.struct_shmifsrv_client = null,
    ident: ?[*:0]const u8 = null,
    registered: bool = false,
};

// Module-level state

const GlobalState = struct {
    L: ?*lua.lua_State = null,
    SHMIF: c.struct_arcan_shmif_cont = std.mem.zeroes(c.struct_arcan_shmif_cont),
    shutdown: bool = false,
    in_filereq_handler: c_int = 0,
    filereq_handler_ref: c_int = -1,
};

var G: GlobalState = .{};

const ClientSet = struct {
    dirfd: c_int = -1,
    active: usize = 0,
    set_sz: usize = 0,
    pset: ?[*]c.struct_pollfd = null,
    cset: ?[*]Client = null,
    monitor_slot: usize = 0,
};

var CLIENTS: ClientSet = .{};

// nbio job tracking (mirrors nbio_static_loop.h)
const NbioJobs = struct {
    fdin: [LIMIT_JOBS]c_int = std.mem.zeroes([LIMIT_JOBS]c_int),
    fdin_tags: [LIMIT_JOBS]isize = std.mem.zeroes([LIMIT_JOBS]isize),
    fdin_used: usize = 0,
    fdout: [LIMIT_JOBS]c.struct_pollfd = std.mem.zeroes([LIMIT_JOBS]c.struct_pollfd),
    fdout_tags: [LIMIT_JOBS]isize = std.mem.zeroes([LIMIT_JOBS]isize),
    fdout_used: usize = 0,
};

var nbio_jobs: NbioJobs = .{};

var logout: ?*c.FILE = null;

// Logging helper

fn log_print(comptime fmt: []const u8, args: anytype) void {
    if (logout) |f| {
        var buf: [512]u8 = undefined;
        const s = std.fmt.bufPrintZ(&buf, fmt ++ "\n", args) catch return;
        _ = c.fputs(s.ptr, f);
    }
}

// UTF-8 sanitisation (mirrors slim_utf8_push / MSGBUF_UTF8)
// We expose the C version via an extern rather than re-implementing it, since
// utf8_decode lives in an included .c file on the C side.
extern "c" fn utf8_decode(state: *u32, codepoint: *u32, byte: u8) u32;
const UTF8_ACCEPT: u32 = 0;
const UTF8_REJECT: u32 = 1;

fn slim_utf8_push(dst: [*]u8, ulim: usize, inmsg: [*:0]const u8) void {
    var state: u32 = 0;
    var codepoint: u32 = 0;
    var i: usize = 0;
    while (inmsg[i] != 0 and i < ulim) : (i += 1) {
        dst[i] = inmsg[i];
        if (utf8_decode(&state, &codepoint, inmsg[i]) == UTF8_REJECT) {
            dst[0] = 0;
            return;
        }
    }
    if (state == UTF8_ACCEPT) {
        dst[i] = 0;
    } else {
        dst[0] = 0;
    }
}

/// Apply in-place UTF-8 validation on a mutable buffer (mirrors MSGBUF_UTF8).
fn msgbuf_utf8(buf: [*]u8, len: usize) void {
    slim_utf8_push(buf, len - 1, @ptrCast(buf));
}

// Stack dump (debug helper)

fn dump_stack(L: ?*lua.lua_State, dst: *c.FILE) void {
    const top = lua.lua_gettop(L);
    _ = c.fprintf(dst, "-- stack dump (%d)--\n", top);
    var i: c_int = 1;
    while (i <= top) : (i += 1) {
        const t = lua.lua_type(L, i);
        switch (t) {
            lua.LUA_TBOOLEAN => {
                _ = c.fprintf(dst, if (lua.lua_toboolean(L, i) != 0) "true" else "false");
            },
            lua.LUA_TSTRING => {
                _ = c.fprintf(dst, "%d\t'%s'\n", i, lua.lua_tolstring(L, i, null));
            },
            lua.LUA_TNUMBER => {
                _ = c.fprintf(dst, "%d\t%g\n", i, lua.lua_tonumber(L, i));
            },
            else => {
                _ = c.fprintf(dst, "%d\t%s\n", i, lua.lua_typename(L, t));
            },
        }
    }
    _ = c.fprintf(dst, "\n");
}

// Lua panic handler

fn panic(L: ?*lua.lua_State) callconv(.c) c_int {
    // With a monitor attached we don't immediately die — send the trace and return.
    if (CLIENTS.monitor_slot != 0) {
        dirlua_monitor_watchdog(L, null);
        return 0;
    }

    // Free all worker clients so DMS/EXIT gets propagated.
    var i: usize = 1;
    while (i < CLIENTS.set_sz) : (i += 1) {
        if (CLIENTS.cset.?[i].shmif) |shmif| {
            shmifsrv_free(shmif, c.SHMIFSRV_FREE_FULL);
        }
    }

    if (logout) |f| {
        _ = c.fprintf(f, "\nScript Error:\nVM stack:\n");
        if (L) |L_arg| dump_stack(L_arg, f);
    }
    arcan_shmif_last_words(&G.SHMIF, "script_error");
    arcan_shmif_drop(&G.SHMIF);
    std.process.exit(1);
}

// API exposure

fn expose_api(L: ?*lua.lua_State, funtbl: [*]const lua.luaL_Reg) void {
    var ft = funtbl;
    while (ft[0].name != null) : (ft += 1) {
        _ = lua.lua_pushstring(L, ft[0].name);
        lua.lua_pushcclosure(L, ft[0].func, 1);
        lua.lua_setglobal(L, ft[0].name);
    }
}

// Client lookup

fn alua_checkclient(L: ?*lua.lua_State, ind: c_int) *Client {
    const clid: usize = @intFromFloat(lua.lua_tonumber(L, ind));
    var i: usize = 0;
    while (i < CLIENTS.set_sz) : (i += 1) {
        const cl = &CLIENTS.cset.?[i];
        if (cl.clid == clid) {
            if (cl.shmif == null) {
                _ = lua.luaL_error(L, "client identifier to dead client: %zu\n", clid);
            }
            return cl;
        }
    }
    _ = lua.luaL_error(L, "unknown client identifier: %zu\n", clid);
    unreachable;
}

// Key validation

fn validate_key(key: [*:0]const u8) bool {
    var p = key;
    while (p[0] != 0) : (p += 1) {
        const ch = p[0];
        if (c.isalnum(ch) == 0 and ch != '_' and ch != '+' and ch != '/' and ch != '=')
            return false;
    }
    return true;
}

// send_setkey

fn send_setkey(key: [*:0]const u8, val: [*:0]const u8, use_dom: bool, domain: c_int) void {
    var buf: [512]u8 = undefined;
    const req_slice = if (use_dom)
        std.fmt.bufPrintZ(&buf, "setkey={s}:domain={d}:value={s}", .{ key, domain, val }) catch return
    else
        std.fmt.bufPrintZ(&buf, "setkey={s}:value={s}", .{ key, val }) catch return;

    var mev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    mev.unnamed_0.unnamed_0.category = @intCast(c.EVENT_EXTERNAL);
    _ = arcan_shmif_pushutf8(&G.SHMIF, &mev, req_slice.ptr, req_slice.len);
}

// Lua bound functions

fn storekeys(L: ?*lua.lua_State) callconv(.c) c_int {
    if (lua.lua_type(L, 1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "store_keys(>tbl<) expecting key-indexed table");
        return 0;
    }
    const domain: c_int = @intFromFloat(lua.luaL_optnumber(L, 2, 0));

    var beg: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    beg.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    beg.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    _ = std.fmt.bufPrintZ(
        beg.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0..beg.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data.len],
        "begin_kv_transaction:domain={d}",
        .{@rem(domain, 10)},
    ) catch {};
    _ = arcan_shmif_enqueue(&G.SHMIF, &beg);

    lua.lua_pushnil(L);
    while (lua.lua_next(L, 1) != 0) {
        const key: [*:0]const u8 = lua.lua_tolstring(L, -2, null) orelse {
            _ = lua.luaL_error(L, "store_keys(>tbl<) - non-string key");
            return 0;
        };
        if (!validate_key(key)) {
            _ = lua.luaL_error(L, "store_keys(>tbl<) - invalid key (alphanum, no +/_=)");
            return 0;
        }
        const value: [*:0]const u8 = lua.lua_tolstring(L, -1, null) orelse "(null)";
        send_setkey(key, value, false, 0);
        lua.lua_pop(L, 1);
    }

    var endtrans: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    endtrans.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    endtrans.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;
    @memcpy(endtrans.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0.."end_kv_transaction".len], "end_kv_transaction");
    _ = arcan_shmif_enqueue(&G.SHMIF, &endtrans);
    return 0;
}

fn listtargets(L: ?*lua.lua_State) callconv(.c) c_int {
    if (!lua.lua_isfunction(L, 2) or (lua.lua_iscfunction(L, 2) != 0)) {
        _ = lua.luaL_error(L, "list_targets(>handler<), handler is not a function");
        return 0;
    }
    lua.lua_pushvalue(L, 2);
    const ref: isize = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    var ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    _ = std.fmt.bufPrintZ(
        ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0..ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data.len],
        ".target_index:id={d}",
        .{ref},
    ) catch {};
    _ = arcan_shmif_enqueue(&G.SHMIF, &ev);
    return 0;
}

fn systemload(L: ?*lua.lua_State) callconv(.c) c_int {
    const fn_name: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;
    var dieonfail: bool = true;
    if (lua.lua_isboolean(L, 2))
        dieonfail = lua.lua_toboolean(L, 2) != 0;
    return dirlua_loadfile(L, CLIENTS.dirfd, fn_name, dieonfail);
}

fn clientid(L: ?*lua.lua_State) callconv(.c) c_int {
    const cl = alua_checkclient(L, 1);
    var raw: bool = false;
    if (lua.lua_isboolean(L, 2))
        raw = lua.lua_toboolean(L, 2) != 0;

    _ = lua.lua_pushstring(L, cl.ident orelse "");

    if (raw) {
        _ = lua.lua_pushstring(L, @ptrCast(&cl.keyid));
    } else {
        const keyid_ptr: [*:0]const u8 = @ptrCast(&cl.keyid);
        var len: usize = c.strlen(keyid_ptr);
        while (len > 0 and keyid_ptr[len - 1] == '=') : (len -= 1) {}
        _ = lua.lua_pushlstring(L, keyid_ptr, len);
    }

    return 2;
}

fn sinkclient(L: ?*lua.lua_State) callconv(.c) c_int {
    const dst = alua_checkclient(L, 1);
    const name: [*:0]const u8 = lua.luaL_checklstring(L, 2, null) orelse return 0;

    var buf: [256]u8 = undefined;
    const req = std.fmt.bufPrintZ(&buf, "sink_client={s}:dst={s}", .{ name, dst.ident orelse "" }) catch {
        lua.lua_pushboolean(L, 0);
        return 1;
    };
    var mev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    mev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    _ = arcan_shmif_pushutf8(&G.SHMIF, &mev, req.ptr, req.len);
    lua.lua_pushboolean(L, 1);
    return 1;
}

fn sourceclient(L: ?*lua.lua_State) callconv(.c) c_int {
    const name: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;
    const dst = alua_checkclient(L, 2);
    if (!lua.lua_isfunction(L, 3) or (lua.lua_iscfunction(L, 3) != 0)) {
        _ = lua.luaL_error(L, "source_client(name, clid, >handler<) is not a function");
        return 0;
    }
    const ref: isize = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    var buf: [512]u8 = undefined;
    const req = std.fmt.bufPrintZ(
        &buf,
        "source_client={s}:dst={s}:id={d}",
        .{ name, dst.ident orelse "", ref },
    ) catch {
        lua.lua_pushboolean(L, 0);
        return 1;
    };
    var mev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    mev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    _ = arcan_shmif_pushutf8(&G.SHMIF, &mev, req.ptr, req.len);
    lua.lua_pushboolean(L, 1);
    return 1;
}

fn launchtarget(L: ?*lua.lua_State) callconv(.c) c_int {
    const name: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;
    if (lua.lua_type(L, 2) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "launch_target(name, >option table<, ...) no table provided");
        return 0;
    }

    const argstr: [*:0]const u8 = "";
    var dst: ?*Client = null;
    var ind: c_int = 3;

    if (lua.lua_type(L, 3) == lua.LUA_TNUMBER) {
        dst = alua_checkclient(L, 3);
        ind += 1;
    }

    if (!lua.lua_isfunction(L, ind) or (lua.lua_iscfunction(L, ind) != 0)) {
        _ = lua.luaL_error(L, "launch_target(..., >handler<) is not a function");
        return 0;
    }
    const ref: isize = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);

    var buf: [512]u8 = undefined;
    const req = if (dst == null)
        std.fmt.bufPrintZ(&buf, "launch={s}:id={d}:args={s}", .{ name, ref, argstr }) catch {
            lua.lua_pushboolean(L, 0);
            return 1;
        }
    else
        std.fmt.bufPrintZ(&buf, "launch={s}:dst={s}:id={d}:args={s}", .{
            name, dst.?.ident orelse "", ref, argstr,
        }) catch {
            lua.lua_pushboolean(L, 0);
            return 1;
        };

    var mev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    mev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    _ = arcan_shmif_pushutf8(&G.SHMIF, &mev, req.ptr, req.len);
    lua.lua_pushboolean(L, 1);
    return 1;
}

fn matchkeys(L: ?*lua.lua_State) callconv(.c) c_int {
    const pattern: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;
    if (!lua.lua_isfunction(L, 2) or (lua.lua_iscfunction(L, 2) != 0)) {
        _ = lua.luaL_error(L, "match_keys(pattern, >handler<, [domain]), handler is not a function");
        return 0;
    }
    lua.lua_pushvalue(L, 2);
    const ref: isize = lua.luaL_ref(L, lua.LUA_REGISTRYINDEX);
    const domain: c_int = @intFromFloat(lua.luaL_optnumber(L, 3, 0));

    var buf: [512]u8 = undefined;
    const req = std.fmt.bufPrintZ(&buf, "match={s}:domain={d}:id={d}", .{ pattern, domain, ref }) catch {
        lua.lua_pushboolean(L, 0);
        return 1;
    };
    var mev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    mev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    _ = arcan_shmif_pushutf8(&G.SHMIF, &mev, req.ptr, req.len);
    return 0;
}

fn targetmessage(L: ?*lua.lua_State) callconv(.c) c_int {
    var strind: c_int = 1;
    var target: ?*Client = null;

    if (lua.lua_type(L, 1) == lua.LUA_TNUMBER) {
        target = alua_checkclient(L, 1);
        strind = 2;
    }

    var out_sz: usize = 0;
    const msg: [*:0]const u8 = lua.luaL_checklstring(L, strind, &out_sz) orelse return 0;

    var outev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    outev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_MESSAGE;

    if (target) |tgt| {
        if (tgt.shmif == null) {
            log_print("kind=error:bad_shmif:source=message_target:id={d}", .{lua.lua_tonumber(L, 1)});
        }
        lua.lua_pushboolean(L, if (shmifsrv_enqueue_multipart_message(
            tgt.shmif.?,
            &outev,
            msg,
            out_sz,
        )) 1 else 0);
        return 1;
    }

    // Broadcast to all registered clients
    var i: usize = 0;
    while (i < CLIENTS.set_sz) : (i += 1) {
        if (CLIENTS.cset.?[i].shmif) |shmif| {
            _ = shmifsrv_enqueue_multipart_message(shmif, &outev, msg, out_sz);
        }
    }
    lua.lua_pushboolean(L, 1);
    return 1;
}

fn acceptnonblock(L: ?*lua.lua_State) callconv(.c) c_int {
    if (G.in_filereq_handler == 0) {
        _ = lua.luaL_error(L, "accept_nonblock() - only valid inside client request entrypoint");
        return 0;
    }
    if (G.filereq_handler_ref != -1) {
        _ = lua.luaL_error(L, "accept_nonblock() - only allowed once within scope of entrypoint");
        return 0;
    }

    var pair: [2]c_int = undefined;
    if (c.pipe(&pair) == -1)
        return 0;

    if (G.in_filereq_handler == c.O_RDONLY) {
        alt_nbio_import(L, pair[1], c.O_WRONLY, null, null);
        G.filereq_handler_ref = pair[0];
    } else {
        alt_nbio_import(L, pair[0], c.O_RDONLY, null, null);
        G.filereq_handler_ref = pair[1];
    }
    return 1;
}

fn reqnonblock(L: ?*lua.lua_State) callconv(.c) c_int {
    if (!lua.lua_isfunction(L, 3) or (lua.lua_iscfunction(L, 3) != 0)) {
        _ = lua.luaL_error(L, "request_nonblock(name, mode, >handler<), handler is not a function");
        return 0;
    }
    const write: bool = lua.luaL_checknumber(L, 2) != 0;
    const name: [*:0]const u8 = lua.luaL_checklstring(L, 1, null) orelse return 0;

    lua.lua_pushvalue(L, 3);
    var ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    ev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.kind = c.EVENT_EXTERNAL_BCHUNKSTATE;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier = @intCast(lua.luaL_ref(L, lua.LUA_REGISTRYINDEX));
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input = if (write) 0 else 1;
    ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns = NS_NONBLOCK;

    const ext_len = ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len;
    _ = std.fmt.bufPrint(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0..ext_len], "{s}", .{name}) catch {};
    _ = arcan_shmif_enqueue(&G.SHMIF, &ev);
    return 0;
}

fn print_log(L: ?*lua.lua_State) callconv(.c) c_int {
    const n = lua.lua_gettop(L);
    _ = lua.lua_getglobal(L, "tostring");
    if (logout) |f| {
        _ = c.fputs("kind=lua:print=", f);
    }
    var i: c_int = 1;
    while (i <= n) : (i += 1) {
        lua.lua_pushvalue(L, -1);
        lua.lua_pushvalue(L, i);
        lua.lua_call(L, 1, 1);
        const s = lua.lua_tolstring(L, -1, null);
        if (s == null) {
            return lua.luaL_error(L, "'tostring' must return a string to 'print'");
        }
        if (logout) |f| {
            if (i > 1) _ = c.fputs("\t", f);
            _ = c.fputs(s, f);
        }
        lua.lua_pop(L, 1);
    }
    if (logout) |f| {
        _ = c.fputs("\n", f);
    }
    return 0;
}

// nbio error handler

fn nbio_error(L: ?*lua.lua_State, fd: c_int, tag: isize, src: [*:0]const u8) callconv(.c) void {
    _ = L;
    _ = fd;
    _ = tag;
    _ = src;
    // Debug-only in original; no-op here
}

// nbio queue/dequeue (mirrors nbio_static_loop.h)

fn nbio_queue(fd: c_int, mode: c_uint, tag: isize) callconv(.c) bool {
    if (fd == -1) return false;

    if (mode == c.O_RDONLY) {
        if (nbio_jobs.fdin_used >= LIMIT_JOBS - 1) return false;
        nbio_jobs.fdin[nbio_jobs.fdin_used] = fd;
        nbio_jobs.fdin_tags[nbio_jobs.fdin_used] = tag;
        nbio_jobs.fdin_used += 1;
    }

    if (mode == c.O_WRONLY) {
        if (nbio_jobs.fdout_used >= LIMIT_JOBS - 1) return false;
        nbio_jobs.fdout[nbio_jobs.fdout_used].fd = fd;
        nbio_jobs.fdout[nbio_jobs.fdout_used].events = c.POLLOUT | c.POLLERR | c.POLLHUP;
        nbio_jobs.fdout_tags[nbio_jobs.fdout_used] = tag;
        nbio_jobs.fdout_used += 1;
    }

    if (mode != c.O_RDONLY and mode != c.O_WRONLY)
        std.process.abort();

    return true;
}

fn nbio_dequeue(fd: c_int, mode: c_uint, out_tag: *isize) callconv(.c) bool {
    var found = false;

    if (mode == c.O_RDONLY) {
        var i: usize = 0;
        while (i < nbio_jobs.fdin_used) : (i += 1) {
            if (nbio_jobs.fdin[i] == fd) {
                out_tag.* = nbio_jobs.fdin_tags[i];
                // Compact the arrays
                std.mem.copyForwards(
                    isize,
                    nbio_jobs.fdin_tags[i .. nbio_jobs.fdin_used - 1],
                    nbio_jobs.fdin_tags[i + 1 .. nbio_jobs.fdin_used],
                );
                std.mem.copyForwards(
                    c_int,
                    nbio_jobs.fdin[i .. nbio_jobs.fdin_used - 1],
                    nbio_jobs.fdin[i + 1 .. nbio_jobs.fdin_used],
                );
                nbio_jobs.fdin_used -= 1;
                found = true;
                break;
            }
        }
    }

    var i: usize = 0;
    while (i < nbio_jobs.fdout_used) : (i += 1) {
        if (nbio_jobs.fdout[i].fd == fd) {
            out_tag.* = nbio_jobs.fdout_tags[i];
            nbio_jobs.fdout_used -= 1;
            std.mem.copyForwards(
                isize,
                nbio_jobs.fdout_tags[i .. nbio_jobs.fdout_used],
                nbio_jobs.fdout_tags[i + 1 .. nbio_jobs.fdout_used + 1],
            );
            std.mem.copyForwards(
                c.struct_pollfd,
                nbio_jobs.fdout[i .. nbio_jobs.fdout_used],
                nbio_jobs.fdout[i + 1 .. nbio_jobs.fdout_used + 1],
            );
            found = true;
            break;
        }
    }
    return found;
}

// open_appl

fn open_appl(dfd: c_int, name: [*:0]const u8) void {
    // Swap dirfd
    if (CLIENTS.dirfd != -1) _ = c.close(CLIENTS.dirfd);
    CLIENTS.dirfd = dfd;

    log_print("dir_lua:open={s}", .{name});
    const len = std.mem.len(name);

    // Graceful shutdown of existing VM
    if (G.L) |L| {
        log_print("existing:reset", .{});
        if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_RESET)) {
            dirlua_pcall(L, 0, 0, panic);
        }
        lua.lua_close(L);
        G.L = null;
    }

    const newL = lua.luaL_newstate() orelse {
        log_print("dir_lua:no_lua_state", .{});
        return;
    };
    _ = lua.lua_atpanic(newL, panic);

    const rv = lua.luaL_loadbuffer(
        newL,
        @ptrCast(arcan_bootstrap_lua),
        arcan_bootstrap_lua_len,
        "bootstrap",
    );
    if (rv != 0) {
        log_print("dir_lua:build_error:bootstrap.lua", .{});
        return;
    }

    lua.luaL_openlibs(newL);
    lua.lua_pushcfunction(newL, print_log);
    lua.lua_setglobal(newL, "print");
    _ = lua.lua_pcall(newL, 0, 0, 0);

    _ = lua.lua_pushstring(newL, "zig-port");
    lua.lua_setglobal(newL, "API_ENGINE_BUILD");

    dirlua_pcall_prefix(newL, name);

    // Build scratch filename: "<name>.lua"
    var scratch_buf: [256]u8 = undefined;
    const scratch = std.fmt.bufPrintZ(&scratch_buf, "{s}.lua", .{name}) catch return;

    var source: data_source = std.mem.zeroes(data_source);
    source.fd = c.openat(dfd, scratch.ptr, c.O_RDONLY);
    _ = c.fchdir(dfd);

    const reg = arcan_map_resource(&source, false);

    if (lua.luaL_loadbuffer(newL, @ptrCast(reg.ptr), reg.sz, name) == 0) {
        const api = [_]lua.luaL_Reg{
            .{ .name = "message_target", .func = targetmessage },
            .{ .name = "store_keys", .func = storekeys },
            .{ .name = "match_keys", .func = matchkeys },
            .{ .name = "list_targets", .func = listtargets },
            .{ .name = "launch_target", .func = launchtarget },
            .{ .name = "source_client", .func = sourceclient },
            .{ .name = "sink_client", .func = sinkclient },
            .{ .name = "client_identifier", .func = clientid },
            .{ .name = "system_load", .func = systemload },
            .{ .name = "request_nonblock", .func = reqnonblock },
            .{ .name = "accept_nonblock", .func = acceptnonblock },
            .{ .name = null, .func = null },
        };
        expose_api(newL, &api);
        alt_nbio_register(newL, nbio_queue, nbio_dequeue, nbio_error);
        dirlua_pcall(newL, 0, 0, panic);
    }

    arcan_release_map(reg);
    arcan_release_resource(&source);

    G.L = newL;

    if (dirlua_setup_entrypoint(newL, c.EP_TRIGGER_MAIN)) {
        dirlua_pcall(newL, 0, 0, panic);
    }

    // Re-expose existing clients as fake JOIN calls
    log_print("status:adopt={d}", .{CLIENTS.active});
    var i: usize = 0;
    while (i < CLIENTS.set_sz) : (i += 1) {
        if (CLIENTS.cset.?[i].shmif == null) continue;
        if (dirlua_setup_entrypoint(newL, c.EP_TRIGGER_JOIN)) {
            lua.lua_pushnumber(newL, @floatFromInt(CLIENTS.cset.?[i].clid));
            dirlua_pcall(newL, 1, 0, panic);
        }
    }
    _ = len;
}

// Monitor SIGUSR1 handler

fn monitor_sigusr(sig: c_int) callconv(.c) void {
    _ = sig;
    if (G.L) |L| {
        _ = lua.lua_sethook(L, dirlua_monitor_watchdog, lua.LUA_MASKCOUNT, 1);
    }
    if (dirlua_monitor_getstate()) |state| {
        state.dumppause = true;
    }
}

// join_worker

fn join_worker(fd: c_int, ident: [*:0]const u8, monitor: bool) bool {
    const gpa = std.heap.c_allocator;

    // Grow the poll/client sets if needed
    if (CLIENTS.active == CLIENTS.set_sz) {
        const new_sz = CLIENTS.set_sz + GROW_SLOTS;
        const new_pset = gpa.alloc(c.struct_pollfd, new_sz) catch {
            _ = c.close(fd);
            return false;
        };
        const new_cset = gpa.alloc(Client, new_sz) catch {
            gpa.free(new_pset);
            _ = c.close(fd);
            return false;
        };

        if (CLIENTS.pset) |old_pset| {
            @memcpy(new_pset[0..CLIENTS.set_sz], old_pset[0..CLIENTS.set_sz]);
            gpa.free(old_pset[0..CLIENTS.set_sz]);
        }
        if (CLIENTS.cset) |old_cset| {
            @memcpy(new_cset[0..CLIENTS.set_sz], old_cset[0..CLIENTS.set_sz]);
            gpa.free(old_cset[0..CLIENTS.set_sz]);
        }

        for (CLIENTS.set_sz..new_sz) |i| {
            new_pset[i] = .{ .fd = -1, .events = 0, .revents = 0 };
            new_cset[i] = .{};
        }

        CLIENTS.pset = new_pset.ptr;
        CLIENTS.cset = new_cset.ptr;
        CLIENTS.set_sz = new_sz;
    }

    // Find an empty slot (slot 0 reserved for shmif)
    var ind: usize = 0;
    while (ind < CLIENTS.set_sz) : (ind += 1) {
        if (CLIENTS.pset.?[ind].fd <= 0) break;
    }

    CLIENTS.pset.?[ind] = .{
        .fd = fd,
        .events = c.POLLIN | c.POLLERR | c.POLLHUP,
        .revents = 0,
    };

    // Duplicate ident string
    const ident_dup = gpa.dupeZ(u8, std.mem.span(ident)) catch {
        _ = c.close(fd);
        return false;
    };

    CLIENTS.cset.?[ind] = Client{
        .registered = false,
        .clid = ind,
        .ident = ident_dup.ptr,
    };

    if (ind != 0) {
        const cl = &CLIENTS.cset.?[ind];
        var tmp: c_int = 0;
        cl.shmif = shmifsrv_inherit_connection(fd, -1, &tmp);
        var pv = shmifsrv_poll(cl.shmif.?);
        while (pv != c.CLIENT_IDLE and pv != c.CLIENT_DEAD) {
            pv = shmifsrv_poll(cl.shmif.?);
        }
        if (pv == c.CLIENT_DEAD) {
            log_print("status=worker_broken", .{});
            shmifsrv_free(cl.shmif.?, c.SHMIFSRV_FREE_FULL);
            cl.shmif = null;
            return false;
        }
        log_print("status=joined:worker={d}", .{cl.clid});

        if (monitor) {
            cl.registered = true;
            CLIENTS.monitor_slot = ind;
            var msg_ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
            msg_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            msg_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
            @memcpy(msg_ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0.."#WAITING\n".len], "#WAITING\n");
            _ = shmifsrv_enqueue_event(cl.shmif.?, &msg_ev, -1);

            dirlua_monitor_allocstate(&G.SHMIF);
            // struct_sigaction's internal __sa_handler union is opaque in
            // posix_libc (the struct is an [152]u8 blob). Use signal(3) here
            // — only the handler fn is needed; none of sigaction's extra
            // knobs (mask, flags, restorer) were set in the C original.
            _ = libc.signal(c.SIGUSR1, monitor_sigusr);
        }
    }

    CLIENTS.active += 1;
    return true;
}

// release_worker

fn release_worker(ind: usize) void {
    if (ind >= CLIENTS.set_sz or ind == 0) return;

    if (ind == CLIENTS.monitor_slot) {
        CLIENTS.monitor_slot = 0;
        _ = anet_directory_merge_multipart(null, null, null, null);
        if (G.L) |L| dirlua_monitor_releasestate(L);
    }

    const cl = &CLIENTS.cset.?[ind];
    _ = c.close(CLIENTS.pset.?[ind].fd);
    CLIENTS.pset.?[ind].fd = -1;
    CLIENTS.active -= 1;

    if (cl.registered) {
        if (G.L) |L| {
            if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_LEAVE)) {
                lua.lua_pushnumber(L, @floatFromInt(cl.clid));
                dirlua_pcall(L, 1, 0, panic);
            }
        }
    }

    log_print("status=left:worker={d}:ident={s}", .{ cl.clid, cl.ident orelse "" });
    if (cl.shmif) |shmif| shmifsrv_free(shmif, c.SHMIFSRV_FREE_FULL);
    CLIENTS.cset.?[ind] = .{};
}

// lua_pushkv_buffer

fn lua_pushkv_buffer(L: ?*lua.lua_State, pos_in: ?[*]u8, end: [*]u8) void {
    lua.lua_newtable(L);
    var pos = pos_in orelse return;
    while (@intFromPtr(pos) < @intFromPtr(end)) {
        const len = std.mem.len(@as([*:0]u8, @ptrCast(pos)));
        if (std.mem.indexOfScalar(u8, pos[0..len], '=')) |eq_off| {
            _ = lua.lua_pushlstring(L, pos, eq_off);
            _ = lua.lua_pushstring(L, @ptrCast(pos + eq_off + 1));
        } else {
            _ = lua.lua_pushlstring(L, pos, len);
            lua.lua_pushboolean(L, 1);
        }
        lua.lua_rawset(L, -3);
        pos += len + 1;
    }
}

// meta_resource

fn meta_resource(fd: c_int, msg: [*:0]const u8) void {
    const L = G.L orelse return;

    if (std.mem.startsWith(u8, std.mem.span(msg), ".worker-")) {
        _ = join_worker(fd, msg + 8, false);
        return;
    }
    if (std.mem.eql(u8, std.mem.span(msg)[0..9], ".monitor\x00"[0..9]) or
        std.mem.eql(u8, std.mem.span(msg), ".monitor"))
    {
        _ = join_worker(fd, ".monitor", true);
        return;
    }

    if (std.mem.startsWith(u8, std.mem.span(msg), ".reply=")) {
        var source: data_source = std.mem.zeroes(data_source);
        source.fd = fd;
        const id: c_int = @intCast(c.strtoul(msg + 7, null, 10));
        const reg = arcan_map_resource(&source, false);
        _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, id);
        if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
            _ = lua.luaL_error(L, "BUG:request_reply into invalid callback");
            return;
        }
        lua_pushkv_buffer(L, @ptrCast(reg.ptr), @as([*]u8, @ptrCast(reg.ptr)) + reg.sz);
        lua.lua_pushboolean(L, 1);
        arcan_release_map(reg);
        arcan_release_resource(&source);
        lua.lua_call(L, 2, 0);
        lua.luaL_unref(L, lua.LUA_REGISTRYINDEX, id);
    } else {
        log_print("unhandled:{s}", .{msg});
        _ = c.close(fd);
    }
}

// route_bchunk_rep

fn route_bchunk_rep(L: ?*lua.lua_State, ev: *c.struct_arcan_event) void {
    if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv == NS_CLID) {
        const cl_idx: usize = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv);
        const cl = &CLIENTS.cset.?[cl_idx];
        if (cl.shmif) |shmif| {
            _ = shmifsrv_enqueue_event(shmif, ev, ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
        }
        return;
    }

    // NS_NONBLOCK path
    const fd = arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, false);
    if (fd == -1) {
        log_print("kind=error:source=dup:bchunk:message={s}", .{ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message});
        return;
    }

    _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv);
    if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
        _ = lua.luaL_error(L, "BUG:request_reply:bchunk into invalid callback");
        return;
    }

    const mode: c_int = if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind == c.TARGET_COMMAND_BCHUNK_IN) c.O_RDONLY else c.O_RDWR;
    alt_nbio_import(L, fd, mode, null, null);
    lua.lua_call(L, 1, 0);
    lua.luaL_unref(L, lua.LUA_REGISTRYINDEX, ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[3].iv);
}

// handle_message

fn handle_message(L: ?*lua.lua_State, ev: *c.struct_arcan_event) void {
    const msg: [*:0]const u8 = @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message);
    const arr = arg_unpack(msg) orelse {
        _ = c.fprintf(stderr(), "malformed_message: %s\n", msg);
        return;
    };
    defer arg_cleanup(arr);

    var dst: ?[*:0]const u8 = null;
    if (!arg_lookup(arr, "source", 0, &dst)) {
        _ = c.fprintf(stderr(), "unknown_message: %s\n", msg);
        return;
    }

    dst = null;
    _ = arg_lookup(arr, "id", 0, &dst);
    const id: isize = @intCast(c.strtoull(dst orelse "0", null, 10));
    _ = lua.lua_rawgeti(L, lua.LUA_REGISTRYINDEX, @intCast(id));
    if (lua.lua_type(L, -1) != lua.LUA_TFUNCTION) {
        _ = lua.luaL_error(L, "BUG:source_status:invalid callback");
        return;
    }

    var name_ptr: ?[*:0]const u8 = "";
    _ = arg_lookup(arr, "name", 0, &name_ptr);
    _ = lua.lua_pushstring(L, name_ptr orelse "");

    var status_ptr: ?[*:0]const u8 = "";
    _ = arg_lookup(arr, "status", 0, &status_ptr);
    const status = status_ptr orelse "";
    _ = lua.lua_pushstring(L, status);

    lua.lua_call(L, 2, 0);

    if (std.mem.eql(u8, std.mem.span(status), "left")) {
        lua.luaL_unref(L, lua.LUA_REGISTRYINDEX, @intCast(id));
    }
}

// parent_control_event

fn parent_control_event(ev: *c.struct_arcan_event) void {
    if (ev.unnamed_0.unnamed_0.category != c.EVENT_TARGET) return;

    const L = G.L;

    switch (ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind) {
        c.TARGET_COMMAND_BCHUNK_IN => {
            if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv != 0) {
                if (L) |l| route_bchunk_rep(l, ev);
                return;
            }
            const fd = arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, false);
            if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0] != '.') {
                open_appl(fd, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message));
            } else {
                meta_resource(fd, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message));
            }
        },
        c.TARGET_COMMAND_REQFAIL => {
            if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv == NS_CLID) {
                const cl_idx: usize = @intCast(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
                const cl = &CLIENTS.cset.?[cl_idx];
                if (cl.shmif) |shmif| {
                    _ = shmifsrv_enqueue_event(shmif, ev, -1);
                }
            } else if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv == NS_NONBLOCK) {
                if (L) |l| {
                    _ = lua.lua_rawgeti(l, lua.LUA_REGISTRYINDEX, ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
                    if (lua.lua_type(l, -1) != lua.LUA_TFUNCTION) {
                        _ = lua.luaL_error(l, "BUG:request_reply:bchunk into invalid callback");
                        return;
                    }
                    lua.lua_pushnil(l);
                    lua.lua_call(l, 1, 0);
                    lua.luaL_unref(l, lua.LUA_REGISTRYINDEX, ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv);
                }
            }
        },
        c.TARGET_COMMAND_MESSAGE => {
            if (L) |l| handle_message(l, ev);
        },
        c.TARGET_COMMAND_BCHUNK_OUT => {
            if (ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[4].iv != 0) {
                if (L) |l| route_bchunk_rep(l, ev);
                return;
            }
            if (std.mem.eql(u8, std.mem.span(@as([*:0]const u8, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message))), ".log")) {
                const fd = arcan_shmif_dupfd(ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv, -1, true);
                logout = c.fdopen(fd, "w");
                if (logout) |f| c.setlinebuf(f);
                log_print("--- log opened ---", .{});
            }
        },
        c.TARGET_COMMAND_EXIT => {
            G.shutdown = true;
        },
        c.TARGET_COMMAND_STEPFRAME => {},
        else => {},
    }
}

// flush_to_client

fn flush_to_client(cl: *Client) void {
    var out_buf: ?[*]u8 = null;
    const out_sz = dirlua_monitor_flush(&out_buf);
    if (out_sz == 0) return;

    var outev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    outev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_MESSAGE;
    if (cl.shmif) |shmif| {
        _ = shmifsrv_enqueue_multipart_message(shmif, &outev, out_buf.?, out_sz);
    }
    if (dirlua_monitor_getstate()) |state| {
        if (state.out) |out| {
            _ = c.fseek(out, 0, c.SEEK_SET);
        }
    }
}

// monitor_message

fn monitor_message(cl: *Client, ev: *c.struct_arcan_event) void {
    var msg_ptr: ?[*:0]u8 = null;
    var err: c_int = 0;
    if (!anet_directory_merge_multipart(ev, null, @ptrCast(&msg_ptr), &err)) {
        if (err != 0) log_print("monitor:merge_multipart:error={d}", .{err});
        return;
    }
    if (G.L) |L| {
        if (!dirlua_monitor_command(msg_ptr orelse return, L, null)) {
            log_print("monitor:unhandled_cmd={s}", .{msg_ptr orelse ""});
        }
    }
    flush_to_client(cl);
}

// flush_parent

fn flush_parent() void {
    var ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    if (!arcan_shmif_wait(&G.SHMIF, &ev)) {
        G.shutdown = true;
        return;
    }
    parent_control_event(&ev);
    while (arcan_shmif_poll(&G.SHMIF, &ev) > 0) {
        parent_control_event(&ev);
    }
    // rv == -1 means dead connection
    if (arcan_shmif_poll(&G.SHMIF, &ev) == -1) {
        G.shutdown = true;
    }
}

// worker_file_request

fn worker_file_request(cl: *Client, ev: *c.struct_arcan_event) void {
    const L = G.L orelse return;

    var outev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    outev.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    outev.unnamed_0.unnamed_0.unnamed_0.ext.kind = @bitCast(c.EVENT_EXTERNAL_BCHUNKSTATE);
    outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier = @intCast(cl.clid);
    outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.unnamed_0.ns = NS_CLID;

    var reqev: c_int = 0;
    var ntr: c_int = 0;
    G.filereq_handler_ref = -1;

    if (ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input != 0) {
        var ep: c_int = c.EP_TRIGGER_LOAD;
        reqev = c.TARGET_COMMAND_BCHUNK_IN;
        outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.input = 1;
        G.in_filereq_handler = c.O_RDONLY;

        if (std.mem.eql(
            u8,
            ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0..".index".len],
            ".index",
        )) {
            ep = c.EP_TRIGGER_INDEX;
        }

        if (dirlua_setup_entrypoint(L, ep)) {
            lua.lua_pushnumber(L, @floatFromInt(cl.clid));
            msgbuf_utf8(@ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions), ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len);
            _ = lua.lua_pushstring(L, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions));
            dirlua_pcall(L, 2, 1, panic);
            ntr = 1;

            if (lua.lua_type(L, -1) == lua.LUA_TSTRING) {
                const instr: [*:0]const u8 = lua.lua_tolstring(L, -1, null) orelse "";
                _ = std.fmt.bufPrint(
                    outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0..],
                    "{s}",
                    .{instr},
                ) catch {};
            } else if (G.filereq_handler_ref == -1) {
                lua.lua_pop(L, ntr);
                goto_fail(cl, ev);
                return;
            }
        }
    } else if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_STORE)) {
        G.in_filereq_handler = c.O_WRONLY;
        reqev = c.TARGET_COMMAND_BCHUNK_OUT;

        lua.lua_pushnumber(L, @floatFromInt(cl.clid));
        msgbuf_utf8(@ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions), ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions.len);
        _ = lua.lua_pushstring(L, @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions));
        dirlua_pcall(L, 2, 1, panic);
        ntr = 1;

        if (lua.lua_type(L, -1) == lua.LUA_TSTRING) {
            const instr: [*:0]const u8 = lua.lua_tolstring(L, -1, null) orelse "";
            _ = std.fmt.bufPrint(
                outev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.extensions[0..],
                "{s}",
                .{instr},
            ) catch {};
        } else if (G.filereq_handler_ref == -1) {
            lua.lua_pop(L, ntr);
            goto_fail(cl, ev);
            return;
        }
    }

    if (G.filereq_handler_ref != -1) {
        // Script called accept_nonblock — route fd to worker
        var reply_ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
        reply_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
        reply_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = @intCast(reqev);
        reply_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier);
        if (cl.shmif) |shmif| {
            _ = shmifsrv_enqueue_event(shmif, &reply_ev, G.filereq_handler_ref);
        }
        G.in_filereq_handler = 0;
        G.filereq_handler_ref = -1;
        lua.lua_pop(L, ntr);
        return;
    }

    // Relay to parent
    _ = arcan_shmif_enqueue(&G.SHMIF, &outev);
    lua.lua_pop(L, ntr);
    return;
}

fn goto_fail(cl: *Client, ev: *c.struct_arcan_event) void {
    var fail_ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();
    fail_ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_REQFAIL;
    fail_ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = @bitCast(ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.bchunk.identifier);
    if (cl.shmif) |shmif| {
        _ = shmifsrv_enqueue_event(shmif, &fail_ev, -1);
    }
}

// worker_instance_event

fn worker_instance_event(cl: *Client, fd: c_int, revents: c_short) bool {
    _ = revents;
    const L = G.L orelse return false;
    var flush = false;
    var ev: c.struct_arcan_event = c.struct_arcan_event.zeroes();

    while (shmifsrv_dequeue_events(cl.shmif.?, &ev, 1) == 1) {
        flush = true;

        if (!cl.registered) {
            if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_NETSTATE) {
                var out_len: usize = 0;
                const b64 = a12helper_tob64(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.netstate.unnamed_0.unnamed_0.pubk, 32, &out_len);
                const copy_len = @min(out_len, cl.keyid.len - 1);
                @memcpy(cl.keyid[0..copy_len], b64[0..copy_len]);
                cl.keyid[copy_len] = 0;
                log_print("kind=status:worker={d}:registered:key={s}", .{ cl.clid, cl.keyid });
                _ = c.free(b64);
                cl.registered = true;
                if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_JOIN)) {
                    lua.lua_pushnumber(L, @floatFromInt(cl.clid));
                    dirlua_pcall(L, 1, 0, panic);
                }
            } else {
                log_print("kind=error:worker={d}:unregistered_event", .{cl.clid});
            }
            continue;
        }

        if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_BCHUNKSTATE) {
            worker_file_request(cl, &ev);
        } else if (ev.unnamed_0.unnamed_0.unnamed_0.ext.kind == c.EVENT_EXTERNAL_MESSAGE) {
            if (cl.clid == CLIENTS.monitor_slot) {
                monitor_message(cl, &ev);
            } else {
                if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_MESSAGE)) {
                    lua.lua_pushnumber(L, @floatFromInt(cl.clid));
                    lua.lua_newtable(L);
                    const top = lua.lua_gettop(L);
                    tblbool(L, "multipart", ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.multipart != 0, top);
                    msgbuf_utf8(@ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data), ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data.len);
                    tbldynstr(L, "message", @ptrCast(&ev.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data), top);
                    dirlua_pcall(L, 2, 0, panic);
                }
            }
        }
    }

    if (flush) {
        var buf: [256]u8 = undefined;
        _ = c.read(fd, &buf, buf.len);
    }
    return flush;
}

// flush_worker

fn flush_worker(cl: *Client, fd: c_int, revents: c_short, ind: usize) bool {
    if (cl.shmif == null) return false;
    const rv = worker_instance_event(cl, fd, revents);
    if (revents & (c.POLLHUP | c.POLLNVAL) != 0) {
        release_worker(ind);
    }
    return rv;
}

// in_monitor_lock

fn in_monitor_lock() bool {
    const state = dirlua_monitor_getstate() orelse return false;
    return state.lock;
}

// process_nbio_in

fn process_nbio_in(L: ?*lua.lua_State) void {
    if (nbio_jobs.fdin_used == 0) return;

    var fds: [LIMIT_JOBS]c.struct_pollfd = std.mem.zeroes([LIMIT_JOBS]c.struct_pollfd);
    for (0..LIMIT_JOBS) |i| {
        fds[i] = .{
            .fd = nbio_jobs.fdin[i],
            .events = c.POLLIN | c.POLLERR | c.POLLNVAL | c.POLLHUP,
            .revents = 0,
        };
    }

    var sv = c.poll(&fds, LIMIT_JOBS, 0);
    var i: usize = 0;
    while (i < LIMIT_JOBS and sv > 0) : (i += 1) {
        if (fds[i].revents == 0) continue;
        sv -= 1;
        alt_nbio_data_in(L, nbio_jobs.fdin_tags[i]);
    }
}

fn nbio_run_outbound(L: ?*lua.lua_State) void {
    if (nbio_jobs.fdout_used == 0) return;

    var set: [LIMIT_JOBS]isize = std.mem.zeroes([LIMIT_JOBS]isize);
    var count: usize = 0;

    var pv = c.poll(
        @ptrCast(&nbio_jobs.fdout),
        @intCast(nbio_jobs.fdout_used),
        0,
    );
    if (pv > 0) {
        var i: usize = 0;
        while (i < nbio_jobs.fdout_used and pv > 0) : (i += 1) {
            if (nbio_jobs.fdout[i].revents != 0) {
                set[count] = nbio_jobs.fdout_tags[i];
                count += 1;
                pv -= 1;
            }
        }
    }

    for (set[0..count]) |tag| {
        alt_nbio_data_out(L, tag);
    }
}

// anet_directory_appl_runner (main entry point)

pub export fn anet_directory_appl_runner() void {
    logout = stdout();

    var args: ?*c.struct_arg_arr = null;
    G.SHMIF = arcan_shmif_open(c.SEGID_NETWORK_SERVER, shmifopen_flags, @ptrCast(&args));
    shmifsrv_monotonic_rebase();

    // Slot 0 reserved for the shmif pipe
    _ = join_worker(G.SHMIF.epipe, ".main", false);

    var left: c_int = 25;

    while (!G.shutdown) {
        if (in_monitor_lock()) {
            flush_to_client(&CLIENTS.cset.?[CLIENTS.monitor_slot]);

            var pset: [2]c.struct_pollfd = .{
                CLIENTS.pset.?[0],
                CLIENTS.pset.?[CLIENTS.monitor_slot],
            };
            const pv = c.poll(&pset, 2, -1);
            if (pv > 0) {
                if (pset[0].revents != 0) flush_parent();
                if (pset[1].revents != 0) {
                    _ = flush_worker(
                        &CLIENTS.cset.?[CLIENTS.monitor_slot],
                        pset[1].fd,
                        pset[1].revents,
                        CLIENTS.monitor_slot,
                    );
                }
            }
            continue;
        }

        _ = c.poll(CLIENTS.pset.?, @intCast(CLIENTS.set_sz), left);
        const nt = shmifsrv_monotonic_tick(&left);
        if (nt > 0) {
            if (G.L) |L| {
                if (dirlua_setup_entrypoint(L, c.EP_TRIGGER_CLOCK)) {
                    lua.lua_pushnumber(L, @floatFromInt(nt));
                    dirlua_pcall(L, 1, 0, panic);
                }
            }
        }

        if (in_monitor_lock()) continue;

        if (G.L) |L| {
            process_nbio_in(L);
            nbio_run_outbound(L);
        }

        // Process privileged parent inbound events first
        if (CLIENTS.pset.?[0].revents != 0) {
            flush_parent();
        }

        // Flush each worker client
        var i: usize = 1;
        while (i < CLIENTS.set_sz) : (i += 1) {
            if (in_monitor_lock()) continue;
            _ = flush_worker(
                &CLIENTS.cset.?[i],
                CLIENTS.pset.?[i].fd,
                CLIENTS.pset.?[i].revents,
                i,
            );
        }
    }

    if (G.L) |L| {
        lua.lua_close(L);
    }

    log_print("parent_exit", .{});
}
