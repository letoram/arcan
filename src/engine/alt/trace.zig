// Pure Zig port of engine/alt/trace.c — engine tracing layer interfacing
// with Lua stage for automated analysis and report generation.

const std = @import("std");
const c = @import("arcan_boot_compat");

// Types from boot_compat
const lua_State = c.lua_State;
const lua_Number = c.lua_Number;

// Lua API — all from boot_compat
const lua_gettop = c.lua_gettop;
const lua_settop = c.lua_settop;
const lua_type = c.lua_type;
const lua_pcall = c.lua_pcall;
const lua_pushnil = c.lua_pushnil;
const lua_pushvalue = c.lua_pushvalue;
const lua_pushstring = c.lua_pushstring;
const lua_pushlstring = c.lua_pushlstring;
const lua_pushnumber = c.lua_pushnumber;
const lua_toboolean = c.lua_toboolean;
const lua_tonumber = c.lua_tonumber;
const lua_tolstring = c.lua_tolstring;
const lua_createtable = c.lua_createtable;
const lua_rawset = c.lua_rawset;
const lua_rawgeti = c.lua_rawgeti;
const lua_next = c.lua_next;
const lua_getfield = c.lua_getfield;
const lua_call = c.lua_call;
const lua_getinfo = c.lua_getinfo;
const lua_getstack = c.lua_getstack;
const lua_objlen = c.lua_objlen;
const luaL_unref = c.luaL_unref;
fn lua_istable(L: ?*lua_State, idx: c_int) c_int {
    return if (c.lua_type(L, idx) == c.LUA_TTABLE) 1 else 0;
}
fn lua_isfunction(L: ?*lua_State, idx: c_int) c_int {
    return if (c.lua_type(L, idx) == c.LUA_TFUNCTION) 1 else 0;
}

// Lua API — from boot_compat
const lua_rawequal = c.lua_rawequal;
const lua_getlocal = c.lua_getlocal;
const lua_getmetatable = c.lua_getmetatable;
const luaL_openlibs = c.luaL_openlibs;

// Lua constants
const LUA_TFUNCTION = c.LUA_TFUNCTION;
const LUA_TBOOLEAN = c.LUA_TBOOLEAN;
const LUA_TSTRING = c.LUA_TSTRING;
const LUA_TNUMBER = c.LUA_TNUMBER;
const LUA_TTABLE = c.LUA_TTABLE;
const LUA_TNIL = c.LUA_TNIL;
const LUA_TUSERDATA: c_int = 7;
const LUA_REGISTRYINDEX = c.LUA_REGISTRYINDEX;

// arcan engine — from boot_compat
const arcan_alloc_mem = c.arcan_alloc_mem;
const arcan_mem_free = c.arcan_mem_free;
const arcan_trace_setbuffer = c.arcan_trace_setbuffer;
// arcan engine — from boot_compat
const arcan_conductor_toggle_watchdog = c.arcan_conductor_toggle_watchdog;
const arcan_trace_log = c.arcan_trace_log;
const alt_apply_ban = c.alt_apply_ban;
const alt_call = c.alt_call;
const alt_trace_cbstate = c.alt_trace_cbstate;

// Memory allocation constants
const ARCAN_MEM_EXTSTRUCT: c_int = 3;
const ARCAN_MEM_STRINGBUF: c_int = 5;
const ARCAN_MEM_BZERO: c_int = 1;
const ARCAN_MEM_NONFATAL: c_int = 8;
const ARCAN_MEM_TEMPORARY: c_int = 2;
const ARCAN_MEMALIGN_NATURAL: c_int = 0;

// Trace level constants
const TRACE_SYS_DEFAULT: u8 = 0;
const TRACE_SYS_SLOW: u8 = 1;
const TRACE_SYS_FAST: u8 = 2;
const TRACE_SYS_WARN: u8 = 3;
const TRACE_SYS_ERROR: u8 = 4;

// CB_SOURCE_NONE, EP_TRIGGER_TRACE
const CB_SOURCE_NONE: c_int = 0;
const EP_TRIGGER_TRACE: u64 = (1 << 23);

// LINE_TAG
const LINE_TAG_TRACE = "trace.zig:trace";

// libc — from boot_compat
const FILE = c.FILE;
const fputc = c.fputc;
const fputs = c.fputs;
const fflush = c.fflush;
const fprintf = c.fprintf;
const free = c.free;
const strdup = c.strdup;

// EP_TRIGGER constants
const EP_TRIGGER_CLOCK: c_int = (1 << 0);
const EP_TRIGGER_INPUT: c_int = (1 << 1);
const EP_TRIGGER_INPUT_RAW: c_int = (1 << 2);
const EP_TRIGGER_INPUT_END: c_int = (1 << 3);
const EP_TRIGGER_PREFRAME: c_int = (1 << 4);
const EP_TRIGGER_POSTFRAME: c_int = (1 << 5);
const EP_TRIGGER_ADOPT: c_int = (1 << 6);
const EP_TRIGGER_AUTORES: c_int = (1 << 7);
const EP_TRIGGER_AUTOFONT: c_int = (1 << 8);
const EP_TRIGGER_DISPLAYSTATE: c_int = (1 << 9);
const EP_TRIGGER_DISPLAYRESET: c_int = (1 << 10);
const EP_TRIGGER_FRAMESERVER: c_int = (1 << 11);
const EP_TRIGGER_MESH: c_int = (1 << 12);
const EP_TRIGGER_CALCTARGET: c_int = (1 << 13);
const EP_TRIGGER_LWA: c_int = (1 << 14);
const EP_TRIGGER_IMAGE: c_int = (1 << 15);
const EP_TRIGGER_AUDIO: c_int = (1 << 16);
const EP_TRIGGER_MAIN: c_int = (1 << 17);
const EP_TRIGGER_SHUTDOWN: c_int = (1 << 18);
const EP_TRIGGER_NBIO_RD: c_int = (1 << 19);
const EP_TRIGGER_NBIO_WR: c_int = (1 << 20);
const EP_TRIGGER_NBIO_DATA: c_int = (1 << 21);
const EP_TRIGGER_HANDOVER: c_int = (1 << 22);
const EP_TRIGGER_TRACE_EP: c_int = (1 << 23);

// Static state
var got_trace_buffer: bool = false;
var trace_buffer: ?[*]u8 = null;
var trace_buffer_sz: usize = 0;
var trace_cb: isize = 0;
var crash_source: [*c]u8 = null;

// tblstr / tblnum helpers (replicate C macros)
fn tblstr(L: ?*lua_State, k: [*c]const u8, v: [*c]const u8, top: c_int) void {
    lua_pushstring(L, k);
    lua_pushstring(L, v);
    lua_rawset(L, top);
}

fn tblnum(L: ?*lua_State, k: [*c]const u8, v: f64, top: c_int) void {
    lua_pushstring(L, k);
    lua_pushnumber(L, v);
    lua_rawset(L, top);
}

// alt_trace_crash_source
export fn alt_trace_crash_source() [*c]u8 {
    return crash_source;
}

// alt_trace_set_crash_source
export fn alt_trace_set_crash_source(msg: [*c]const u8) void {
    if (@intFromPtr(crash_source) != 0) {
        free(@ptrCast(crash_source));
        crash_source = null;
    }
    if (@intFromPtr(msg) != 0) {
        crash_source = strdup(msg);
    }
}

// alt_trace_callstack
export fn alt_trace_callstack(L: ?*lua_State, out: ?*FILE) void {
    luaL_openlibs(L);

    lua_settop(L, -2);
    _ = c.lua_getglobal(L, "debug");
    if (lua_istable(L, -1) == 0) {
        lua_settop(L, lua_gettop(L) - 1);
    } else {
        _ = lua_getfield(L, -1, "traceback");
        if (lua_isfunction(L, -1) == 0) {
            // pop 2 (debug table + non-function)
            lua_settop(L, lua_gettop(L) - 2);
        } else {
            lua_call(L, 0, 1);
            const str = lua_tolstring(L, -1, null);
            _ = fprintf(out, "%s\n", str);
        }
    }

    alt_apply_ban(L);
}

// put_shmif_luastr
fn put_shmif_luastr(msg: [*c]const u8, out: ?*FILE) void {
    if (@intFromPtr(msg) == 0) return;
    var p: [*c]const u8 = msg;
    while (p[0] != 0) {
        if (p[0] == '\n') {
            _ = fputc('\\', out);
            _ = fputc('n', out);
            p += 1;
            continue;
        }
        if (p[0] == '\t') {
            _ = fputs("     ", out);
        } else if (p[0] == ':') {
            _ = fputs("\t", out);
        } else if (p[0] == ',') {
            _ = fputc('\\', out);
        } else {
            _ = fputc(p[0], out);
        }
        p += 1;
    }
}

// alt_trace_dumptable_raw
export fn alt_trace_dumptable_raw(L: ?*lua_State, ofs_arg: c_int, cap_arg: c_int, out: ?*FILE) void {
    if (lua_type(L, -1) != LUA_TTABLE)
        return;

    lua_pushnil(L);
    var ind: c_int = 0;
    var ofs = ofs_arg;
    var cap = cap_arg;

    while (lua_next(L, -2) != 0) {
        if (ofs == 0) {
            _ = fprintf(out, "type=table:index=%d:", ind);
            ind += 1;
            switch (lua_type(L, -2)) {
                LUA_TNUMBER => {
                    _ = fprintf(out, "keytype=number:tblkey=%.14g:", lua_tonumber(L, -2));
                },
                LUA_TSTRING => {
                    _ = fputs("keytype=string:tblkey=", out);
                    put_shmif_luastr(lua_tolstring(L, -2, null), out);
                    _ = fputc(':', out);
                },
                LUA_TBOOLEAN => {
                    const bval: [*c]const u8 = if (lua_toboolean(L, -2) != 0) "true" else "false";
                    _ = fprintf(out, "keytype=bool:tblkey=%s:", bval);
                },
                LUA_TFUNCTION => {
                    _ = fputs("keytype=function:tblkey=func:", out);
                },
                LUA_TTABLE => {
                    _ = fputs("keytype=table:tblkey=table:", out);
                },
                else => {
                    _ = fputs("keytype=unknown:tblkey=unknown:", out);
                },
            }
            _ = fputs("var", out);
            alt_trace_print_type(L, -1, "\n", out);
        } else {
            ofs -= 1;
        }
        // lua_pop(L, 1)
        lua_settop(L, lua_gettop(L) - 1);
        if (cap != 0) {
            cap -= 1;
            if (cap == 0) break;
        }
    }
    // lua_pop(L, 1)
    lua_settop(L, lua_gettop(L) - 1);
}

// alt_trace_dumpstack_raw
export fn alt_trace_dumpstack_raw(L: ?*lua_State, out: ?*FILE) void {
    var top = lua_gettop(L);
    while (top > 0) {
        _ = fprintf(out, "type=stack:index=%d:name=%d:var", top, top);
        alt_trace_print_type(L, top, "\n", out);
        top -= 1;
    }
}

// ep_map
const EpMapEntry = struct {
    maskv: c_int,
    keyv: [*c]const u8,
};

const ep_map = [_]EpMapEntry{
    .{ .maskv = EP_TRIGGER_CLOCK, .keyv = "clock" },
    .{ .maskv = EP_TRIGGER_INPUT, .keyv = "input" },
    .{ .maskv = EP_TRIGGER_INPUT_RAW, .keyv = "input_raw" },
    .{ .maskv = EP_TRIGGER_INPUT_END, .keyv = "input_end" },
    .{ .maskv = EP_TRIGGER_PREFRAME, .keyv = "preframe" },
    .{ .maskv = EP_TRIGGER_POSTFRAME, .keyv = "postframe" },
    .{ .maskv = EP_TRIGGER_ADOPT, .keyv = "adopt" },
    .{ .maskv = EP_TRIGGER_AUTORES, .keyv = "autores" },
    .{ .maskv = EP_TRIGGER_AUTOFONT, .keyv = "autofont" },
    .{ .maskv = EP_TRIGGER_DISPLAYSTATE, .keyv = "display_state" },
    .{ .maskv = EP_TRIGGER_DISPLAYRESET, .keyv = "display_reset" },
    .{ .maskv = EP_TRIGGER_FRAMESERVER, .keyv = "frameserver" },
    .{ .maskv = EP_TRIGGER_MESH, .keyv = "mesh" },
    .{ .maskv = EP_TRIGGER_CALCTARGET, .keyv = "calctarget" },
    .{ .maskv = EP_TRIGGER_LWA, .keyv = "lwa" },
    .{ .maskv = EP_TRIGGER_IMAGE, .keyv = "image" },
    .{ .maskv = EP_TRIGGER_AUDIO, .keyv = "audio" },
    .{ .maskv = EP_TRIGGER_MAIN, .keyv = "main" },
    .{ .maskv = EP_TRIGGER_SHUTDOWN, .keyv = "shutdown" },
    .{ .maskv = EP_TRIGGER_NBIO_RD, .keyv = "nbio_read" },
    .{ .maskv = EP_TRIGGER_NBIO_WR, .keyv = "nbio_write" },
    .{ .maskv = EP_TRIGGER_NBIO_DATA, .keyv = "nbio_data" },
    .{ .maskv = EP_TRIGGER_HANDOVER, .keyv = "handover" },
    .{ .maskv = EP_TRIGGER_TRACE_EP, .keyv = "trace" },
};

fn c_streq(a: [*c]const u8, b: [*c]const u8) bool {
    if (@intFromPtr(a) == 0 or @intFromPtr(b) == 0) return false;
    var i: usize = 0;
    while (a[i] != 0 and b[i] != 0) : (i += 1) {
        if (a[i] != b[i]) return false;
    }
    return a[i] == b[i];
}

// alt_trace_strtoep
export fn alt_trace_strtoep(ep: [*c]const u8) u64 {
    for (ep_map) |entry| {
        if (c_streq(entry.keyv, ep))
            return @bitCast(@as(i64, entry.maskv));
    }
    return 0;
}

// alt_trace_eptostr
export fn alt_trace_eptostr(ep: u64) [*c]const u8 {
    const ep_i: c_int = @intCast(@as(i64, @bitCast(ep)));
    for (ep_map) |entry| {
        if (entry.maskv == ep_i)
            return entry.keyv;
    }
    return "(bad)";
}

// lua_Debug layout
// LuaJIT lua_Debug has a specific layout. We access fields by offset.
// On LuaJIT 5.1: event, name, namewhat, what, source, currentline,
// nups, linedefined, lastlinedefined, short_src[60]
// sizeof(lua_Debug) varies; we allocate a generous buffer.
const LUA_DEBUG_SIZE: usize = 256;
const LUA_DEBUG_NAME_OFFSET: usize = 8; // const char* name (after int event + padding)
const LUA_DEBUG_NAMEWHAT_OFFSET: usize = 16; // const char* namewhat
// These are accessed via Lua API (lua_getinfo populates them), so we pass the
// buffer directly.

// alt_trace_callstack_raw
export fn alt_trace_callstack_raw(L: ?*lua_State, _: ?*anyopaque, levels: c_int, out: ?*FILE) void {
    var cbk: u64 = undefined;
    var luavid: i64 = undefined;
    var vid: i64 = undefined;
    alt_trace_cbstate(&cbk, &luavid, &vid);
    _ = fprintf(out, "type=entrypoint:kind=%s:vid=%lld:luavid=%llu\n", alt_trace_eptostr(cbk), @as(c_longlong, luavid), @as(c_ulonglong, @bitCast(vid)));

    var level: c_int = 0;
    var ar: [LUA_DEBUG_SIZE]u8 align(8) = std.mem.zeroes([LUA_DEBUG_SIZE]u8);

    while (lua_getstack(L, level, @ptrCast(&ar)) != 0 and level < levels) {
        _ = lua_getinfo(L, "Slnu", @ptrCast(&ar));

        // Access lua_Debug fields via offsets — Lua C API populates the struct
        // We use the C API approach: pass ar to getinfo, then read fields via C helper
        // Actually, for safety we use fprintf with the opaque ar and let C read them.
        // But since this is Zig calling fprintf with lua_Debug fields that are C strings,
        // we need to read the pointers from the lua_Debug struct.
        // LuaJIT lua_Debug layout (aarch64):
        //   int event;          // 0
        //   const char *name;   // 8
        //   const char *namewhat; // 16
        //   const char *what;   // 24
        //   const char *source; // 32
        //   int currentline;    // 40
        //   int nups;           // 44
        //   int linedefined;    // 48
        //   int lastlinedefined; // 52
        const ar_ptr: [*]const u8 = &ar;
        const name = readCStr(ar_ptr, 8);
        const namewhat = readCStr(ar_ptr, 16);
        const source = readCStr(ar_ptr, 32);
        const currentline = readI32(ar_ptr, 40);
        const linedefined = readI32(ar_ptr, 48);
        const lastlinedefined = readI32(ar_ptr, 52);
        const nups = readI32(ar_ptr, 44);

        const name_s: [*c]const u8 = if (@intFromPtr(name) != 0) name else "(null)";
        const namewhat_s: [*c]const u8 = if (@intFromPtr(namewhat) != 0) namewhat else "(null)";
        _ = fprintf(out,
            "type=stacktrace:frame=%d:name=%s:" ++
                "kind=%s:source=%s:current=%d:start=%d:end=%d:upvalues=%d\n",
            level,
            name_s,
            namewhat_s,
            source,
            currentline,
            linedefined,
            lastlinedefined,
            nups,
        );

        // Dump locals
        var argi: c_int = 1;
        while (true) {
            const lname = lua_getlocal(L, @ptrCast(&ar), argi);
            if (@intFromPtr(lname) == 0) break;
            _ = fprintf(out, "type=local:index=%d:name=%s:var", argi, lname);
            alt_trace_print_type(L, -1, "", out);
            _ = fputc('\n', out);
            lua_settop(L, lua_gettop(L) - 1); // pop
            argi += 1;
        }

        // Varargs (negative locals)
        argi = -1;
        while (true) {
            const lname = lua_getlocal(L, @ptrCast(&ar), argi);
            if (@intFromPtr(lname) == 0) break;
            _ = fprintf(out, "type=local:index=%d:vararg:name=%s:var", argi, lname);
            alt_trace_print_type(L, -1, "", out);
            _ = fputc('\n', out);
            lua_settop(L, lua_gettop(L) - 1); // pop
            argi -= 1;
        }

        level += 1;
    }
}

fn readCStr(base: [*]const u8, off: usize) [*c]const u8 {
    const ptr: *align(1) const [*c]const u8 = @ptrCast(base + off);
    return ptr.*;
}

fn readI32(base: [*]const u8, off: usize) c_int {
    const ptr: *align(1) const c_int = @ptrCast(base + off);
    return ptr.*;
}

// alt_trace_start
export fn alt_trace_start(L: ?*lua_State, cb: isize, sz: usize) bool {
    const interim = arcan_alloc_mem(
        sz,
        ARCAN_MEM_EXTSTRUCT,
        ARCAN_MEM_BZERO | ARCAN_MEM_NONFATAL,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse {
        luaL_unref(L, LUA_REGISTRYINDEX, @intCast(cb));
        return false;
    };

    arcan_trace_setbuffer(interim, sz, &got_trace_buffer);
    trace_buffer = @ptrCast(interim);
    trace_buffer_sz = sz;
    trace_cb = cb;

    return true;
}

// alt_trace_finish
export fn alt_trace_finish(L: ?*lua_State) void {
    if (!got_trace_buffer)
        return;

    _ = lua_rawgeti(L, LUA_REGISTRYINDEX, @intCast(trace_cb));
    lua_createtable(L, 0, 0);
    const ttop = lua_gettop(L);

    const buf: [*]u8 = trace_buffer orelse return;
    var pos: usize = 0;

    var ind: usize = 1;
    while (buf[pos] == 0xff) {
        pos += 1;
        lua_pushnumber(L, @floatFromInt(ind));
        ind += 1;
        lua_createtable(L, 0, 0);
        const top = lua_gettop(L);

        // timestamp (u64)
        var ts: u64 = undefined;
        @memcpy(std.mem.asBytes(&ts), buf[pos..][0..8]);
        pos += 8;
        tblnum(L, "timestamp", @floatFromInt(ts), top);

        // system (null-terminated string)
        var nb: usize = cstrlen(buf + pos);
        lua_pushstring(L, "system");
        lua_pushlstring(L, @ptrCast(buf + pos), nb);
        lua_rawset(L, top);
        pos += nb + 1;

        // subsystem
        nb = cstrlen(buf + pos);
        lua_pushstring(L, "subsystem");
        lua_pushlstring(L, @ptrCast(buf + pos), nb);
        lua_rawset(L, top);
        pos += nb + 1;

        // trigger
        const inb_trigger: u8 = buf[pos];
        pos += 1;
        tblnum(L, "trigger", @floatFromInt(inb_trigger), top);

        // tracelevel
        const inb_level: u8 = buf[pos];
        pos += 1;
        switch (inb_level) {
            TRACE_SYS_DEFAULT => tblstr(L, "path", "default", top),
            TRACE_SYS_SLOW => tblstr(L, "path", "slow", top),
            TRACE_SYS_WARN => tblstr(L, "path", "warning", top),
            TRACE_SYS_FAST => tblstr(L, "path", "fast", top),
            TRACE_SYS_ERROR => tblstr(L, "path", "error", top),
            else => tblstr(L, "path", "broken", top),
        }

        // identifier (u64)
        var ident: u64 = undefined;
        @memcpy(std.mem.asBytes(&ident), buf[pos..][0..8]);
        pos += 8;
        tblnum(L, "identifier", @floatFromInt(ident), top);

        // quantifier (u32)
        var quant: u32 = undefined;
        @memcpy(std.mem.asBytes(&quant), buf[pos..][0..4]);
        pos += 4;
        tblnum(L, "quantity", @floatFromInt(quant), top);

        // caller message
        nb = cstrlen(buf + pos);
        lua_pushstring(L, "message");
        lua_pushlstring(L, @ptrCast(buf + pos), nb);
        lua_rawset(L, top);
        pos += nb + 1;

        // step outer table
        lua_rawset(L, ttop);
    }

    // free buffer and reset
    free(@ptrCast(trace_buffer));
    arcan_trace_setbuffer(null, 0, null);
    trace_buffer = null;
    trace_buffer_sz = 0;
    got_trace_buffer = false;

    arcan_conductor_toggle_watchdog();
    alt_call(L, CB_SOURCE_NONE, EP_TRIGGER_TRACE, 0, 1, 0, LINE_TAG_TRACE);
    arcan_conductor_toggle_watchdog();
    luaL_unref(L, LUA_REGISTRYINDEX, @intCast(trace_cb));
}

fn cstrlen(s: [*]const u8) usize {
    var i: usize = 0;
    while (s[i] != 0) : (i += 1) {}
    return i;
}

// udata_list
const udata_list = [_][*c]const u8{
    "Arcan TUI",
    "nonblockIO",
    "nonblockIOs",
    "calcImage",
    "meshAccess",
};

fn match_udata(L: ?*lua_State, pos: c_int) [*c]const u8 {
    if (lua_getmetatable(L, pos) == 0)
        return null;

    for (udata_list) |name| {
        _ = lua_getfield(L, LUA_REGISTRYINDEX, name);
        if (lua_rawequal(L, -1, -2) != 0) {
            // pop 2
            lua_settop(L, lua_gettop(L) - 2);
            return name;
        }
        // pop 1
        lua_settop(L, lua_gettop(L) - 1);
    }

    // pop 1
    lua_settop(L, lua_gettop(L) - 1);
    return "(unknown)";
}

// alt_trace_print_type
export fn alt_trace_print_type(
    L: ?*lua_State,
    i: c_int,
    suffix: [*c]const u8,
    out: ?*FILE,
) void {
    const t = lua_type(L, i);
    if (t == LUA_TNUMBER) {
        _ = fprintf(out, "type=number:value=%.14g", lua_tonumber(L, i));
    } else if (t == LUA_TUSERDATA) {
        _ = fprintf(out, "type=userdata:name=%s\n", match_udata(L, i));
    } else if (t == LUA_TFUNCTION) {
        var ar: [LUA_DEBUG_SIZE]u8 align(8) = std.mem.zeroes([LUA_DEBUG_SIZE]u8);
        lua_pushvalue(L, i);
        _ = lua_getinfo(L, ">Snl", @ptrCast(&ar));
        const ar_ptr: [*]const u8 = &ar;
        const fname = readCStr(ar_ptr, 8);
        const fnamewhat = readCStr(ar_ptr, 16);
        const fsource = readCStr(ar_ptr, 32);
        const flinedefined = readI32(ar_ptr, 48);
        const flastlinedefined = readI32(ar_ptr, 52);
        const fname_s: [*c]const u8 = if (@intFromPtr(fname) != 0) fname else "(null)";
        const fnamewhat_s: [*c]const u8 = if (@intFromPtr(fnamewhat) != 0) fnamewhat else "(null)";
        _ = fprintf(out,
            "type=func:name=%s:kind=%s:source=%s:start=%d:end=%d",
            fname_s,
            fnamewhat_s,
            fsource,
            flinedefined,
            flastlinedefined,
        );
    } else if (t == LUA_TSTRING) {
        const msg = lua_tolstring(L, i, null);
        _ = fputs("type=string:value=", out);
        put_shmif_luastr(msg, out);
    } else if (t == LUA_TBOOLEAN) {
        _ = fputs(if (lua_toboolean(L, i) != 0) "type=bool:value=true" else "type=bool:value=false", out);
    } else if (t == LUA_TTABLE) {
        var n_keys: usize = 0;

        const nelems: usize = lua_objlen(L, i);

        lua_pushvalue(L, i);
        lua_pushnil(L);

        while (lua_next(L, -2) != 0) {
            lua_settop(L, lua_gettop(L) - 1); // pop value
            n_keys += 1;
        }
        lua_settop(L, lua_gettop(L) - 1); // pop table copy

        _ = fprintf(out, "type=table:length=%zu:keys=%zu", nelems, n_keys);
    } else if (t == LUA_TNIL) {
        _ = fputs("type=nil", out);
    }
    _ = fputs(suffix, out);
}

// alt_trace_log (replaces the default print function)
export fn alt_trace_log(L: ?*lua_State) c_int {
    if (!c.arcan_trace_enabled) {
        const n_args = lua_gettop(L);
        if (n_args > 0) {
            var i: c_int = 1;
            while (i < n_args) : (i += 1) {
                alt_trace_print_type(L, i, ", ", c.stdout);
            }
            alt_trace_print_type(L, n_args, "\n", c.stdout);
        }
        _ = fflush(c.stdout);
        return 0;
    }

    const str_prefix = "LUA_PRINT: ";
    const str_prefix_len: usize = str_prefix.len;

    const n_args = lua_gettop(L);

    var total_len: usize = str_prefix_len;
    {
        var i: c_int = 1;
        while (i <= n_args) : (i += 1) {
            var str_len: usize = 0;
            _ = lua_tolstring(L, i, &str_len);
            total_len += str_len + 1;
        }
    }
    total_len += 1;

    const log_buffer_ptr = arcan_alloc_mem(
        total_len,
        ARCAN_MEM_STRINGBUF,
        ARCAN_MEM_TEMPORARY | ARCAN_MEM_NONFATAL,
        ARCAN_MEMALIGN_NATURAL,
    ) orelse {
        const oom_msg = "Couldn't log trace message: Out of memory\n";
        arcan_trace_log(oom_msg, oom_msg.len);
        return 0;
    };
    const log_buffer: [*]u8 = @ptrCast(log_buffer_ptr);

    @memcpy(log_buffer[0..str_prefix_len], str_prefix);
    var running_len: usize = str_prefix_len;

    {
        var i: c_int = 1;
        while (i <= n_args) : (i += 1) {
            var str_len: usize = 0;
            const str = lua_tolstring(L, i, &str_len);
            if (@intFromPtr(str) != 0) {
                const src: [*]const u8 = @ptrCast(str);
                @memcpy(log_buffer[running_len..][0..str_len], src[0..str_len]);
            }
            running_len += str_len + 1;
            log_buffer[running_len - 1] = '\t';
        }
    }

    log_buffer[running_len - 1] = '\n';
    log_buffer[running_len] = 0;

    arcan_trace_log(@ptrCast(log_buffer), total_len);
    arcan_mem_free(log_buffer_ptr);
    return 0;
}
