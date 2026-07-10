// Zig port of nbio.c — non-blocking I/O for TUI Lua bindings
// Assembled from translate-c chunk with @cImport alias layer.

const std = @import("std");

const c = @import("shmif_types");

// Type aliases
const lua_State = c.lua_State;
const lua_Number = c.lua_Number;
const lua_Integer = c.lua_Integer;
const mode_t = c.mode_t;
const off_t = c.off_t;
const sa_family_t = c.sa_family_t;
const pid_t = c.pid_t;
const socklen_t = c.socklen_t;
const struct_nonblock_io = c.struct_nonblock_io;
const struct_io_job = c.struct_io_job;
const struct_pollfd = c.struct_pollfd;
const struct_stat = c.struct_stat;
const struct_sockaddr_un = c.struct_sockaddr_un;

// Socket address portability helpers
// glibc wraps sockaddr pointers in __CONST_SOCKADDR_ARG / __SOCKADDR_ARG union types,
// while musl (and other libcs) use plain pointers. These helpers abstract the difference.
const ConstSockaddrArg = if (@hasDecl(c, "__CONST_SOCKADDR_ARG")) c.__CONST_SOCKADDR_ARG else [*c]const c.struct_sockaddr;
const SockaddrArg = if (@hasDecl(c, "__SOCKADDR_ARG")) c.__SOCKADDR_ARG else [*c]c.struct_sockaddr;

fn constSockaddrCast(ptr: anytype) ConstSockaddrArg {
    if (@hasDecl(c, "__CONST_SOCKADDR_ARG")) {
        return .{ .__sockaddr__ = @ptrCast(@alignCast(ptr)) };
    } else {
        return @ptrCast(@alignCast(ptr));
    }
}

fn sockaddrCast(ptr: anytype) SockaddrArg {
    if (@hasDecl(c, "__SOCKADDR_ARG")) {
        return .{ .__sockaddr__ = @ptrCast(@alignCast(ptr)) };
    } else {
        return @ptrCast(@alignCast(ptr));
    }
}

fn nullSockaddrArg() SockaddrArg {
    if (@hasDecl(c, "__SOCKADDR_ARG")) {
        return .{ .__sockaddr__ = @ptrFromInt(@as(usize, 0)) };
    } else {
        return @ptrFromInt(@as(usize, 0));
    }
}

// Lua function aliases
const lua_call = c.lua_call;
const lua_error = c.lua_error;
const lua_getfield = c.lua_getfield;
const lua_isnumber = c.lua_isnumber;
const luaL_argerror = c.luaL_argerror;
const luaL_checklstring = c.luaL_checklstring;
const luaL_checkudata = c.luaL_checkudata;
const luaL_newmetatable = c.luaL_newmetatable;
const luaL_optnumber = c.luaL_optnumber;
const luaL_ref = c.luaL_ref;
const luaL_unref = c.luaL_unref;
const lua_newuserdata = c.lua_newuserdata;
const lua_objlen = c.lua_objlen;
const lua_pushboolean = c.lua_pushboolean;
const lua_pushcclosure = c.lua_pushcclosure;
const lua_pushinteger = c.lua_pushinteger;
const lua_pushlstring = c.lua_pushlstring;
const lua_pushnil = c.lua_pushnil;
const lua_pushnumber = c.lua_pushnumber;
const lua_pushvalue = c.lua_pushvalue;
const lua_rawgeti = c.lua_rawgeti;
const lua_rawset = c.lua_rawset;
const lua_setfield = c.lua_setfield;
const lua_setmetatable = c.lua_setmetatable;
const lua_settop = c.lua_settop;
const lua_toboolean = c.lua_toboolean;
const lua_tolstring = c.lua_tolstring;
const lua_tonumber = c.lua_tonumber;
const lua_type = c.lua_type;

// C lib function aliases
const accept = c.accept;
const bind = c.bind;
const close = c.close;
const connect = c.connect;
const fchmod = c.fchmod;
const fcntl = c.fcntl;
const free = c.free;
const fstat = c.fstat;
const listen = c.listen;
const lseek = c.lseek;
const malloc = c.malloc;
const memcpy = c.memcpy;
const memmove = c.memmove;
const memset = c.memset;
const open = c.open;
const poll = c.poll;
const read = c.read;
const socket = c.socket;
const stat = c.stat;
const strdup = c.strdup;
const strlen = c.strlen;
const unlink = c.unlink;
const write = c.write;
const stderr = c.stderr;
const __errno_location = c.__errno_location;
const __ctype_b_loc = c.__ctype_b_loc;
const O_RDONLY = c.O_RDONLY;
const O_WRONLY = c.O_WRONLY;
const O_RDWR = c.O_RDWR;
const O_CREAT = c.O_CREAT;
const O_TRUNC = c.O_TRUNC;
const O_APPEND = c.O_APPEND;
const O_NONBLOCK = c.O_NONBLOCK;
const O_CLOEXEC = c.O_CLOEXEC;
const POLLIN = c.POLLIN;
const POLLHUP = c.POLLHUP;
const POLLERR = c.POLLERR;
const SOCK_STREAM = c.SOCK_STREAM;
const SOCK_DGRAM = c.SOCK_DGRAM;
const AF_UNIX = c.AF_UNIX;
const SEEK_SET = c.SEEK_SET;
const SEEK_CUR = c.SEEK_CUR;
const SEEK_END = c.SEEK_END;
const S_IRUSR = c.S_IRUSR;
const S_IWUSR = c.S_IWUSR;
const S_IRGRP = c.S_IRGRP;
const S_IWGRP = c.S_IWGRP;
const F_GETFL = c.F_GETFL;
const F_SETFL = c.F_SETFL;
const F_GETFD = c.F_GETFD;
const F_SETFD = c.F_SETFD;
const FD_CLOEXEC = c.FD_CLOEXEC;
const EINTR = c.EINTR;
const EAGAIN = c.EAGAIN;

// Varargs C functions
extern "c" fn fprintf(stream: *anyopaque, fmt: [*c]const u8, ...) c_int;
extern "c" fn snprintf(buf: [*c]u8, size: usize, fmt: [*c]const u8, ...) c_int;

// Stub functions from nbio_local.h
const ARCAN_MEM_BZERO: c_int = 1;
const RESOURCE_APPL_TEMP: c_int = 1;
const RESOURCE_NS_USER: c_int = 2;
const ARES_FILE: c_int = 1;
const ARES_CREATE: c_int = 256;
const DEFAULT_USERMASK: c_int = 2;
const CB_SOURCE_NONE: c_int = 0;

fn arcan_mem_free(f: ?*anyopaque) void {
    c.free(f);
}

fn arcan_alloc_mem(sz: usize, type_: c_int, hint: c_int, alignment: c_int) ?*anyopaque {
    _ = type_;
    _ = alignment;
    const res = c.malloc(sz);
    if (res != null and (hint & ARCAN_MEM_BZERO) != 0) {
        _ = c.memset(res.?, 0, sz);
    }
    return res;
}

fn alt_call(L: ?*lua_State, kind: c_int, kind_tag: usize, args: c_int, retc: c_int, src: [*c]const u8) void {
    _ = kind;
    _ = kind_tag;
    _ = src;
    c.lua_call(L, args, retc);
}

fn arcan_expand_resource(prefix: [*c]const u8, ns: c_int) [*c]u8 {
    _ = ns;
    return if (prefix != null) c.strdup(prefix) else null;
}

fn arcan_find_resource(prefix: [*c]const u8, ns: c_int, kind: c_int, dfd: [*c]c_int) [*c]u8 {
    _ = kind;
    const res: [*c]u8 = arcan_expand_resource(prefix, ns);
    if (res == null) return null;

    const fd = c.open(res, c.O_RDONLY);
    if (fd == -1) {
        if (dfd != null) dfd.* = -1;
        return null;
    }

    const expanded: [*c]u8 = c.realpath(res, null);
    c.free(@as(?*anyopaque, @ptrCast(res)));

    if (dfd != null)
        dfd.* = fd
    else
        _ = c.close(fd);

    return expanded;
}

// arcan_warning — simple stderr print in TUI Lua context
pub fn arcan_warning(msg: [*c]const u8) callconv(.c) void {
    _ = fprintf(@ptrCast(stderr), "%s", msg);
}

pub extern "c" fn arcan_timemillis() c_ulonglong;
pub extern "c" fn arcan_random(dst: [*c]u8, sz: usize) void;
pub extern "c" fn getpid() pid_t;

// End of header, function implementations follow

pub export fn alt_nbio_register(L: ?*lua_State, add: ?*const fn (c_int, mode_t, isize) callconv(.c) bool, remove_1: ?*const fn (c_int, mode_t, [*c]isize) callconv(.c) bool, @"error": ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void) void {
    add_job = add;
    remove_job = remove_1;
    trigger_error = @"error";
    _ = luaL_newmetatable(L, "nonblockIO");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pushcclosure(L, &nbio_read, 0);
    lua_setfield(L, -2, "read");
    lua_pushcclosure(L, &nbio_write, 0);
    lua_setfield(L, -2, "write");
    lua_pushcclosure(L, &nbio_closer, 0);
    lua_setfield(L, -2, "__gc");
    lua_pushcclosure(L, &nbio_writequeue, 0);
    lua_setfield(L, -2, "outqueue");
    lua_pushcclosure(L, &nbio_datahandler, 0);
    lua_setfield(L, -2, "data_handler");
    lua_pushcclosure(L, &nbio_closer, 0);
    lua_setfield(L, -2, "close");
    lua_pushcclosure(L, &nbio_seek, 0);
    lua_setfield(L, -2, "seek");
    lua_pushcclosure(L, &nbio_position, 0);
    lua_setfield(L, -2, "set_position");
    lua_pushcclosure(L, &nbio_flush, 0);
    lua_setfield(L, -2, "flush");
    lua_pushcclosure(L, &nbio_lf, 0);
    lua_setfield(L, -2, "lf_strip");
    lua_settop(L, -1 - 1);
    _ = luaL_newmetatable(L, "nonblockIOs");
    lua_pushvalue(L, -1);
    lua_setfield(L, -2, "__index");
    lua_pushcclosure(L, &nbio_socketaccept, 0);
    lua_setfield(L, -2, "accept");
    lua_pushcclosure(L, &nbio_socketclose, 0);
    lua_setfield(L, -2, "close");
    lua_pushcclosure(L, &nbio_socketclose, 0);
    lua_setfield(L, -2, "_gc");
    lua_settop(L, -1 - 1);
}

pub export fn alt_nbio_process_read(L: ?*lua_State, ib: [*c]struct_nonblock_io, nonbuffered: bool) c_int {
    const buf_sz: usize = @sizeOf([4096]u8) / @sizeOf(u8);
    var ch: [*c]u8 = null;
    var len: usize = 0;
    var step: usize = 0;
    if (!(ib != null) or (ib.*.fd < 0)) return 0;
    var eof: bool = false;
    const uofs: usize = if (ib.*.ofs >= 0) @as(usize, @intCast(ib.*.ofs)) else 0;
    const nr: isize = if (uofs >= buf_sz) 0 else read(ib.*.fd, @as(?*anyopaque, @ptrCast(&ib.*.buf[uofs])), buf_sz - uofs);
    if (0 == nr) {
        eof = true;
    } else if (-1 == nr) {
        if ((__errno_location().* == 11) or (__errno_location().* == 4)) {
            if (!(ib.*.ofs != 0)) {
                lua_pushnil(L);
                lua_pushboolean(L, 1);
                if (!(ib.*.ofs != 0)) return 2;
            }
        } else {
            eof = true;
        }
    } else {
        ib.*.ofs += @as(off_t, @bitCast(nr));
    }
    if (nonbuffered) {
        if (ib.*.ofs != 0) {
            lua_pushlstring(L, @ptrCast(&ib.*.buf[0]), @as(usize, @bitCast(ib.*.ofs)));
        } else {
            lua_pushnil(L);
        }
        lua_pushboolean(L, @intFromBool(!eof or (ib.*.ofs != 0)));
        ib.*.ofs = 0;
        return 2;
    }
    var gotline: bool = undefined;
    if (lua_type(L, -1) == 6) {
        var ci: usize = 0;
        var cancel: bool = false;
        while (!cancel and ((blk: {
            const tmp = nextline(ib, ci, eof, &len, &step, &gotline, ib.*.lfch);
            ch = tmp;
            break :blk tmp;
        }) != null)) {
            lua_pushvalue(L, -1);
            lua_pushlstring(L, ch, len);
            lua_pushboolean(L, @intFromBool((@as(c_int, @intFromBool(eof)) != 0) and !gotline));
            ci +%= step;
            alt_call(L, 0, 0, 2, 1, "839:read_cb");
            cancel = (lua_toboolean(L, -1) != 0) or (@as(usize, @bitCast(ib.*.ofs)) <= ci);
            lua_settop(L, -1 - 1);
        }
        if (ci <= @as(usize, @bitCast(ib.*.ofs))) {
            _ = memmove(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(&ib.*.buf[0])))), @as(?*const anyopaque, @ptrCast(&ib.*.buf[ci])), @as(usize, @bitCast(ib.*.ofs)) -% ci);
            ib.*.ofs -= @as(off_t, @bitCast(ci));
        }
        lua_pushnil(L);
        lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else if (lua_type(L, -1) == 5) {
        var ind: usize = lua_objlen(L, -1) +% 1;
        var ci: usize = 0;
        lua_getfield(L, -1, "read_cap");
        var count: usize = @intFromFloat(lua_tonumber(L, -1));
        if (!(count != 0)) {
            count = @as(usize, @bitCast(@as(isize, -1)));
        }
        lua_settop(L, -1 - 1);
        while ((blk: {
            _ = (count != 0) and (ci < @as(usize, @bitCast(ib.*.ofs)));
            break :blk blk_1: {
                const tmp = nextline(ib, ci, eof, &len, &step, &gotline, ib.*.lfch);
                ch = tmp;
                break :blk_1 tmp;
            };
        }) != null) {
            if ((@as(c_int, @intFromBool(eof)) != 0) and (len == 0) and (step == 0)) break;
            lua_pushinteger(L, @as(lua_Integer, @bitCast(blk: {
                const ref = &ind;
                const tmp = ref.*;
                ref.* +%= 1;
                break :blk tmp;
            })));
            lua_pushlstring(L, ch, len);
            lua_rawset(L, -3);
            count -%= 1;
            ci +%= step;
        }
        if (ci <= @as(usize, @bitCast(ib.*.ofs))) {
            _ = memmove(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(&ib.*.buf[0])))), @as(?*const anyopaque, @ptrCast(&ib.*.buf[ci])), @as(usize, @bitCast(ib.*.ofs)) -% ci);
            ib.*.ofs -= @as(off_t, @bitCast(ci));
        }
        lua_pushnil(L);
        lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    } else {
        if ((blk: {
            const tmp = nextline(ib, 0, eof, &len, &step, &gotline, ib.*.lfch);
            ch = tmp;
            break :blk tmp;
        }) != null) {
            lua_pushlstring(L, ch, len);
            if (step < @as(usize, @bitCast(ib.*.ofs))) {
                _ = memmove(@as(?*anyopaque, @ptrCast(@as([*c]u8, @ptrCast(&ib.*.buf[0])))), @as(?*const anyopaque, @ptrCast(&ib.*.buf[step])), buf_sz -% step);
                ib.*.ofs -= @as(off_t, @bitCast(step));
            } else {
                ib.*.ofs = 0;
            }
        } else {
            lua_pushnil(L);
        }
        lua_pushboolean(L, @intFromBool(!eof));
        return 2;
    }
    return 0;
}

pub const struct_pathfd = extern struct {
    path: [*c]u8 = std.mem.zeroes([*c]u8),
    unlink: [*c]u8 = std.mem.zeroes([*c]u8),
    err: [*c]const u8 = std.mem.zeroes([*c]const u8),
    metatable: [*c]const u8 = std.mem.zeroes([*c]const u8),
    fd: c_int = std.mem.zeroes(c_int),
    wrmode: c_int = std.mem.zeroes(c_int),
};

pub export fn alt_nbio_open(L: ?*lua_State) c_int {
    var pfd: struct_pathfd = undefined;
    const wrmode: c_int = if (luaL_optbnumber(L, 2, 0) != 0) @as(c_int, 1) else @as(c_int, 0);
    var userns: bool = false;
    const str: [*c]u8 = strdup(luaL_checklstring(L, 1, null));
    var i: usize = 0;
    while (str[i] != 0 and (c.isalnum(str[i]) != 0)) : (i +%= 1) {}
    if ((@as(c_int, @bitCast(@as(c_uint, str[i]))) == ':') and (@as(c_int, @bitCast(@as(c_uint, str[i +% 1]))) == '/')) {
        userns = true;
    }
    if (@as(c_int, @bitCast(@as(c_uint, str[0]))) == '<') {
        pfd = build_fifo_ipc(str + @as(usize, @bitCast(@as(isize, 1))), userns, wrmode == 1);
    } else if (@as(c_int, @bitCast(@as(c_uint, str[0]))) == '=') {
        pfd = build_socket_ipc(str + @as(usize, @bitCast(@as(isize, 1))), userns, wrmode != 1);
    } else if (wrmode == 1) {
        pfd = build_new_file(str, userns);
    } else {
        pfd = open_existing_file(str, userns);
    }
    free(@as(?*anyopaque, @ptrCast(str)));
    if (pfd.err != null) {
        return 0;
    }
    const conn: [*c]struct_nonblock_io = @ptrCast(@alignCast(arcan_alloc_mem(@sizeOf(struct_nonblock_io), 0, 1, 0)));
    conn.*.fd = pfd.fd;
    conn.*.lfch = '\n';
    alt_nbio_nonblock_cloexec(pfd.fd, true);
    conn.*.mode = @as(mode_t, @bitCast(pfd.wrmode));
    conn.*.pending = pfd.path;
    conn.*.unlink_fn = pfd.unlink;
    conn.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
    conn.*.write_handler = @as(isize, @bitCast(@as(isize, -2)));
    const dp: [*c]usize = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(usize))));
    dp.* = @intFromPtr(conn);
    _ = lua_getfield(L, -1001000, pfd.metatable);
    _ = lua_setmetatable(L, -2);
    return 1;
}

pub export fn alt_nbio_nonblock_cloexec(fd: c_int, socket_1: bool) void {
    _ = socket_1;
    var flags: c_int = fcntl(fd, 3);
    if (-1 != flags) {
        _ = fcntl(fd, 4, flags | 2048);
    }
    if (-1 != (blk: {
        const tmp = fcntl(fd, 1);
        flags = tmp;
        break :blk tmp;
    })) {
        _ = fcntl(fd, 2, flags | 1);
    }
}

pub export fn alt_nbio_socket(path: [*c]const u8, ns: c_int, out: [*c][*c]u8) c_int {
    var local_path: [*c]u8 = null;
    var retry: c_int = 3;
    while (true) {
        var tmpname: [32]u8 = undefined;
        var rnd: u32 = undefined;
        arcan_random(@ptrCast(@alignCast(&rnd)), 4);
        _ = snprintf(@ptrCast(&tmpname[0]), @sizeOf([32]u8), "/tmp/_sock%u_%d", rnd, getpid());
        const tmppath: [*c]u8 = arcan_find_resource(@ptrCast(&tmpname[0]), ns, 1, null);
        if (!(tmppath != null)) {
            local_path = arcan_expand_resource(@ptrCast(&tmpname[0]), ns);
        } else {
            free(@as(?*anyopaque, @ptrCast(tmppath)));
        }
        if (!(!(local_path != null) and ((blk: {
            const ref = &retry;
            const tmp = ref.*;
            ref.* -= 1;
            break :blk tmp;
        }) != 0))) break;
    }
    if (!(local_path != null)) return -1;
    var fd: c_int = connect_trypath(local_path, path, SOCK_STREAM);
    if (-1 == fd) {
        if (__errno_location().* == 91) {
            fd = connect_trypath(local_path, path, SOCK_DGRAM);
        }
        if (-1 == fd) {
            _ = unlink(local_path);
            arcan_mem_free(@as(?*anyopaque, @ptrCast(local_path)));
        } else {
            out.* = local_path;
        }
    } else {
        _ = unlink(local_path);
        arcan_mem_free(@as(?*anyopaque, @ptrCast(local_path)));
    }
    return fd;
}

pub export fn alt_nbio_process_write(_: ?*lua_State, ib: [*c]struct_nonblock_io) c_int {
    var job: [*c]struct_io_job = ib.*.out_queue;
    while (job != null) {
        const nw: isize = write(ib.*.fd, @as(?*const anyopaque, @ptrCast(&job.*.buf[job.*.ofs])), job.*.buf_sz -% job.*.ofs);
        if (-1 == nw) {
            if ((__errno_location().* == 4) or (__errno_location().* == 11)) return 0;
            return -1;
        }
        job.*.ofs +%= @as(usize, @bitCast(nw));
        ib.*.out_count +%= @as(usize, @bitCast(nw));
        if (job.*.ofs == job.*.buf_sz) {
            ib.*.out_queued -%= job.*.buf_sz;
            ib.*.out_queue = job.*.next;
            arcan_mem_free(@as(?*anyopaque, @ptrCast(job.*.buf)));
            arcan_mem_free(@as(?*anyopaque, @ptrCast(job)));
            job = ib.*.out_queue;
            if (!(job != null)) {
                ib.*.out_queue_tail = &ib.*.out_queue;
            }
        }
    }
    return 1;
}

pub export fn alt_nbio_data_in(L: ?*lua_State, tag_arg: isize) void {
    var tag = tag_arg;
    if (!lookup_registry(L, tag, 7, "data-in")) return;
    const ibb: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, -1, "nonblockIO")));
    const ib: [*c]struct_nonblock_io = ibb.*;
    if (!(ib != null)) return;
    lua_settop(L, -1 - 1);
    if (!lookup_registry(L, ib.*.data_handler, 6, "data-in-dh")) return;
    const ch: isize = ib.*.data_handler;
    ib.*.data_rearmed = false;
    lua_pushboolean(L, 0);
    alt_call(L, 0, 0, 1, 1, "1400:data_handler_cb");
    if (ib.*.data_rearmed) {} else if ((lua_type(L, -1) == 1) and (lua_toboolean(L, -1) != 0)) {} else {
        unref_registry(L, ch, 6, "data-in-dontwant");
        ib.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
        if (remove_job.?(ib.*.fd, @as(mode_t, @bitCast(@as(c_int, 0))), &tag)) {
            unref_registry(L, tag, 7, "data-in-meta-dontwant");
        }
    }
    lua_settop(L, -1 - 1);
}

pub export fn alt_nbio_data_out(L: ?*lua_State, tag_arg: isize) void {
    var tag = tag_arg;
    if (!lookup_registry(L, tag, 7, "data-out")) return;
    const ibb: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, -1, "nonblockIO")));
    const ib: [*c]struct_nonblock_io = ibb.*;
    lua_settop(L, -1 - 1);
    if (!(ib.*.out_queue != null)) return;
    const status: c_int = alt_nbio_process_write(L, ib);
    if (status == 0) return;
    if (ib.*.write_handler == @as(isize, @bitCast(@as(isize, -2)))) {
        drop_all_jobs(ib);
        return;
    }
    if (!lookup_registry(L, ib.*.write_handler, 6, "data-out-wh")) return;
    lua_pushboolean(L, @intFromBool(status == 1));
    lua_pushboolean(L, 0);
    drop_all_jobs(ib);
    alt_call(L, 0, 0, 2, 0, "1366:write_handler_cb");
    if (!(ib.*.out_queue != null)) {
        if (remove_job.?(ib.*.fd, @as(mode_t, @bitCast(@as(c_int, 1))), &tag)) {
            unref_registry(L, tag, 7, "nbio-open-wrmeta");
        }
    }
}

pub export fn alt_nbio_release() void {
    {
        var i: usize = 0;
        while (i < 64) : (i +%= 1) {
            const ent: [*c]struct_nonblock_io = &open_fds[i];
            if (ent.*.fd > 0) {
                _ = remove_job.?(ent.*.fd, @as(mode_t, @bitCast(@as(c_int, 0))), null);
                _ = remove_job.?(ent.*.fd, @as(mode_t, @bitCast(@as(c_int, 1))), null);
                _ = close(ent.*.fd);
            }
            drop_all_jobs(ent);
            open_fds[i] = std.mem.zeroes(struct_nonblock_io);
            open_fds[i].data_handler = @as(isize, @bitCast(@as(isize, -2)));
            open_fds[i].write_handler = @as(isize, @bitCast(@as(isize, -2)));
        }
    }
}

pub export fn alt_nbio_import(L: ?*lua_State, fd: c_int, mode: mode_t, out: [*c][*c]struct_nonblock_io, unlink_fn: [*c][*c]u8) bool {
    if (-1 == fd) {
        lua_pushnil(L);
        return false;
    }
    if (out != null) {
        out.* = null;
    }
    const nbio: [*c]struct_nonblock_io = @ptrCast(@alignCast(malloc(@sizeOf(struct_nonblock_io))));
    if (!(nbio != null)) {
        _ = close(fd);
        lua_pushnil(L);
        return false;
    }
    const dp: [*c]usize = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf([*c]usize))));
    if (!(dp != null)) {
        _ = close(fd);
        free(@as(?*anyopaque, @ptrCast(nbio)));
        lua_pushnil(L);
        return false;
    }
    dp.* = @intFromPtr(nbio);
    nbio.* = std.mem.zeroes(struct_nonblock_io);
    nbio.*.lfch = '\n';
    nbio.*.fd = fd;
    nbio.*.mode = mode;
    nbio.*.unlink_fn = if (unlink_fn != null) unlink_fn.* else null;
    nbio.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
    nbio.*.write_handler = @as(isize, @bitCast(@as(isize, -2)));
    if (out != null) {
        out.* = nbio;
    }
    alt_nbio_nonblock_cloexec(fd, false);
    _ = lua_getfield(L, -1001000, "nonblockIO");
    _ = lua_setmetatable(L, -2);
    return true;
}

pub export fn alt_nbio_close(L: ?*lua_State, ibb: [*c][*c]struct_nonblock_io) c_int {
    const ib: [*c]struct_nonblock_io = ibb.*;
    const fd: c_int = ib.*.fd;
    if (fd > 0) {
        _ = close(fd);
    }
    if (ib.*.unlink_fn != null) {
        _ = unlink(ib.*.unlink_fn);
        arcan_mem_free(@as(?*anyopaque, @ptrCast(ib.*.unlink_fn)));
    }
    free(@as(?*anyopaque, @ptrCast(ib.*.pending)));
    drop_all_jobs(ib);
    if (ib.*.data_handler != @as(isize, @bitCast(@as(isize, -2)))) {
        unref_registry(L, ib.*.data_handler, 6, "nbio_close_dh");
        ib.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
    }
    if (ib.*.write_handler != @as(isize, @bitCast(@as(isize, -2)))) {
        unref_registry(L, ib.*.write_handler, 6, "nbio_close_wh");
        ib.*.write_handler = @as(isize, @bitCast(@as(isize, -2)));
    }
    var tag: isize = undefined;
    if (remove_job.?(fd, @as(mode_t, @bitCast(@as(c_int, 0))), &tag)) {
        unref_registry(L, tag, 7, "nbio_close_rdmeta");
    }
    if (remove_job.?(fd, @as(mode_t, @bitCast(@as(c_int, 1))), &tag)) {
        unref_registry(L, tag, 7, "nbio_close_wrmeta");
    }
    free(@as(?*anyopaque, @ptrCast(ib)));
    ibb.* = null;
    {
        var i: usize = 0;
        while (i < 64) : (i +%= 1) {
            if (open_fds[i].fd == fd) {
                open_fds[i] = std.mem.zeroes(struct_nonblock_io);
                open_fds[i].data_handler = @as(isize, @bitCast(@as(isize, -2)));
                open_fds[i].write_handler = @as(isize, @bitCast(@as(isize, -2)));
                break;
            }
        }
    }
    return 0;
}

// (arcan_mem_free, arcan_alloc_mem, alt_call, arcan_expand_resource,
//  arcan_find_resource, arcan_warning, arcan_random — provided by header)

pub var open_fds: [64]struct_nonblock_io = std.mem.zeroes([64]struct_nonblock_io);
pub var add_job: ?*const fn (c_int, mode_t, isize) callconv(.c) bool = std.mem.zeroes(?*const fn (c_int, mode_t, isize) callconv(.c) bool);
pub var remove_job: ?*const fn (c_int, mode_t, [*c]isize) callconv(.c) bool = std.mem.zeroes(?*const fn (c_int, mode_t, [*c]isize) callconv(.c) bool);
pub var trigger_error: ?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void = std.mem.zeroes(?*const fn (?*lua_State, c_int, isize, [*c]const u8) callconv(.c) void);

pub fn lookup_registry(L: ?*lua_State, tag: isize, @"type": c_int, src: [*c]const u8) callconv(.c) bool {
    lua_rawgeti(L, -1001000, @as(c_int, @truncate(tag)));
    if (lua_type(L, -1) != @"type") {
        trigger_error.?(L, -1, tag, src);
        lua_settop(L, -1 - 1);
        return false;
    }
    return true;
}

pub fn unref_registry(L: ?*lua_State, tag: isize, @"type": c_int, src: [*c]const u8) callconv(.c) void {
    _ = @"type";
    _ = src;
    luaL_unref(L, -1001000, @as(c_int, @truncate(tag)));
}

pub fn ensure_flush(L: ?*lua_State, ib: [*c]struct_nonblock_io, timeout_arg: usize) callconv(.c) bool {
    var timeout = timeout_arg;
    var rv: bool = true;
    var fd: struct_pollfd = struct_pollfd{
        .fd = ib.*.fd,
        .events = @as(c_short, @bitCast(@as(c_short, @truncate(((@as(c_int, 4) | @as(c_int, 8)) | @as(c_int, 16)) | @as(c_int, 32))))),
        .revents = 0,
    };
    var current: c_ulonglong = arcan_timemillis();
    var status: c_int = undefined;
    while ((blk: {
        const tmp = alt_nbio_process_write(L, ib);
        status = tmp;
        break :blk tmp;
    }) == 0) {
        if (timeout > 0) {
            const now: c_ulonglong = arcan_timemillis();
            if (now > current) {
                timeout -%= @as(usize, @bitCast(@as(usize, @truncate(now -% current))));
            }
            current = now;
            if (timeout <= 0) {
                rv = false;
                break;
            }
        }
        var rv_1: c_int = poll(&fd, 1, @as(c_int, @bitCast(@as(c_uint, @truncate(timeout)))));
        if ((-1 == rv_1) and ((__errno_location().* == 11) or (__errno_location().* == 4))) continue;
        if ((@as(c_int, @bitCast(@as(c_int, fd.revents))) & ((@as(c_int, 8) | @as(c_int, 16)) | @as(c_int, 32))) != 0) {
            rv_1 = 0;
            break;
        }
    }
    if (status < 0) {
        rv = false;
    }
    return rv;
}

pub fn connect_trypath(local: [*c]const u8, remote: [*c]const u8, @"type": c_int) callconv(.c) c_int {
    const fd: c_int = socket(1, @"type", 0);
    if (-1 == fd) return fd;
    var addr_local: struct_sockaddr_un = .{ .sun_family = 1 }; // AF_UNIX
    _ = snprintf(@ptrCast(&addr_local.sun_path[0]), @sizeOf(@TypeOf(addr_local.sun_path)), "%s", local);
    var addr_remote: struct_sockaddr_un = .{ .sun_family = 1 }; // AF_UNIX
    _ = snprintf(@ptrCast(&addr_remote.sun_path[0]), @sizeOf(@TypeOf(addr_remote.sun_path)), "%s", remote);
    const rv: c_int = c.bind(fd, constSockaddrCast(&addr_local), @as(socklen_t, @bitCast(@as(c_uint, @truncate(@sizeOf(struct_sockaddr_un))))));
    if (-1 == rv) {
        _ = close(fd);
        return -1;
    }
    alt_nbio_nonblock_cloexec(fd, true);
    if (-1 == c.connect(fd, constSockaddrCast(&addr_remote), @as(socklen_t, @bitCast(@as(c_uint, @truncate(@sizeOf(struct_sockaddr_un))))))) {
        _ = unlink(local);
        _ = close(fd);
        return -1;
    }
    return fd;
}

pub fn drop_all_jobs(ib: [*c]struct_nonblock_io) callconv(.c) void {
    var job: [*c]struct_io_job = ib.*.out_queue;
    while (job != null) {
        const cur: [*c]struct_io_job = job;
        job = job.*.next;
        arcan_mem_free(@as(?*anyopaque, @ptrCast(cur.*.buf)));
        arcan_mem_free(@as(?*anyopaque, @ptrCast(cur)));
    }
    ib.*.out_queue = null;
    ib.*.out_queue_tail = &ib.*.out_queue;
    ib.*.out_queued = 0;
    ib.*.out_count = 0;
}

pub fn queue_out(ib: [*c]struct_nonblock_io, buf: [*c]const u8, len_arg: usize, suffix: [*c]const u8, suffix_len: usize) callconv(.c) [*c]struct_io_job {
    var len = len_arg;
    if ((suffix_len +% len) < len) return null;
    const res: [*c]struct_io_job = @ptrCast(@alignCast(malloc(@sizeOf(struct_io_job))));
    if (!(res != null)) return null;
    res.* = struct_io_job{
        .buf = null,
        .buf_sz = 0,
        .ofs = 0,
        .next = null,
    };
    res.*.buf = @ptrCast(@alignCast(malloc(len +% suffix_len)));
    if (!(res.*.buf != null)) {
        free(@as(?*anyopaque, @ptrCast(res)));
        return null;
    }
    _ = memcpy(@as(?*anyopaque, @ptrCast(res.*.buf)), @as(?*const anyopaque, @ptrCast(buf)), len);
    if (suffix_len != 0) {
        _ = memcpy(@as(?*anyopaque, @ptrCast(&res.*.buf[len])), @as(?*const anyopaque, @ptrCast(suffix)), suffix_len);
        len +%= suffix_len;
    }
    res.*.buf_sz = len;
    ib.*.out_queued +%= len;
    if (!(ib.*.out_queue_tail != null)) {
        ib.*.out_queue_tail = &ib.*.out_queue;
    }
    ib.*.out_queue_tail.?.* = res;
    ib.*.out_queue_tail = &res.*.next;
    return res;
}

pub fn nbio_closer(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    if (!(ib.* != null)) {
        return 0;
    }
    _ = ensure_flush(L, ib.*, 1000);
    _ = alt_nbio_close(L, ib);
    return 0;
}

pub fn nbio_datahandler(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    if (!(ib.* != null)) {
        return 0;
    }
    if (ib.*.*.data_handler != @as(isize, @bitCast(@as(isize, -2)))) {
        unref_registry(L, ib.*.*.data_handler, 6, "nbio-dh-reset");
        ib.*.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
    }
    ib.*.*.data_rearmed = true;
    var out: isize = undefined;
    if (remove_job.?(ib.*.*.fd, @as(mode_t, @bitCast(@as(c_int, 0))), &out)) {
        unref_registry(L, out, 7, "nbio-rdonly-meta-reset");
    }
    if (lua_type(L, 2) == 6) {
        var ref: isize = @as(isize, @bitCast(@as(isize, luaL_ref(L, -1001000))));
        ib.*.*.data_handler = ref;
        ref = @as(isize, @bitCast(@as(isize, luaL_ref(L, -1001000))));
        lua_pushvalue(L, 1);
        lua_pushvalue(L, 1);
        if (!add_job.?(ib.*.*.fd, @as(mode_t, @bitCast(@as(c_int, 0))), ref)) {
            unref_registry(L, ref, 7, "nbio-rdonly-meta-fail");
            lua_pushboolean(L, 0);
        }
        lua_pushboolean(L, 1);
        return 1;
    } else if (lua_type(L, 2) == 0) {} else {
        while (true) {
            lua_pushlstring(L, "open_nonblock:data_handler argument error, expected function or nil", @sizeOf([68]u8) - 1);
            _ = lua_error(L);
            if (!false) break;
        }
    }
    lua_pushboolean(L, 1);
    return 1;
}

pub fn nbio_socketclose(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIOs")));
    if (!(ib.* != null)) {
        return 0;
    }
    _ = alt_nbio_close(L, ib);
    return 0;
}

pub fn nbio_socketaccept(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIOs")));
    if (!(ib.* != null)) {
        return 0;
    }
    const is: [*c]struct_nonblock_io = ib.*;
    const newfd: c_int = c.accept(is.*.fd, nullSockaddrArg(), null);
    if (-1 == newfd) {
        return 0;
    }
    var flags: c_int = fcntl(newfd, 3);
    if (-1 != flags) {
        _ = fcntl(newfd, 4, flags | 2048);
    }
    if (-1 != (blk: {
        const tmp = fcntl(newfd, 1);
        flags = tmp;
        break :blk tmp;
    })) {
        _ = fcntl(newfd, 2, flags | 1);
    }
    const conn: [*c]struct_nonblock_io = @ptrCast(@alignCast(arcan_alloc_mem(@sizeOf(struct_nonblock_io), 0, 0, 0)));
    conn.* = std.mem.zeroes(struct_nonblock_io);
    conn.*.lfch = '\n';
    conn.*.fd = newfd;
    conn.*.mode = @as(mode_t, @bitCast(@as(c_int, 2)));
    conn.*.data_handler = @as(isize, @bitCast(@as(isize, -2)));
    conn.*.write_handler = @as(isize, @bitCast(@as(isize, -2)));
    if (!(conn != null)) {
        _ = close(newfd);
        return 0;
    }
    const dp: [*c]usize = @ptrCast(@alignCast(lua_newuserdata(L, @sizeOf(usize))));
    if (!(dp != null)) {
        _ = close(newfd);
        arcan_mem_free(@as(?*anyopaque, @ptrCast(conn)));
        return 0;
    }
    dp.* = @intFromPtr(conn);
    _ = lua_getfield(L, -1001000, "nonblockIO");
    _ = lua_setmetatable(L, -2);
    return 1;
}

pub fn nbio_writequeue(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    if (!(ib.* != null)) {
        lua_pushnumber(L, 0);
        lua_pushnumber(L, 0);
        return 2;
    }
    const iw: [*c]struct_nonblock_io = ib.*;
    if (!(iw.*.out_queue != null)) {
        lua_pushnumber(L, 0);
        lua_pushnumber(L, 0);
    } else {
        lua_pushnumber(L, @as(lua_Number, @floatFromInt(iw.*.out_count)));
        lua_pushnumber(L, @as(lua_Number, @floatFromInt(iw.*.out_queued)));
    }
    return 2;
}

pub fn nbio_write(L: ?*lua_State) callconv(.c) c_int {
    const ud: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    const iw: [*c]struct_nonblock_io = ud.*;
    if (!(iw != null)) {
        return 0;
    }
    if (iw.*.mode == @as(mode_t, @bitCast(@as(c_int, 0)))) {
        return 0;
    }
    var len: usize = 0;
    var buf: [*c]const u8 = null;
    if (lua_type(L, 2) == 4) {
        buf = luaL_checklstring(L, 2, &len);
        if (!(len != 0)) {
            return 0;
        }
    } else if (lua_type(L, 2) == 5) {} else while (true) {
        lua_pushlstring(L, "open_nonblock:write(data, cb) unexpected data type (str or tbl)", @sizeOf([64]u8) - 1);
        _ = lua_error(L);
        if (!false) break;
    }
    if ((-1 == iw.*.fd) and (iw.*.pending != null)) {
        iw.*.fd = open(iw.*.pending, (2048 | 1) | 524288);
        if (-1 != iw.*.fd) {
            var fi: struct_stat = undefined;
            if ((-1 != fstat(iw.*.fd, &fi)) and !((fi.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 4096))))) {
                lua_pushnumber(L, 0);
                lua_pushboolean(L, 0);
                return 2;
            }
        }
    }
    if (lua_type(L, 3) == 6) {
        if (iw.*.write_handler != @as(isize, @bitCast(@as(isize, -2)))) {
            unref_registry(L, iw.*.write_handler, 6, "nbio-write-cb-chg");
            iw.*.write_handler = @as(isize, @bitCast(@as(isize, -2)));
        }
        lua_pushvalue(L, 3);
        iw.*.write_handler = @as(isize, @bitCast(@as(isize, luaL_ref(L, -1001000))));
    }
    if (!(len != 0)) {
        lua_getfield(L, 2, "suffix");
        var suffix: [*c]u8 = null;
        var suffix_len: usize = 0;
        if (lua_type(L, -1) == 4) {
            suffix = strdup(lua_tolstring(L, -1, &suffix_len));
        }
        lua_settop(L, -1 - 1);
        const count: c_int = @as(c_int, @bitCast(@as(c_uint, @truncate(lua_objlen(L, 2)))));
        {
            var i: isize = 0;
            while (i < @as(isize, @bitCast(@as(isize, count)))) : (i += 1) {
                lua_rawgeti(L, 2, @as(c_int, @truncate(i + 1)));
                buf = lua_tolstring(L, -1, &len);
                if (!(len != 0)) {
                    if (!(suffix_len != 0)) {
                        lua_settop(L, -1 - 1);
                        continue;
                    }
                    buf = "";
                    len = 0;
                }
                if (!(buf != null) or !(queue_out(iw, buf, len, suffix, suffix_len) != null)) {
                    drop_all_jobs(iw);
                    lua_settop(L, -1 - 1);
                    lua_pushnumber(L, 0);
                    lua_pushboolean(L, 0);
                    free(@as(?*anyopaque, @ptrCast(suffix)));
                    return 2;
                }
                lua_settop(L, -1 - 1);
            }
        }
    } else {
        if (!(queue_out(iw, buf, len, null, 0) != null)) {
            lua_pushnumber(L, 0);
            lua_pushboolean(L, 0);
            return 2;
        }
    }
    var ref: isize = undefined;
    if (remove_job.?(iw.*.fd, @as(mode_t, @bitCast(@as(c_int, 1))), &ref)) {
        unref_registry(L, ref, 7, "nbio-wrmeta-chg");
    }
    lua_pushvalue(L, 1);
    ref = @as(isize, @bitCast(@as(isize, luaL_ref(L, -1001000))));
    _ = add_job.?(iw.*.fd, @as(mode_t, @bitCast(@as(c_int, 1))), ref);
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(len)));
    lua_pushboolean(L, 1);
    return 2;
}

pub fn nextline(ib: [*c]struct_nonblock_io, start: usize, eof: bool, nb: [*c]usize, step: [*c]usize, gotline: [*c]bool, linech: u8) callconv(.c) [*c]u8 {
    if (!(ib.*.ofs != 0)) return null;
    step.* = 0;
    {
        var i: usize = start;
        while (i < @as(usize, @bitCast(ib.*.ofs))) : (i +%= 1) {
            if (@as(c_int, @bitCast(@as(c_uint, ib.*.buf[i]))) == @as(c_int, @bitCast(@as(c_uint, linech)))) {
                nb.* = if (ib.*.lfstrip) i -% start else (i -% start) +% 1;
                step.* = (i -% start) +% 1;
                gotline.* = true;
                return &ib.*.buf[start];
            }
        }
    }
    if ((@as(c_int, @intFromBool(eof)) != 0) or (!(start != 0) and (@as(usize, @bitCast(ib.*.ofs)) == @sizeOf([4096]u8) / @sizeOf(u8)))) {
        gotline.* = false;
        if (@as(usize, @bitCast(ib.*.ofs)) < start) {
            nb.* = 0;
            step.* = 0;
            ib.*.ofs = 0;
        } else {
            nb.* = @as(usize, @bitCast(ib.*.ofs)) -% start;
            step.* = @as(usize, @bitCast(ib.*.ofs)) -% start;
        }
        return @ptrCast(&ib.*.buf[0]);
    }
    return null;
}

pub export fn luaL_optbnumber(L: ?*lua_State, narg: c_int, opt: lua_Number) lua_Number {
    if (lua_isnumber(L, narg) != 0) return lua_tonumber(L, narg) else if (lua_type(L, narg) == 1) return @as(lua_Number, @floatFromInt(lua_toboolean(L, narg))) else return opt;
    return std.mem.zeroes(lua_Number);
}

pub export fn luaL_checkbnumber(L: ?*lua_State, narg: c_int) lua_Number {
    var d: lua_Number = lua_tonumber(L, narg);
    if ((d == 0) and !(lua_isnumber(L, narg) != 0)) {
        if (!(lua_type(L, narg) == 1)) {
            _ = luaL_argerror(L, narg, "number or boolean");
        } else {
            d = @as(lua_Number, @floatFromInt(lua_toboolean(L, narg)));
        }
    }
    return d;
}

pub fn nbio_lf(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    const ir: [*c]struct_nonblock_io = ib.*;
    ir.*.lfstrip = luaL_optbnumber(L, 2, 0) != 0;
    if (lua_type(L, 3) == 4) {
        const ch: [*c]const u8 = lua_tolstring(L, 3, null);
        ir.*.lfch = ch[0];
    }
    return 0;
}

pub fn nbio_read(L: ?*lua_State) callconv(.c) c_int {
    const ib: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    const ir: [*c]struct_nonblock_io = ib.*;
    if (!(ir != null)) {
        return 0;
    }
    if (ir.*.mode == @as(mode_t, @bitCast(@as(c_int, 1)))) {
        return 0;
    }
    const nonbuffered: bool = luaL_optbnumber(L, 2, 0) != 0;
    const nr: c_int = alt_nbio_process_read(L, ib.*, nonbuffered);
    return nr;
}

pub fn build_fifo_ipc(path: [*c]u8, userns: bool, expect_write: bool) callconv(.c) struct_pathfd {
    var res: struct_pathfd = struct_pathfd{
        .path = null,
        .unlink = null,
        .err = null,
        .metatable = null,
        .fd = -1,
        .wrmode = 0,
    };
    const ns: c_int = if (userns) @as(c_int, 2) else @as(c_int, 1);
    const workpath: [*c]u8 = arcan_expand_resource(path, ns);
    if (!(workpath != null)) {
        res.err = "Couldn't expand FIFO path";
        return res;
    }
    var fi: struct_stat = undefined;
    if (-1 == stat(path, &fi)) {
        if (expect_write) {
            if (-1 == c.mkfifo(workpath, @as(mode_t, @bitCast(@as(c_int, 256) | @as(c_int, 128) | @as(c_int, 64))))) {
                arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
                res.err = "Couldn't build FIFO";
                return res;
            }
            const fd: c_int = open(workpath, 2);
            if (-1 == fd) {
                arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
                res.err = "Couldn't bind FIFO";
                return res;
            }
            res.unlink = workpath;
            res.fd = fd;
            return res;
        } else {
            res.path = workpath;
            return res;
        }
    }
    const fd: c_int = open(workpath, if (expect_write) @as(c_int, 1) else @as(c_int, 0));
    arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
    if ((-1 == fd) or (-1 == fstat(fd, &fi)) or ((fi.st_mode & @as(mode_t, @bitCast(@as(c_int, 61440)))) == @as(mode_t, @bitCast(@as(c_int, 4096))))) {
        _ = close(fd);
        res.err = "Couldn't open as FIFO";
        return res;
    }
    var flags: c_int = fcntl(fd, 3);
    if (-1 != flags) {
        _ = fcntl(fd, 4, flags | 2048);
    }
    if (-1 != (blk: {
        const tmp = fcntl(fd, 1);
        flags = tmp;
        break :blk tmp;
    })) {
        _ = fcntl(fd, 2, flags | 1);
    }
    res.fd = fd;
    return res;
}

pub fn build_socket_ipc(pathin: [*c]u8, userns: bool, srv: bool) callconv(.c) struct_pathfd {
    var res: struct_pathfd = struct_pathfd{
        .path = null,
        .unlink = null,
        .err = null,
        .metatable = null,
        .fd = -1,
        .wrmode = 0,
    };
    const ns: c_int = if (userns) @as(c_int, 2) else @as(c_int, 1);
    if (srv) {
        var workpath: [*c]u8 = arcan_find_resource(pathin, ns, 1, null);
        if (workpath != null) {
            res.err = "EINVAL: Couldn't create socket";
            arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
            return res;
        }
        workpath = arcan_expand_resource(pathin, ns);
        if (!(workpath != null)) {
            res.err = "EINVAL: Couldn't build socket file";
            return res;
        }
        var addr: struct_sockaddr_un = .{ .sun_family = 1 }; // AF_UNIX
        const lim: usize = @sizeOf(@TypeOf(addr.sun_path));
        if (strlen(workpath) > (lim -% 1)) {
            res.err = "ENAMETOOLONG: expanded socket doesn't fit sockaddr";
            arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
            return res;
        }
        _ = snprintf(@ptrCast(&addr.sun_path[0]), lim, "%s", workpath);
        res.fd = socket(1, SOCK_STREAM, 0);
        if (-1 == res.fd) {
            res.err = "EPERM: couldn't allocate socket";
            arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
            return res;
        }
        _ = fchmod(res.fd, @as(mode_t, @bitCast(@as(c_int, 256) | @as(c_int, 128) | @as(c_int, 64))));
        if (-1 == c.bind(res.fd, constSockaddrCast(&addr), @as(socklen_t, @bitCast(@as(c_uint, @truncate(@sizeOf(struct_sockaddr_un))))))) {
            _ = close(res.fd);
            arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
            res.fd = -1;
            res.err = "ESOCKET: couldn't bind socket";
            return res;
        }
        _ = listen(res.fd, 5);
        res.unlink = workpath;
        res.metatable = "nonblockIOs";
        res.wrmode = 2;
    } else {
        const workpath: [*c]u8 = arcan_find_resource(pathin, ns, 1, null);
        if (!(workpath != null)) {
            res.err = "EEXIST: Couldn't connect to socket";
            return res;
        }
        res.fd = alt_nbio_socket(workpath, ns, &res.unlink);
        res.wrmode = 2;
        res.metatable = "nonblockIO";
        if (-1 == res.fd) {
            res.err = "EPERM: Couldn't bind to socket";
        }
        arcan_mem_free(@as(?*anyopaque, @ptrCast(workpath)));
    }
    return res;
}

pub fn build_new_file(path: [*c]u8, userns: bool) callconv(.c) struct_pathfd {
    var res: struct_pathfd = struct_pathfd{
        .path = null,
        .unlink = null,
        .err = null,
        .metatable = "nonblockIO",
        .fd = -1,
        .wrmode = 2,
    };
    const ns: c_int = if (userns) @as(c_int, 2) else @as(c_int, 1);
    const userpath: [*c]u8 = arcan_find_resource(path, ns, 1 | 256, &res.fd);
    if (!(path != null)) {
        res.err = "Couldn't create file in namespace";
    } else {
        arcan_mem_free(@as(?*anyopaque, @ptrCast(userpath)));
    }
    return res;
}

pub fn open_existing_file(path: [*c]u8, userns: bool) callconv(.c) struct_pathfd {
    var res: struct_pathfd = struct_pathfd{
        .path = null,
        .unlink = null,
        .err = null,
        .metatable = "nonblockIO",
        .fd = -1,
        .wrmode = 0,
    };
    _ = userns;
    const ns: c_int = 2;
    const cpath: [*c]u8 = arcan_find_resource(path, ns, 1, &res.fd);
    if (!(cpath != null)) {
        res.err = "Couldn't find file";
    }
    arcan_mem_free(@as(?*anyopaque, @ptrCast(cpath)));
    return res;
}

pub fn nbio_seek(L: ?*lua_State) callconv(.c) c_int {
    const ibb: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    const ib: [*c]struct_nonblock_io = ibb.*;
    if (!(ib != null)) while (true) {
        lua_pushlstring(L, "nbio:seek on closed file", @sizeOf([25]u8) - 1);
        _ = lua_error(L);
        if (!false) break;
    };
    const ofs: lua_Number = lua_tonumber(L, 1);
    const relative: bool = luaL_optbnumber(L, 2, 1) != 0;
    var pos: off_t = undefined;
    if (!relative) {
        pos = lseek(ib.*.fd, @as(off_t, @intFromFloat(ofs)), 0);
    } else {
        if (ofs < 0) {
            pos = lseek(ib.*.fd, @as(off_t, @intFromFloat(-ofs)), 2);
        } else {
            pos = lseek(ib.*.fd, @as(off_t, @intFromFloat(ofs)), 1);
        }
    }
    lua_pushboolean(L, @intFromBool(pos != @as(off_t, @bitCast(@as(isize, -1)))));
    lua_pushnumber(L, @as(lua_Number, @floatFromInt(pos)));
    return 2;
}

pub fn nbio_position(L: ?*lua_State) callconv(.c) c_int {
    const ibb: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    if (!(ibb != null)) while (true) {
        lua_pushlstring(L, "nbio:set_position on closed file", @sizeOf([33]u8) - 1);
        _ = lua_error(L);
        if (!false) break;
    };
    const ib: [*c]struct_nonblock_io = ibb.*;
    var pos: lua_Number = lua_tonumber(L, 1);
    if (pos < 0) {
        pos = @as(lua_Number, @floatFromInt(lseek(ib.*.fd, @as(off_t, @intFromFloat(-pos)), 2)));
    } else {
        pos = @as(lua_Number, @floatFromInt(lseek(ib.*.fd, @as(off_t, @intFromFloat(pos)), 0)));
    }
    lua_pushboolean(L, @intFromBool(pos != @as(lua_Number, @floatFromInt(@as(c_int, -1)))));
    lua_pushnumber(L, pos);
    return 2;
}

pub fn nbio_flush(L: ?*lua_State) callconv(.c) c_int {
    const ibb: [*c][*c]struct_nonblock_io = @ptrCast(@alignCast(luaL_checkudata(L, 1, "nonblockIO")));
    const ib: [*c]struct_nonblock_io = ibb.*;
    lua_settop(L, -1 - 1);
    if (((ib.*.write_handler != @as(isize, @bitCast(@as(isize, -2)))) or !(ib.*.out_queue != null)) or (ib.*.fd == -1)) {
        lua_pushboolean(L, 0);
        return 1;
    }
    const timeout: isize = @as(isize, @intFromFloat(luaL_optnumber(L, 2, @as(lua_Number, @floatFromInt(@as(c_int, -1))))));
    const rv: bool = ensure_flush(L, ib, @as(usize, @bitCast(timeout)));
    lua_pushboolean(L, @intFromBool(rv));
    return 1;
}
