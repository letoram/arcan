// Pure Zig port of engine/alt/support.c — Lua VM crash recovery,
// call wrappers, script loading, and entry-point lookup.
//
// Uses extern C declarations for Lua API and libc functions.

const std = @import("std");
const c = @import("arcan_boot_compat");

// Re-export types and functions from boot_compat for local use
const lua_State = c.lua_State;
const lua_CFunction = c.lua_CFunction;
const lua_Number = c.lua_Number;
const arcan_vobj_id = c.arcan_vobj_id;

// Lua API — all from boot_compat (handles LuaJIT→Lua5.4 compat)
const lua_gettop = c.lua_gettop;
const lua_settop = c.lua_settop;
const lua_type = c.lua_type;
const lua_pcall = c.lua_pcall;
const lua_pushcclosure = c.lua_pushcclosure;
const lua_insert = c.lua_insert;
const lua_remove = c.lua_remove;
const lua_toboolean = c.lua_toboolean;
const lua_tonumber = c.lua_tonumber;
const lua_tolstring = c.lua_tolstring;
const lua_getfield = c.lua_getfield;
const lua_pushvalue = c.lua_pushvalue;
const lua_pushstring = c.lua_pushstring;
const lua_sethook = c.lua_sethook;
const luaL_checknumber = c.luaL_checknumber;
const luaL_optlstring = c.luaL_optlstring;
const luaL_loadbuffer = c.luaL_loadbuffer;

// Lua API — from boot_compat
const lua_pushfstring = c.lua_pushfstring;
const lua_pushliteral_helper = c.lua_pushliteral_helper;
const lua_atpanic = c.lua_atpanic;
const lua_load = c.lua_load;
const lua_typename = c.lua_typename;

// Lua macro wrappers
fn lua_pushcfunction(L: ?*lua_State, f: lua_CFunction) void { c.lua_pushcclosure(L, f, 0); }
fn lua_getglobal(L: ?*lua_State, name: [*c]const u8) void { _ = c.lua_getglobal(L, name); }
fn lua_isfunction(L: ?*lua_State, idx: c_int) c_int { return if (c.lua_type(L, idx) == c.LUA_TFUNCTION) 1 else 0; }
fn luaL_optstring(L: ?*lua_State, narg: c_int, def: [*c]const u8) [*c]const u8 { return c.luaL_optlstring(L, narg, def, null); }

// Lua constants
const LUA_TFUNCTION = c.LUA_TFUNCTION;
const LUA_TBOOLEAN = c.LUA_TBOOLEAN;
const LUA_TSTRING = c.LUA_TSTRING;
const LUA_TNUMBER = c.LUA_TNUMBER;
const LUA_MASKLINE: c_int = 2;
const LUA_ERRFILE: c_int = 6;
const LUA_REGISTRYINDEX = c.LUA_REGISTRYINDEX;
const LUA_GLOBALSINDEX = c.LUA_GLOBALSINDEX;
const LUA_SIGNATURE_BYTE: c_int = 0x1b;

// arcan engine — from boot_compat
const arcan_vobject = c.arcan_vobject;
const arcan_video_getobject = c.arcan_video_getobject;
const arcan_fatal = c.arcan_fatal;
const arcan_warning = c.arcan_warning;
const arcan_trace_setbuffer = c.arcan_trace_setbuffer;
const arcan_monitor_watchdog = c.arcan_monitor_watchdog;

// arcan engine — from boot_compat
const arcan_state_dump = c.arcan_state_dump;
const arcan_monitor_watchdog_error = c.arcan_monitor_watchdog_error;
const arcan_monitor_masktrigger = c.arcan_monitor_masktrigger;
const luavid_tovid = c.luavid_tovid;
const vid_toluavid = c.vid_toluavid;

// alt subsystem — from boot_compat
const alt_trace_callstack_raw = c.alt_trace_callstack_raw;
const alt_trace_dumpstack_raw = c.alt_trace_dumpstack_raw;
const alt_trace_callstack = c.alt_trace_callstack;
const alt_trace_set_crash_source = c.alt_trace_set_crash_source;
const alt_trace_crash_source = c.alt_trace_crash_source;
const alt_trace_finish = c.alt_trace_finish;
const alt_nbio_release = c.alt_nbio_release;

// bootstrap Lua source — embedded at comptime via a module at src/engine/ level
// (Zig restricts @embedFile to files within the package directory tree,
//  and support.zig lives in src/engine/alt/, so we import from a parent-level module)
const arcan_bootstrap_lua_data = @import("bootstrap_embed").data;

// recovery longjmp target
const ARCAN_LUA_RECOVERY_SWITCH: c_int = 1;
const ARCAN_LUA_RECOVERY_FATAL_IGNORE: c_int = 2;

// libc — from boot_compat
const FILE = c.FILE;
const fopen = c.fopen;
const fclose = c.fclose;
const feof = c.feof;
const fread = c.fread;
const fputc = c.fputc;
const fflush = c.fflush;
const fprintf = c.fprintf;
const vfprintf = c.vfprintf;
const open_memstream = c.open_memstream;
const getc = c.getc;
const ungetc = c.ungetc;
const ferror = c.ferror;
const free = c.free;
const strlen = c.strlen;
const snprintf = c.snprintf;
const strerror = c.strerror;
const __errno_location = c.__errno_location;
fn get_errno() c_int {
    return __errno_location().*;
}


// arcan trace
// boot_compat's arcan_trace_mark has 10 params; wrap to supply defaults for file/func/line
fn arcan_trace_mark(sys: [*c]const u8, sub: [*c]const u8, trigger: u8, tracelevel: u8, ident: u64, quant: u32, msg: [*c]const u8) void {
    c.arcan_trace_mark(sys, sub, trigger, tracelevel, ident, quant, msg, "support.zig", "", 0);
}

// longjmp wrapper — casts arcanmain_recover_state ptr and marks noreturn
fn longjmp(env: *anyopaque, val: c_int) noreturn {
    c.longjmp(@ptrCast(@alignCast(env)), val);
    unreachable;
}

const TRACE_SYS_ERROR: u8 = 4;

// Constants from alt/types.h
const CB_SOURCE_NONE: c_int = 0;
const EP_TRIGGER_HANDOVER: u64 = (1 << 22);
const EP_TRIGGER_TRACE: u64 = (1 << 23);

// LINE_TAG — Zig cannot do __LINE__ at compile time in the same way,
// so we provide meaningful source location strings instead
const LINE_TAG_FATAL_HANDOVER = "support.zig:fatal_handover";
const LINE_TAG_TRACE = "support.zig:trace";

// LUAL_BUFFERSIZE (from luaconf.h, typically 512 or BUFSIZ)
const LUAL_BUFFERSIZE: usize = 8192;

// COUNT_OF helper
fn COUNT_OF(comptime arr: anytype) usize {
    return arr.len;
}

// Static state
const prefix_maxlen: usize = 34;
var prefix_buf: [128]u8 = [_]u8{0} ** 128;
var prefix_len: usize = 0;

var callback_source: struct {
    kind: c_int = 0,
    maskkind: i64 = 0,
    luavid: arcan_vobj_id = 0,
    vid: arcan_vobj_id = 0,
} = .{};

var hook_mask: u64 = 0;
var fatal_context: ?*lua_State = null;

// externally set in main as part of -g -g or in _lua if the script modifies DEBUGLEVEL
export var lua_debug_level: c_uint = 0;

// crash recovery state
var in_panic_state: bool = false;
var in_fatal_state: bool = false;
var in_breakpoint_set: bool = false;

var trace_out: ?*FILE = null;

// (wraperr is defined below, no forward declaration needed in Zig)

// alt_trace_hookmask
export fn alt_trace_hookmask(mask: u64, bkpt: bool) void {
    in_breakpoint_set = bkpt;
    hook_mask = mask;
}

// alt_trace_cbstate
export fn alt_trace_cbstate(kind: *u64, luavid: *i64, vid: *i64) void {
    kind.* = @bitCast(callback_source.maskkind);
    vid.* = callback_source.vid;
    luavid.* = callback_source.luavid;
}

// dump_stack
fn dump_stack(L: ?*lua_State, dst: ?*FILE) void {
    const top = lua_gettop(L);
    _ = fprintf(dst, "-- stack dump (%d)--\n", top);

    var i: c_int = 1;
    while (i <= top) : (i += 1) {
        const t = lua_type(L, i);

        switch (t) {
            LUA_TBOOLEAN => {
                const bval: [*c]const u8 = if (lua_toboolean(L, i) != 0) "true" else "false";
                _ = fprintf(dst, "%d\t %s\n", i, bval);
            },
            LUA_TSTRING => {
                _ = fprintf(dst, "%d\t'%s'\n", i, lua_tolstring(L, i, null));
            },
            LUA_TNUMBER => {
                _ = fprintf(dst, "%d\t%g\n", i, lua_tonumber(L, i));
            },
            else => {
                _ = fprintf(dst, "%d\t%s\n", i, lua_typename(L, t));
            },
        }
    }

    _ = fputc('\n', dst);
    _ = fflush(dst);
}

// luaL_checkvid
export fn luaL_checkvid(
    L: ?*lua_State,
    num: c_int,
    dptr: ?*?*arcan_vobject,
) arcan_vobj_id {
    const lnum = luaL_checknumber(L, num);
    const res = luavid_tovid(lnum);

    if (dptr) |dp| {
        dp.* = arcan_video_getobject(res);
        if (dp.* == null) {
            arcan_fatal("invalid VID requested (%lld)\n", @as(c_longlong, res));
        }
    }

    return res;
}

// wrap_trace_callstack_raw (error handler for pcall with tracing)
fn wrap_trace_callstack_raw_fn(L: ?*lua_State) callconv(.c) c_int {
    _ = fprintf(trace_out, "#BEGINBACKTRACE\n");
    alt_trace_callstack_raw(L, null, 10, trace_out);
    _ = fprintf(trace_out, "#ENDBACKTRACE\n");

    _ = fprintf(trace_out, "#BEGINSTACK\n");
    alt_trace_dumpstack_raw(L, trace_out);
    _ = fprintf(trace_out, "#ENDSTACK\n");

    return 1;
}

// wrap_trace_callstack (error handler for pcall without tracing)
fn wrap_trace_callstack_fn(L: ?*lua_State) callconv(.c) c_int {
    if (alt_lookup_entry(L, "fatal", 5)) {
        lua_pushvalue(L, -2);
        _ = lua_pcall(L, 1, 1, 0);
    } else {
        var buf: [*c]u8 = undefined;
        var buf_sz: usize = undefined;
        const stream = open_memstream(&buf, &buf_sz);
        if (stream) |s| {
            _ = fprintf(s, "error: %s\n\n", lua_tolstring(L, -1, null));
            alt_trace_callstack(L, s);
            _ = fflush(s);
            lua_pushstring(L, buf);
            _ = fclose(s);
            free(@ptrCast(buf));
        } else {
            lua_pushstring(L, "(open_memstream fail, can't build trace)");
        }
    }
    return 1;
}

// alt_call
export fn alt_call(
    L: ?*lua_State,
    cbkind: c_int,
    masksrc: u64,
    source: usize,
    nargs: c_int,
    retc: c_int,
    src: [*c]const u8,
) void {
    // Safeguard: first argument must be a function
    if (lua_type(L, -(nargs + 1)) != LUA_TFUNCTION) {
        dump_stack(L, c.stderr);
        lua_settop(L, 0);
        return;
    }

    callback_source.luavid = @intFromFloat(vid_toluavid(@intCast(source)));
    callback_source.vid = @intCast(source);
    callback_source.kind = cbkind;
    callback_source.maskkind = @bitCast(masksrc);

    const errind: c_int = lua_gettop(L) - nargs;

    trace_out = c.stdout;

    // Push error handler
    const trace_out_val = arcan_monitor_watchdog_error(L, 0, true);
    if (trace_out_val) |tov| {
        trace_out = tov;
        lua_pushcfunction(L, &wrap_trace_callstack_raw_fn);
    } else {
        lua_pushcfunction(L, &wrap_trace_callstack_fn);
    }
    lua_insert(L, errind);

    // If masksrc is in the current break-mask, set hook to line-trigger
    if (hook_mask & masksrc != 0) {
        _ = lua_sethook(L, &arcan_monitor_watchdog, LUA_MASKLINE, 1);
        arcan_monitor_masktrigger(L);
    }

    const errc = lua_pcall(L, nargs, retc, errind);

    if (errc != 0) {
        // Debug: print lua stack top type before trying to read error message
        const top_type = lua_type(L, -1);
        arcan_warning("alt_call: pcall error %d, stack top type=%d\n", @as(c_int, errc), @as(c_int, top_type));
        var msg_len: usize = 0;
        const msg = if (top_type == 4) // LUA_TSTRING
            lua_tolstring(L, -1, &msg_len)
        else
            @as([*c]const u8, "error (non-string on stack)");
        arcan_warning("alt_call: error msg (len=%zu): [%s]\n", msg_len, msg);
        lua_remove(L, errind);
        arcan_trace_mark("scripting", "crash", 0, TRACE_SYS_ERROR, 0, 0, msg);

        if (arcan_monitor_watchdog_error(L, 0, false) == null) {
            arcan_trace_setbuffer(null, 0, null);
            alt_trace_finish(L);
            wraperr(L, errc, src);
            return;
        }
    }

    @memset(std.mem.asBytes(&callback_source), 0);

    // Reset the hook - note that this could clash with breakpointing
    if (!in_breakpoint_set and (hook_mask & masksrc != 0)) {
        _ = lua_sethook(L, null, LUA_MASKLINE, 1);
    }

    if (errind != 0)
        lua_remove(L, errind);
}

// panic
fn panic_fn(L: ?*lua_State) callconv(.c) c_int {
    lua_debug_level = 2;

    if (arcan_monitor_watchdog_error(L, 1, false) != null) {
        return 0;
    }

    if (callback_source.kind != CB_SOURCE_NONE) {
        var vidbuf: [64]u8 = [_]u8{0} ** 64;
        _ = snprintf(&vidbuf, 64, "script error in callback for VID (%lld)", @as(c_longlong, callback_source.luavid));
        wraperr(L, -1, &vidbuf);
    } else {
        in_panic_state = true;
        wraperr(L, -1, "(panic)");
    }

    arcan_warning("LUA VM is in a panic state, recovery handover might be impossible.\n");

    alt_trace_set_crash_source("VM panic");
    longjmp(&c.arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

// fatal_handover
fn fatal_handover(L: ?*lua_State) void {
    if (!alt_lookup_entry(L, "fatal_handover", 14) or in_fatal_state) {
        in_fatal_state = false;
        return;
    }

    in_fatal_state = true;
    lua_settop(L, 0);
    _ = alt_lookup_entry(L, "fatal_handover", 14);
    const cs = alt_trace_crash_source();
    lua_pushstring(L, if (@intFromPtr(cs) != 0) cs else "");
    alt_call(L, CB_SOURCE_NONE, EP_TRIGGER_HANDOVER, 0, 1, 1, LINE_TAG_FATAL_HANDOVER);
    in_fatal_state = false;

    if (lua_type(L, -1) == LUA_TBOOLEAN and lua_toboolean(L, -1) != 0) {
        lua_settop(L, lua_gettop(L) - 1); // lua_pop(L, 1)
        longjmp(&c.arcanmain_recover_state, ARCAN_LUA_RECOVERY_FATAL_IGNORE);
    }
}

// alt_fatal
// Called directly from Zig callers (no varargs formatting needed).
export fn alt_fatal(formatted_msg: [*c]const u8) void {
    var buf: [*c]u8 = undefined;
    var buf_sz: usize = undefined;
    const L = fatal_context;

    // if we have monitor attached, go through watchdog error handler
    const tov = arcan_monitor_watchdog_error(L, 0, true);
    if (tov) |tw| {
        trace_out = tw;
        _ = fprintf(tw, "#BEGINBACKTRACE\n");
        alt_trace_callstack_raw(L, null, 10, tw);
        _ = fprintf(tw, "#ENDBACKTRACE\n");

        _ = fprintf(tw, "#BEGINSTACK\n");
        alt_trace_dumpstack_raw(L, tw);
        _ = fprintf(tw, "#ENDSTACK\n");

        lua_pushstring(L, formatted_msg);
        _ = arcan_monitor_watchdog_error(L, 1, false);
        return;
    }

    const stream = open_memstream(&buf, &buf_sz);
    if (stream) |s| {
        _ = fprintf(s, "%s\n", formatted_msg);
        alt_trace_callstack(L, s);
        _ = fflush(s);
        alt_trace_set_crash_source(buf);
        _ = fclose(s);
    } else {
        alt_trace_set_crash_source("couldn't build stream");
    }

    fatal_handover(L);

    if (lua_debug_level > 2)
        arcan_state_dump("misuse", alt_trace_crash_source(), "");

    longjmp(&c.arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

// wraperr
fn wraperr(L: ?*lua_State, errc: c_int, src: [*c]const u8) void {
    _ = errc;

    const mesg: [*c]const u8 = if (in_panic_state)
        "Lua VM state broken, panic"
    else
        luaL_optstring(L, -1, "unknown");

    // bug 0007: vcontext_stack was previously declared in arcan_lua.zig as
    // `[*c]c.arcan_video_context` (pointer) instead of the actual array type
    // `[CONTEXT_STACK_LIMIT]c.arcan_video_context`.  Indexing the [*c] form
    // first dereferenced the symbol's first 8 bytes as a pointer-base, then
    // applied the index — producing garbage like 0x400000000ab and
    // SIGSEGVing arcan_state_dump → memcpy on every Lua-error recovery.
    // Type-declaration fixed in commit cd54159fc4 (2026-04-30); this gate
    // stays in place as belt-and-braces until a clean ARCAN_STATEDUMP=1
    // controlled test confirms state_dump no longer SEGVs.  Default runs
    // skip the dump path so durian survives script errors regardless.
    if (lua_debug_level > 0 or @import("shmif_types").getenvSpan("ARCAN_STATEDUMP") != null) {
        arcan_state_dump("crash", mesg, src);
    }

    var buf: [*c]u8 = undefined;
    var buf_sz: usize = undefined;
    const stream = open_memstream(&buf, &buf_sz);

    if (stream) |s| {
        if (lua_debug_level != 0) {
            _ = fprintf(s, "Warning: wraperr((), %s, from %s\n", mesg, src);
            alt_trace_callstack(L, s);
            dump_stack(L, s);
        }

        _ = fprintf(s,
            "\n\x1b[1mScript failure:\n \x1b[32m %s\n" ++
                "\x1b[39mC-entry point: \x1b[32m %s \x1b[39m\x1b[0m.\n",
            mesg,
            src,
        );

        _ = fprintf(s, "\nHanding over to recovery script (or shutdown if none present).\n");

        _ = fflush(s);
        alt_trace_set_crash_source(buf);
        _ = fclose(s);
    } else {
        alt_trace_set_crash_source(mesg);
    }

    // first try cooperative script error recovery
    fatal_handover(L);

    // if that fails, switch to a recovery script
    alt_nbio_release();
    longjmp(&c.arcanmain_recover_state, ARCAN_LUA_RECOVERY_SWITCH);
}

// alt_apply_ban
export fn alt_apply_ban(L: ?*lua_State) void {
    const rv = luaL_loadbuffer(L, arcan_bootstrap_lua_data.ptr, arcan_bootstrap_lua_data.len, "bootstrap");

    if (rv != 0) {
        arcan_warning("BROKEN BUILD: bootstrap code couldn't be parsed\n");
    } else {
        _ = lua_pcall(L, 0, 0, 0);
    }
}

// alt_setup_context
export fn alt_setup_context(L: ?*lua_State, applname: [*c]const u8) void {
    _ = lua_atpanic(L, &panic_fn);
    fatal_context = L;

    prefix_len = strlen(applname);

    if (prefix_len + prefix_maxlen >= prefix_buf.len) {
        arcan_fatal("applname exceeds prefix-limit");
    }

    const src: [*]const u8 = @ptrCast(applname);
    @memcpy(prefix_buf[0..prefix_len], src[0..prefix_len]);
}

// alt_lookup_entry
export fn alt_lookup_entry(L: ?*lua_State, ep: [*c]const u8, len: usize) bool {
    if (len == 0) {
        prefix_buf[prefix_len] = 0;
    } else {
        prefix_buf[prefix_len] = '_';
        const src: [*]const u8 = @ptrCast(ep);
        @memcpy(prefix_buf[prefix_len + 1 ..][0..len], src[0..len]);
        prefix_buf[prefix_len + len + 1] = 0;
    }
    lua_getglobal(L, &prefix_buf);

    if (lua_isfunction(L, -1) == 0) {
        lua_settop(L, lua_gettop(L) - 1); // lua_pop(L, 1)
        return false;
    }

    return true;
}

// LoadF struct for alt_loadfile
const LoadF = struct {
    extraline: c_int,
    f: ?*FILE,
    buff: [LUAL_BUFFERSIZE]u8,
};

fn getF(_: ?*lua_State, ud: ?*anyopaque, size: *usize) callconv(.c) [*c]const u8 {
    const lf: *LoadF = @ptrCast(@alignCast(ud orelse return null));
    if (lf.extraline != 0) {
        lf.extraline = 0;
        size.* = 1;
        return "\n";
    }
    if (feof(lf.f) != 0) return null;
    size.* = fread(&lf.buff, 1, LUAL_BUFFERSIZE, lf.f);
    return if (size.* > 0) &lf.buff else null;
}

fn errfile(L: ?*lua_State, what: [*c]const u8, fnameindex: c_int) c_int {
    const serr = strerror(get_errno());
    const filename_raw = lua_tolstring(L, fnameindex, null);
    // Skip the '@' or '=' prefix character
    const filename: [*c]const u8 = if (@intFromPtr(filename_raw) != 0) filename_raw + 1 else filename_raw;
    _ = lua_pushfstring(L, "cannot %s %s: %s", what, filename, serr);
    lua_remove(L, fnameindex);
    return LUA_ERRFILE;
}

// alt_loadfile
export fn alt_loadfile(L: ?*lua_State, filename: [*c]const u8) c_int {
    var lf: LoadF = .{
        .extraline = 0,
        .f = null,
        .buff = undefined,
    };
    var readstatus: c_int = undefined;

    const fnameindex: c_int = lua_gettop(L) + 1;

    if (@intFromPtr(filename) == 0) {
        // lua_pushliteral(L, "=stdin")
        lua_pushstring(L, "=stdin");
        lf.f = c.stdin;
    } else {
        // lua_pushfstring is stubbed in this Zig port (Zig 0.15 disables
        // @cVaStart on aarch64), so format the source name inline as "@<file>"
        // — Lua's chunk-name convention for "real file" sources, used for
        // error tracebacks.
        var src_buf: [512]u8 = undefined;
        const src = std.fmt.bufPrintZ(&src_buf, "@{s}", .{
            std.mem.span(@as([*:0]const u8, @ptrCast(filename))),
        }) catch "@?";
        lua_pushstring(L, src);
        lf.f = fopen(filename, "r");
        if (lf.f == null) return errfile(L, "open", fnameindex);
    }

    var ch = getc(lf.f);
    if (ch == '#') {
        // Unix exec file: skip first line
        lf.extraline = 1;
        while (true) {
            ch = getc(lf.f);
            if (ch == @as(c_int, -1) or ch == '\n') break; // EOF or newline
        }
        if (ch == '\n') ch = getc(lf.f);
    }

    // MAY-230 Phase X: accept bytecode at appl-tree paths so the
    // compile-on-launch cache populated by `may appl run` (.zig sources
    // applc-compiled to stripped Lua 5.4 bytecode, written at <rel>.lua
    // paths in $XDG_CACHE_HOME/may/appls/<appl>/) loads transparently.
    // The bytecode here originates from our own applc pipeline reading
    // .zig that we ourselves shipped — same trust boundary as the .lua
    // source text it replaces. Untrusted scripts coming over a12 etc.
    // are handled by separate loaders (e.g. dir_lua_support.zig) which
    // keep their own bytecode rejection.
    //
    // (Was: "Modified Lua 5.1: reject bytecode" — see git history.)
    _ = LUA_SIGNATURE_BYTE; // marker kept for grep continuity

    _ = ungetc(ch, lf.f);
    const status = lua_load(L, &getF, @ptrCast(&lf), lua_tolstring(L, -1, null), null);
    readstatus = ferror(lf.f);
    if (@intFromPtr(filename) != 0) _ = fclose(lf.f);
    if (readstatus != 0) {
        lua_settop(L, fnameindex);
        return errfile(L, "read", fnameindex);
    }
    lua_remove(L, fnameindex);
    return status;
}
