// Zig port of a12/net/dir_lua_support.c — Lua support utilities for directory operations.
// Implements the monitor/debugger interface, entrypoint helpers, table inspection,
// and the vendored loadfile-via-dirfd used by the appl runner.
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
    // libc — stdio / string / fs
    pub const asprintf = libc.asprintf;
    pub const EOF = libc.EOF;
    pub const fclose = libc.fclose;
    pub const fdopen = libc.fdopen;
    pub const feof = libc.feof;
    pub const ferror = libc.ferror;
    pub const fflush = libc.fflush;
    pub const FILE = libc.FILE;
    pub const fprintf = libc.fprintf;
    pub const fputc = libc.fputc;
    pub const fputs = libc.fputs;
    pub const fread = libc.fread;
    pub const free = libc.free;
    pub const getc = libc.getc;
    pub const malloc = libc.malloc;
    pub const openat = libc.openat;
    pub const open_memstream = libc.open_memstream;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const strcasecmp = libc.strcasecmp;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const strtok_r = libc.strtok_r;
    pub const strtol = libc.strtol;
    pub const strtoul = libc.strtoul;
    pub const ungetc = libc.ungetc;

    // shmif — event constants
    pub const EVENT_EXTERNAL = shmif.EVENT_EXTERNAL;
    pub const EVENT_EXTERNAL_MESSAGE = shmif.EVENT_EXTERNAL_MESSAGE;

    // a12 — shmif_enqueue + event struct
    pub const arcan_shmif_enqueue = a12.arcan_shmif_enqueue;
    pub const struct_arcan_event = a12.struct_arcan_event;
    pub const struct_arcan_shmif_cont = a12.struct_arcan_shmif_cont;

    // anet — directory support types + constants
    pub const BREAK_LIMIT = anet.BREAK_LIMIT;
    pub const EP_TRIGGER_CLOCK = anet.EP_TRIGGER_CLOCK;
    pub const EP_TRIGGER_INDEX = anet.EP_TRIGGER_INDEX;
    pub const EP_TRIGGER_JOIN = anet.EP_TRIGGER_JOIN;
    pub const EP_TRIGGER_LEAVE = anet.EP_TRIGGER_LEAVE;
    pub const EP_TRIGGER_LOAD = anet.EP_TRIGGER_LOAD;
    pub const EP_TRIGGER_MESSAGE = anet.EP_TRIGGER_MESSAGE;
    pub const EP_TRIGGER_RESET = anet.EP_TRIGGER_RESET;
    pub const EP_TRIGGER_STORE = anet.EP_TRIGGER_STORE;
    pub const EP_TRIGGER_TRACE = anet.EP_TRIGGER_TRACE;
    pub const struct_dirlua_monitor_state = anet.struct_dirlua_monitor_state;
};

// External resource-mapping functions (from arcan engine support)
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
extern fn arcan_open_resource(arg: [*:0]const u8) data_source;
extern fn arcan_map_resource(src: *data_source, wr: bool) map_region;
extern fn arcan_release_map(reg: map_region) void;
extern fn arcan_release_resource(src: *data_source) void;

// Thread-local state
threadlocal var monitor: ?*c.struct_dirlua_monitor_state = null;

// Per-thread Lua entrypoint prefix table
const ENTRYPOINT_COUNT = 14;

const LuaThreadState = struct {
    last_ep: c_int,
    prefix_table: [ENTRYPOINT_COUNT]?[*:0]u8,
};

threadlocal var lua_tls: LuaThreadState = .{
    .last_ep = 0,
    .prefix_table = [_]?[*:0]u8{null} ** ENTRYPOINT_COUNT,
};

// Entrypoint maps
const EpMapEntry = struct {
    maskv: c_int,
    keyv: [*:0]const u8,
};

const ep_map = [_]EpMapEntry{
    .{ .maskv = c.EP_TRIGGER_CLOCK,   .keyv = "clock_pulse" },
    .{ .maskv = c.EP_TRIGGER_MESSAGE, .keyv = "message" },
    .{ .maskv = c.EP_TRIGGER_TRACE,   .keyv = "trace" },
    .{ .maskv = c.EP_TRIGGER_RESET,   .keyv = "reset" },
    .{ .maskv = c.EP_TRIGGER_JOIN,    .keyv = "join" },
    .{ .maskv = c.EP_TRIGGER_LEAVE,   .keyv = "leave" },
    .{ .maskv = c.EP_TRIGGER_INDEX,   .keyv = "index" },
    .{ .maskv = c.EP_TRIGGER_LOAD,    .keyv = "load" },
    .{ .maskv = c.EP_TRIGGER_STORE,   .keyv = "store" },
};

// Maps entrypoint index → suffix appended to appl name to build the function name.
// NULL slots mean "not a callable entrypoint from Lua".
const ep_lut = [ENTRYPOINT_COUNT]?[*:0]const u8{
    null,          // 0: none
    "",            // 1: main
    "_clock_pulse",
    "_message",
    null,          // 4: NBIO_RD
    null,          // 5: NBIO_WR
    null,          // 6: NBIO_DATA
    null,          // 7: TRACE
    "_reset",
    "_join",
    "_leave",
    "_index",
    "_load",
    "_store",
};

// Known userdata metatables for type identification
const udata_list = [_][*:0]const u8{
    "nonblockIO",
    "nonblockIOs",
};

// Internal helpers

fn put_shmif_luastr(msg: [*:0]const u8, out: ?*c.FILE) void {
    var p = msg;
    while (p[0] != 0) {
        if (p[0] == '\n') {
            _ = c.fputc('\\', out);
            _ = c.fputc('n', out);
        } else if (p[0] == '\t') {
            _ = c.fputs("     ", out);
        } else if (p[0] == ':') {
            _ = c.fputs("\t", out);
        } else if (p[0] == ',') {
            _ = c.fputc('\\', out);
        } else {
            _ = c.fputc(p[0], out);
        }
        p += 1;
    }
}

fn match_udata(L: *lua.lua_State, pos: isize) ?[*:0]const u8 {
    if (lua.lua_getmetatable(L, @intCast(pos)) == 0)
        return null;

    for (udata_list) |name| {
        _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, name);
        if (lua.lua_rawequal(L, -1, -2) != 0) {
            lua.lua_settop(L, -3); // pop both metatables
            return name;
        }
        lua.lua_settop(L, -2); // pop the checked MT
    }

    lua.lua_settop(L, -2); // pop the object's MT
    return "(unknown)";
}

fn check_breakpoints(L: ?*lua.lua_State) bool {
    const mon = monitor orelse return false;
    if (mon.n_breakpoints == 0) return false;

    var ar: lua.lua_Debug = undefined;
    if (lua.lua_getstack(L, 0, &ar) == 0) return false;

    _ = lua.lua_getinfo(L, "Snl", &ar);

    var checked: usize = 0;
    var i: usize = 0;
    while (i < c.BREAK_LIMIT and checked < mon.n_breakpoints) : (i += 1) {
        const bp = &mon.breakpoints[i];
        if (bp.bpt.file == null) continue;
        checked += 1;

        const base: [*:0]const u8 = if (ar.source[0] == '@')
            @as([*:0]const u8, @ptrCast(ar.source + 1))
        else
            @as([*:0]const u8, @ptrCast(ar.source));
        const line = bp.bpt.line;
        const source = bp.bpt.file;

        if (ar.currentline != @as(c_int, @intCast(line))) continue;
        if (c.strcmp(base, source) == 0) {
            _ = c.fprintf(mon.out, "#BREAK %s:%zu\n", source, line);
            return true;
        }
    }
    return false;
}

fn strip_arg_lf(arg: [*]u8) [*]u8 {
    const len = c.strlen(arg);
    if (len > 0 and arg[len - 1] == '\n') {
        arg[len - 1] = 0;
        return arg + (len - 1);
    }
    return arg + len;
}

// Traceback handler used with lua_pcall
fn traceback(L: ?*lua.lua_State) callconv(.c) c_int {
    if (lua.lua_isstring(L, 1) == 0) return 1;
    _ = lua.lua_getglobal(L, "debug");
    if (!lua.lua_istable(L, -1)) {
        lua.lua_settop(L, -2);
        return 1;
    }
    _ = lua.lua_getfield(L, -1, "traceback");
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_settop(L, -3);
        return 1;
    }
    lua.lua_pushvalue(L, 1);
    lua.lua_pushinteger(L, 2);
    lua.lua_call(L, 2, 1);
    return 1;
}

// Monitor command implementations

fn cmd_continue(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = L;
    _ = D;
    if (monitor) |m| m.lock = false;
}

fn cmd_dumpstate(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = L;
    _ = D;
    const m = monitor orelse return;
    _ = c.fprintf(m.out, "#BEGINKV\n#LASTSOURCE\n#ENDLASTSOURCE\n#ENDKV\n");
}

fn cmd_reload(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = L;
    _ = D;
    const m = monitor orelse return;
    var beg = c.struct_arcan_event.zeroes();
    beg.unnamed_0.unnamed_0.category = c.EVENT_EXTERNAL;
    beg.unnamed_0.unnamed_0.unnamed_0.ext.kind = @as(c_uint, @bitCast(c.EVENT_EXTERNAL_MESSAGE));
    const reload_msg = "reload";
    @memcpy(beg.unnamed_0.unnamed_0.unnamed_0.ext.unnamed_0.message.data[0..reload_msg.len], reload_msg);
    _ = c.arcan_shmif_enqueue(m.C, &beg);
}

fn cmd_backtrace(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    const m = monitor orelse return;
    const L_arg = L orelse return;

    const out = m.out orelse return;
    _ = c.fprintf(out, "#BEGINBACKTRACE\n");
    dirlua_callstack_raw(L_arg, D, 10, out);
    _ = c.fprintf(out, "#ENDBACKTRACE\n");

    _ = c.fprintf(out, "#BEGINSTACK\n");
    dirlua_dumpstack_raw(L_arg, out);
    _ = c.fprintf(out, "#ENDSTACK\n");
}

fn cmd_locals(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = L;
    _ = D;
    // stub — not yet implemented in upstream either
}

fn cmd_stepend(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse {
        _ = c.fprintf(m.out, "#ERROR no Lua state\n");
        return;
    };
    _ = lua.lua_sethook(L_arg, dirlua_monitor_watchdog, lua.LUA_MASKRET, 1);
    m.lock = false;
    m.stepreq = true;
    m.dumppause = true;
}

fn cmd_stepline(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse {
        _ = c.fprintf(m.out, "#ERROR no Lua state\n");
        return;
    };
    _ = lua.lua_sethook(L_arg, dirlua_monitor_watchdog, lua.LUA_MASKLINE, 1);
    m.lock = false;
    m.stepreq = true;
    m.dumppause = true;
}

fn cmd_stepcall(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = arg;
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse return;
    _ = lua.lua_sethook(L_arg, dirlua_monitor_watchdog, lua.LUA_MASKRET, 1);
    m.lock = false;
    m.stepreq = true;
    m.dumppause = true;
}

fn cmd_stepinstruction(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse {
        _ = c.fprintf(m.out, "#ERROR No Lua state\n");
        return;
    };
    var count: c_long = 1;
    if (c.strlen(arg) > 0) {
        count = c.strtol(@ptrCast(arg), null, 10);
    }
    _ = lua.lua_sethook(L_arg, dirlua_monitor_watchdog, lua.LUA_MASKCALL, @intCast(count));
    m.lock = false;
    m.stepreq = true;
    m.dumppause = true;
}

fn cmd_source(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = L;
    _ = D;
    const m = monitor orelse return;
    // strip leading '@' if present (debug protocol prefix)
    var src: [*:0]const u8 = @ptrCast(arg);
    if (arg[0] == '@') src = @ptrCast(arg + 1);
    _ = strip_arg_lf(arg);

    var indata = arcan_open_resource(src);
    const reg = arcan_map_resource(&indata, false);
    if (reg.ptr == null) {
        _ = c.fprintf(m.out, "#ERROR couldn't map Lua source ref: %s\n", src);
    } else {
        _ = c.fprintf(m.out, "#BEGINSOURCE\n");
        _ = c.fprintf(m.out, "%s\n%s\n", src, reg.ptr.?);
        _ = c.fprintf(m.out, "#ENDSOURCE\n");
    }
    arcan_release_map(reg);
    arcan_release_resource(&indata);
}

fn cmd_eval(argv: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse return;

    const status = lua.luaL_loadbuffer(L_arg, argv, c.strlen(argv), "eval");
    if (status != 0) {
        const msg = lua.lua_tolstring(L_arg, -1, null);
        _ = c.fprintf(m.out, "#BADRESULT\n%s\n#ENDBADRESULT\n",
            if (msg != null) @as([*c]const u8, msg) else @as([*c]const u8, "(error object is not a string)"));
        _ = c.fflush(m.out);
        lua.lua_settop(L_arg, -2);
        return;
    }

    const base = lua.lua_gettop(L_arg);
    lua.lua_pushcfunction(L_arg, traceback);
    lua.lua_insert(L_arg, base);

    _ = c.fprintf(m.out, "#BEGINRESULT\n");

    const rc = lua.lua_pcall(L_arg, 0, lua.LUA_MULTRET, base);
    lua.lua_remove(L_arg, base);

    if (rc != 0) {
        _ = lua.lua_gc(L_arg, lua.LUA_GCCOLLECT);
        const msg = lua.lua_tolstring(L_arg, -1, null);
        if (msg != null) {
            _ = c.fprintf(m.out, "%s%s\n",
                @as([*c]const u8, if (msg.?[0] == '#') "\\" else ""), @as([*c]const u8, msg.?));
        } else {
            _ = c.fprintf(m.out, "(error object is not a string)\n");
        }
    } else if (lua.lua_type(L_arg, -1) != lua.LUA_TNIL) {
        dirlua_print_type(L_arg, -1, "", m.out);
        _ = c.fputc('\n', m.out);
    }

    _ = c.fprintf(m.out, "#ENDRESULT\n");
    _ = c.fflush(m.out);
}

// Table navigation helpers for cmd_dumptable

fn local_to_table(tokctx: *[*c]u8, L: *lua.lua_State, m_out: ?*c.FILE) void {
    var ar: lua.lua_Debug = undefined;
    var gotframe = false;

    while (true) {
        const tok = c.strtok_r(null, " ", tokctx) orelse break;
        var err: [*c]u8 = undefined;
        const val = c.strtoul(tok, @ptrCast(&err), 10);
        if (err[0] != 0) {
            _ = c.fprintf(m_out, "#ERROR gettable: missing %s reference\n",
                @as([*c]const u8, if (gotframe) "local" else "frame"));
            return;
        }
        if (!gotframe) {
            if (lua.lua_getstack(L, @intCast(val), &ar) == 0) {
                _ = c.fprintf(m_out, "#ERROR gettable: invalid frame %ld\n", val);
                return;
            }
            gotframe = true;
        } else {
            _ = lua.lua_getlocal(L, &ar, @intCast(val));
            return;
        }
    }
}

fn stack_to_table(tokctx: *[*c]u8, L: *lua.lua_State, out: ?*c.FILE) void {
    while (true) {
        const tok = c.strtok_r(null, " ", tokctx) orelse break;
        var err: [*c]u8 = undefined;
        const index = c.strtoul(tok, @ptrCast(&err), 10);
        if (err[0] != 0) {
            _ = c.fprintf(out, "#ERROR gettable: missing stack reference\n");
        } else if (lua.lua_type(L, @intCast(index)) == lua.LUA_TTABLE) {
            lua.lua_pushvalue(L, @intCast(index));
        }
        return;
    }
}

fn cmd_dumptable(argv: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = D;
    const m = monitor orelse return;
    const L_arg = L orelse return;

    _ = strip_arg_lf(argv);

    var argi: c_int = 0;
    var tokctx: [*c]u8 = null;
    const top = lua.lua_gettop(L_arg);

    var first: [*c]u8 = argv;
    while (true) {
        const tok = c.strtok_r(first, " ", &tokctx) orelse break;
        first = null;

        if (argi != 0) {
            var err: [*c]u8 = undefined;
            const skip_n_ul = c.strtoul(tok, @ptrCast(&err), 10);
            if (err[0] != 0) {
                _ = c.fprintf(m.out, "#ERROR gettable: couldn't parse index\n");
                break;
            }
            var skip_n = skip_n_ul;
            if (lua.lua_type(L_arg, -1) != lua.LUA_TTABLE) {
                _ = c.fprintf(m.out, "#ERROR gettable: resolved index is not a table\n");
                break;
            }
            lua.lua_pushnil(L_arg);
            while (lua.lua_next(L_arg, -2) != 0 and skip_n > 0) {
                lua.lua_settop(L_arg, -2);
                skip_n -= 1;
            }
            lua.lua_remove(L_arg, -2); // remove iteration key
        }

        if (argi == 0) {
            switch (tok[0]) {
                'g' => lua.lua_pushglobaltable(L_arg),
                's' => stack_to_table(&tokctx, L_arg, m.out),
                'l' => local_to_table(&tokctx, L_arg, m.out),
                else => {
                    _ = c.fprintf(m.out, "#ERROR gettable: bad domain selector\n");
                    lua.lua_settop(L_arg, top);
                    return;
                },
            }
            argi += 1;
        }
    }

    if (lua.lua_type(L_arg, -1) != lua.LUA_TTABLE) {
        _ = c.fprintf(m.out, "#ERROR gettable: resolved index is not a table\n");
    } else {
        _ = c.fprintf(m.out, "#BEGINTABLE\n");
        dirlua_dumptable_raw(L_arg, 0, 0, m.out);
        _ = c.fprintf(m.out, "#ENDTABLE\n");
    }

    _ = c.fflush(m.out);
    lua.lua_settop(L_arg, top);
}

fn cmd_breakpoint(argv: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    const m = monitor orelse return;
    const len = c.strlen(argv);

    // Dump current set if no argument
    if (len == 0 or len == 1) {
        _ = c.fprintf(m.out, "#BEGINBREAK\n");
        var i: usize = 0;
        var checked: usize = 0;
        while (i < c.BREAK_LIMIT and checked < m.n_breakpoints) : (i += 1) {
            if (m.breakpoints[i].bpt.file) |f| {
                _ = c.fprintf(m.out, "file=%s:line=%zu\n", f, m.breakpoints[i].bpt.line);
                checked += 1;
            }
        }
        _ = c.fprintf(m.out, "#ENDBREAK\n");
        return;
    }

    var endptr = strip_arg_lf(argv);
    var line: c_ulong = 0;

    // Scan backwards for ':'
    while (endptr != argv and endptr[0] != ':') endptr -= 1;

    if (endptr[0] == ':') {
        endptr[0] = 0;
        endptr += 1;
        if (c.strlen(endptr) == 0) {
            _ = c.fprintf(m.out, "#ERROR breakpoint: expected file:line\n");
            return;
        }
        var err: [*]u8 = undefined;
        line = c.strtoul(@ptrCast(endptr), @ptrCast(&err), 10);
        if (err[0] != 0) {
            _ = c.fprintf(m.out, "#ERROR breakpoint: malformed line specifier\n");
            return;
        }
    }

    // Toggle: if already present, remove it
    var i: usize = 0;
    var checked: usize = 0;
    while (i < c.BREAK_LIMIT and checked < m.n_breakpoints) : (i += 1) {
        if (m.breakpoints[i].bpt.file == null) continue;
        checked += 1;
        if (m.breakpoints[i].bpt.line == line and
            c.strcmp(m.breakpoints[i].bpt.file, argv) == 0)
        {
            c.free(m.breakpoints[i].bpt.file);
            m.breakpoints[i].bpt.file = null;
            m.n_breakpoints -= 1;
            return;
        }
    }

    // Add
    if (m.n_breakpoints == c.BREAK_LIMIT) {
        _ = c.fprintf(m.out, "#ERROR breakpoint: limit filled\n");
        return;
    }

    i = 0;
    while (i < c.BREAK_LIMIT) : (i += 1) {
        if (m.breakpoints[i].bpt.file == null) {
            m.breakpoints[i].bpt.file = c.strdup(argv);
            m.breakpoints[i].bpt.line = line;
            if (m.breakpoints[i].bpt.file != null) {
                m.n_breakpoints += 1;
            } else {
                _ = c.fprintf(m.out, "#ERROR breakpoint: out of memory\n");
            }
            break;
        }
    }

    // Re-dump the updated set
    var empty: [1]u8 = .{0};
    cmd_breakpoint(@ptrCast(&empty), L, D);
}

fn cmd_entrypoint(arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void {
    _ = L;
    _ = D;
    const m = monitor orelse return;

    _ = strip_arg_lf(arg);

    var mask_kind: u64 = 0;
    var tokctx: [*c]u8 = null;
    var first: [*c]u8 = arg;
    while (true) {
        const tok = c.strtok_r(first, " ", &tokctx) orelse break;
        first = null;
        mask_kind |= dirlua_strtoep(tok);
    }
    m.hook_mask = @intCast(mask_kind);
}

// Command dispatch table
const CmdEntry = struct {
    word: [*:0]const u8,
    ptr: *const fn (arg: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) void,
};

const cmds = [_]CmdEntry{
    .{ .word = "continue",        .ptr = cmd_continue },
    .{ .word = "dumpstate",       .ptr = cmd_dumpstate },
    .{ .word = "reload",          .ptr = cmd_reload },
    .{ .word = "backtrace",       .ptr = cmd_backtrace },
    .{ .word = "eval",            .ptr = cmd_eval },
    .{ .word = "locals",          .ptr = cmd_locals },
    .{ .word = "stepnext",        .ptr = cmd_stepline },
    .{ .word = "stepend",         .ptr = cmd_stepend },
    .{ .word = "stepcall",        .ptr = cmd_stepcall },
    .{ .word = "stepinstruction", .ptr = cmd_stepinstruction },
    .{ .word = "table",           .ptr = cmd_dumptable },
    .{ .word = "source",          .ptr = cmd_source },
    .{ .word = "breakpoint",      .ptr = cmd_breakpoint },
    .{ .word = "entrypoint",      .ptr = cmd_entrypoint },
};

// Vendored lua_load-via-dirfd (mirrors alt/support.c)
const LUAL_BUFFERSIZE = 4096;

const LoadF = struct {
    extraline: c_int,
    f: *c.FILE,
    buff: [LUAL_BUFFERSIZE]u8,
};

fn getF(L: ?*lua.lua_State, ud: ?*anyopaque, size: [*c]usize) callconv(.c) [*c]const u8 {
    _ = L;
    const lf: *LoadF = @ptrCast(@alignCast(ud.?));
    if (lf.extraline != 0) {
        lf.extraline = 0;
        size.* = 1;
        return @as([*c]const u8, "\n");
    }
    if (c.feof(lf.f) != 0) return null;
    size.* = c.fread(&lf.buff, 1, LUAL_BUFFERSIZE, lf.f);
    return if (size.* > 0) @as([*c]const u8, @ptrCast(&lf.buff)) else null;
}

// Public API

pub export fn dirlua_dumptable_raw(L: *lua.lua_State, ofs: c_int, cap: c_int, out: ?*c.FILE) void {
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) return;

    lua.lua_pushnil(L);
    var ind: c_int = 0;
    var skip = ofs;
    var remaining_cap = cap;

    while (lua.lua_next(L, -2) != 0) {
        if (skip > 0) {
            // Still in the skip window — count down and continue
            skip -= 1;
            lua.lua_settop(L, -2);
            continue;
        }
        _ = c.fprintf(out, "type=table:index=%d:", ind);
        ind += 1;
        switch (lua.lua_type(L, -2)) {
            lua.LUA_TNUMBER => _ = c.fprintf(out, "keytype=number:tblkey=%.14g:", lua.lua_tonumber(L, -2)),
            lua.LUA_TSTRING => {
                _ = c.fputs("keytype=string:tblkey=", out);
                put_shmif_luastr(lua.lua_tolstring(L, -2, null), out);
                _ = c.fputc(':', out);
            },
            lua.LUA_TBOOLEAN => _ = c.fprintf(out, "keytype=bool:tblkey=%s:",
                @as([*c]const u8, if (lua.lua_toboolean(L, -2) != 0) "true" else "false")),
            lua.LUA_TFUNCTION => _ = c.fputs("keytype=function:tblkey=func:", out),
            lua.LUA_TTABLE    => _ = c.fputs("keytype=table:tblkey=table:", out),
            else            => _ = c.fputs("keytype=unknown:tblkey=unknown:", out),
        }
        _ = c.fputs("var", out);
        dirlua_print_type(L, -1, "\n", out);
        lua.lua_settop(L, -2); // pop value
        if (cap != 0) {
            remaining_cap -= 1;
            if (remaining_cap == 0) break;
        }
    }
    // In case we broke early, lua_next left the last key on the stack; pop it.
    // When the loop exhausted normally lua_next already cleaned up.
    // Safe to call: if nothing is left this is a no-op relative to table.
    lua.lua_settop(L, -2);
}

pub export fn dirlua_print_type(L: *lua.lua_State, i: c_int, suffix: [*:0]const u8, out: ?*c.FILE) void {
    switch (lua.lua_type(L, i)) {
        lua.LUA_TNUMBER => _ = c.fprintf(out, "type=number:value=%.14g", lua.lua_tonumber(L, i)),
        lua.LUA_TUSERDATA => {
            const name = match_udata(L, i) orelse "(unknown)";
            _ = c.fprintf(out, "type=userdata:name=%s\n", name);
        },
        lua.LUA_TFUNCTION => {
            var ar: lua.lua_Debug = undefined;
            lua.lua_pushvalue(L, i);
            _ = lua.lua_getinfo(L, ">Snl", &ar); // pops -1
            _ = c.fprintf(out,
                "type=func:name=%s:kind=%s:source=%s:start=%d:end=%d",
                @as([*c]const u8, if (ar.name != null) ar.name else "(null)"),
                @as([*c]const u8, if (ar.namewhat != null) ar.namewhat else "(null)"),
                ar.source,
                ar.linedefined,
                ar.lastlinedefined);
        },
        lua.LUA_TSTRING => {
            const msg = lua.lua_tolstring(L, i, null);
            _ = c.fputs("type=string:value=", out);
            put_shmif_luastr(msg, out);
        },
        lua.LUA_TBOOLEAN => _ = c.fputs(
            if (lua.lua_toboolean(L, i) != 0) "type=bool:value=true" else "type=bool:value=false",
            out),
        lua.LUA_TTABLE => {
            const nelems: c_int = @intCast(lua.lua_objlen(L, i));
            lua.lua_pushvalue(L, i);
            lua.lua_pushnil(L);
            var n_keys: usize = 0;
            while (lua.lua_next(L, -2) != 0) {
                lua.lua_settop(L, -2);
                n_keys += 1;
            }
            lua.lua_settop(L, -2);
            _ = c.fprintf(out, "type=table:length=%d:keys=%zu", nelems, n_keys);
        },
        lua.LUA_TNIL => _ = c.fputs("type=nil", out),
        else => {},
    }
    _ = c.fputs(suffix, out);
}

pub export fn dirlua_monitor_panic(L: *lua.lua_State, D: *lua.lua_Debug) void {
    const m = monitor orelse return;
    m.dumppause = true;
    m.@"error" = true;
    m.lock = true;
    dirlua_monitor_watchdog(L, D);
    m.stepreq = false;
}

pub export fn dirlua_hookmask(mask: u64, bkpt: bool) void {
    const m = monitor orelse return;
    m.in_breakpoint_set = bkpt;
    m.hook_mask = @intCast(mask);
}

pub export fn dirlua_eptostr(ep: u64) [*:0]const u8 {
    for (ep_map) |e| {
        if (@as(u64, @intCast(e.maskv)) == ep) return e.keyv;
    }
    return "(bad)";
}

pub export fn dirlua_strtoep(ep: [*:0]const u8) u64 {
    for (ep_map) |e| {
        if (c.strcmp(e.keyv, ep) == 0) return @intCast(e.maskv);
    }
    return 0;
}

pub export fn dirlua_pcall_prefix(L: *lua.lua_State, name: ?[*:0]const u8) void {
    _ = L;
    // Free existing prefix table
    for (&lua_tls.prefix_table) |*slot| {
        if (slot.*) |old| {
            c.free(old);
            slot.* = null;
        }
    }

    const n = name orelse return;
    if (n[0] == 0) return;

    for (ep_lut, 0..) |maybe_suffix, i| {
        const suffix = maybe_suffix orelse continue;
        var buf: ?[*:0]u8 = null;
        _ = c.asprintf(@ptrCast(&buf), "%s%s", n, suffix);
        lua_tls.prefix_table[i] = buf;
    }
}

pub export fn dirlua_setup_entrypoint(L: *lua.lua_State, ep: c_int) bool {
    if (ep <= 0 or ep >= ENTRYPOINT_COUNT) return false;
    const fn_name = lua_tls.prefix_table[@intCast(ep)] orelse return false;

    _ = lua.lua_getglobal(L, fn_name);
    if (!lua.lua_isfunction(L, -1)) {
        lua.lua_settop(L, -2);
        return false;
    }

    if (monitor) |m| {
        if ((m.hook_mask & @as(c_int, ep)) != 0) {
            _ = lua.lua_sethook(L, dirlua_monitor_watchdog, lua.LUA_MASKLINE, 1);
            m.dumppause = true;
        }
    }

    lua_tls.last_ep = ep;
    return true;
}

pub export fn dirlua_pcall(L: *lua.lua_State, nargs: c_int, nret: c_int, panic_fn: *const fn (?*lua.lua_State) callconv(.c) c_int) void {
    const errind = lua.lua_gettop(L) - nargs;
    lua.lua_pushcfunction(L, panic_fn);
    lua.lua_insert(L, errind);
    _ = lua.lua_pcall(L, nargs, nret, errind);
    lua.lua_remove(L, errind);
    lua_tls.last_ep = 0;
}

pub export fn dirlua_callstack_raw(L: *lua.lua_State, D: ?*lua.lua_Debug, levels: c_int, out: *c.FILE) void {
    _ = D;
    _ = c.fprintf(out, "type=entrypoint:kind=%s\n", dirlua_eptostr(@intCast(lua_tls.last_ep)));

    var level: c_int = 0;
    var ar: lua.lua_Debug = undefined;
    while (lua.lua_getstack(L, level, &ar) != 0 and level < levels) : (level += 1) {
        _ = lua.lua_getinfo(L, "Slnu", &ar);
        _ = c.fprintf(out,
            "type=stacktrace:frame=%d:name=%s:" ++
            "kind=%s:source=%s:current=%d:start=%d:end=%d:upvalues=%d\n",
            level,
            @as([*c]const u8, if (ar.name != null) ar.name else "(null)"),
            @as([*c]const u8, if (ar.namewhat != null) ar.namewhat else "(null)"),
            ar.source,
            ar.currentline,
            ar.linedefined,
            ar.lastlinedefined,
            ar.nups);

        var argi: c_int = 1;
        while (true) {
            const name = lua.lua_getlocal(L, &ar, argi) orelse break;
            _ = c.fprintf(out, "type=local:index=%d:name=%s:var", argi, name);
            dirlua_print_type(L, -1, "", out);
            _ = c.fputc('\n', out);
            lua.lua_settop(L, -2);
            argi += 1;
        }

        // varargs (negative indices in Lua 5.1)
        argi = -1;
        while (true) {
            const name = lua.lua_getlocal(L, &ar, argi) orelse break;
            _ = c.fprintf(out, "type=local:index=%d:vararg:name=%s:var", argi, name);
            dirlua_print_type(L, -1, "", out);
            _ = c.fputc('\n', out);
            lua.lua_settop(L, -2);
            argi -= 1;
        }
    }
}

pub export fn dirlua_monitor_watchdog(L: ?*lua.lua_State, D: [*c]lua.lua_Debug) callconv(.c) void {
    const m = monitor orelse return;

    if (!check_breakpoints(L) and
        m.n_breakpoints > 0 and
        !m.stepreq and
        !m.@"error" and
        !m.transaction)
    {
        return;
    }

    if (m.dumppause) {
        _ = c.fprintf(m.out, "#WAITING\n");
        m.dumppause = false;
        var empty: [1]u8 = .{0};
        cmd_backtrace(@ptrCast(&empty), L, D);
    }

    m.lock = true;
}

pub export fn dirlua_monitor_command(cmd: [*]u8, L: ?*lua.lua_State, D: ?*lua.lua_Debug) bool {
    var i: usize = 0;
    while (cmd[i] != 0 and cmd[i] != '\n' and cmd[i] != ' ') : (i += 1) {}

    var arg: [*]u8 = cmd + i;
    if (cmd[i] != 0) {
        if (cmd[i] != '\n') arg += 1;
        cmd[i] = 0;
    }

    for (cmds) |entry| {
        if (c.strcasecmp(cmd, entry.word) == 0) {
            entry.ptr(arg, L, D);
            return true;
        }
    }
    return false;
}

pub export fn dirlua_dumpstack_raw(L: *lua.lua_State, out: *c.FILE) void {
    var top = lua.lua_gettop(L);
    while (top > 0) : (top -= 1) {
        _ = c.fprintf(out, "type=stack:index=%d:name=%d:var", top, top);
        dirlua_print_type(L, top, "\n", out);
    }
}

pub export fn dirlua_monitor_getstate() ?*c.struct_dirlua_monitor_state {
    return monitor;
}

pub export fn dirlua_monitor_flush(out_buf: *[*:0]u8) usize {
    const m = monitor orelse return 0;
    _ = c.fflush(m.out);
    out_buf.* = @ptrCast(m.out_buf);
    return m.out_sz;
}

pub export fn dirlua_monitor_releasestate(L: *lua.lua_State) void {
    const m = monitor orelse return;

    _ = c.fclose(m.out);
    c.free(m.out_buf);

    _ = lua.lua_sethook(L, null, lua.LUA_MASKLINE, 1);
    _ = lua.lua_sethook(L, null, lua.LUA_MASKRET, 1);
    _ = lua.lua_sethook(L, null, lua.LUA_MASKCALL, 1);

    c.free(m);
    monitor = null;
}

pub export fn dirlua_monitor_allocstate(C: *c.struct_arcan_shmif_cont) void {
    const m: *c.struct_dirlua_monitor_state = @ptrCast(@alignCast(
        c.malloc(@sizeOf(c.struct_dirlua_monitor_state)).?
    ));
    @memset(std.mem.asBytes(m), 0);
    m.C = C;
    m.lock = true;
    m.out = c.open_memstream(@ptrCast(&m.out_buf), &m.out_sz);
    monitor = m;
}

pub export fn dirlua_loadfile(L: *lua.lua_State, dfd: c_int, filename: [*:0]const u8, dieonfail: bool) c_int {
    var lf: LoadF = undefined;
    lf.extraline = 0;

    const fnameindex = lua.lua_gettop(L) + 1;

    const fd = c.openat(dfd, filename, c.O_RDONLY);
    if (fd == -1) {
        if (dieonfail) {
            _ = lua.luaL_error(L, "system_load(%s) can't be opened", filename);
        }
        lua.lua_pushboolean(L, 0);
        return 1;
    }

    _ = lua.lua_pushfstring(L, "@%s", filename);
    lf.f = c.fdopen(fd, "r") orelse {
        if (dieonfail) {
            _ = lua.luaL_error(L, "system_load:fdopen(%d) failed", fd);
        }
        lua.lua_pushboolean(L, 0);
        return 1;
    };

    var ch = c.getc(lf.f);
    if (ch == '#') {
        lf.extraline = 1;
        // skip to end of first line
        while (true) {
            ch = c.getc(lf.f);
            if (ch == c.EOF or ch == '\n') break;
        }
        if (ch == '\n') ch = c.getc(lf.f);
    }

    // Reject bytecode
    if (ch == lua.LUA_SIGNATURE[0]) {
        _ = c.fclose(lf.f);
        if (dieonfail) {
            _ = lua.luaL_error(L, "system_load(%s) - bytecode forbidden", filename);
        }
        lua.lua_pushboolean(L, 0);
        return 1;
    }

    _ = c.ungetc(ch, lf.f);

    const status = lua.lua_load(L, getF, &lf, lua.lua_tolstring(L, -1, null), null);
    if (status != 0) {
        _ = c.fclose(lf.f);
        if (dieonfail) {
            _ = lua.luaL_error(L, "system_load(%s):%s\n", lua.lua_tolstring(L, -1, null));
        }
        lua.lua_settop(L, fnameindex);
        lua.lua_pushboolean(L, 0);
        return 0; // matches C: returns false (0)
    }

    const readstatus = c.ferror(lf.f);
    _ = c.fclose(lf.f);
    if (readstatus != 0) {
        lua.lua_settop(L, fnameindex);
        if (dieonfail) {
            _ = lua.luaL_error(L, "system_load(%s):lua_load failed", filename);
        }
        return 1;
    }

    lua.lua_remove(L, fnameindex);
    return 1;
}
