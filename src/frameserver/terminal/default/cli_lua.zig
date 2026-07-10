const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, arcan_tui.h,
// unistd.h, fcntl.h, signal.h })` block. Keeps the `c.X` spellings used
// below. Each alias routes to the appropriate hand-written replacement module
// (zero `@cImport` left).
const shmif_types = @import("shmif_types");
const libc = @import("posix");
const lua = @import("lua_api");

const c = struct {
    // shmif — event types, segment ids, context
    pub const arcan_event = shmif_types.arcan_event;
    pub const arcan_shmif_cont = shmif_types.struct_arcan_shmif_cont;
    pub const arcan_shmif_drop = shmif_types.arcan_shmif_drop;
    pub const arcan_shmif_enqueue = shmif_types.arcan_shmif_enqueue;
    pub const arcan_shmif_last_words = shmif_types.arcan_shmif_last_words;
    pub const arcan_tui_conn = shmif_types.arcan_tui_conn;
    pub const arcan_tui_destroy = shmif_types.arcan_tui_destroy;
    pub const arg_arr = shmif_types.struct_arg_arr;
    pub const arg_lookup = shmif_types.arg_lookup;
    pub const EVENT_TARGET = shmif_types.EVENT_TARGET;
    pub const TARGET_COMMAND_BCHUNK_OUT = shmif_types.TARGET_COMMAND_BCHUNK_OUT;
    pub const tui_context = shmif_types.struct_tui_context;
    // sigaction — real extern struct with __sa_handler union lives in shmif_types.
    pub const sigaction = shmif_types.sigaction;
    pub const struct_sigaction = shmif_types.struct_sigaction;

    // libc — stdio + process bits
    pub const close = libc.close;
    pub const fflush = libc.fflush;
    pub const fprintf = libc.fprintf;
    pub const fputs = libc.fputs;
    pub const isatty = libc.isatty;
    pub const open = libc.open;
    // stderr / stdout are `extern "c" var` in libc. Aliasing an extern var
    // via `pub const = libc.stderr` triggers a comptime-value error; redeclare
    // the extern var directly — the linker resolves both to the same libc symbol.
    pub extern "c" var stderr: *libc.FILE;
    pub extern "c" var stdout: *libc.FILE;
    pub const O_CREAT = libc.O_CREAT;
    pub const O_WRONLY = libc.O_WRONLY;
    pub const SIGUSR1 = libc.SIGUSR1;
    pub const STDOUT_FILENO = libc.STDOUT_FILENO;
};

const lash_lua = @embedFile("lash.lua");

var lua_state: ?*lua.lua_State = null;

extern fn arcan_timemillis() c_ulonglong;
extern fn ltui_inherit(L: ?*lua.lua_State, conn: ?*c.arcan_tui_conn, meta: ?*anyopaque) ?*c.tui_context;
extern fn tui_event_inject(tui: ?*c.tui_context, ev: ?*c.arcan_event) void;
extern fn arcan_luaopen_bit(L: ?*lua.lua_State) c_int;

// ds4.infer — native DS4-Flash inference. In single-binary builds the C
// export lives in src/Ds4/api.zig and is linked in; that engine is not
// part of the standalone arcan tree, so keep the Lua surface (`ds4`
// global with an `infer` field) but report unavailability at runtime.
fn ds4_infer_c(prompt_ptr: [*]const u8, prompt_len: usize) c_int {
    _ = prompt_ptr;
    _ = prompt_len;
    std.debug.print("ds4.infer: no inference engine in this build\n", .{});
    return -1;
}

fn ds4_infer_lua(ctx: ?*lua.lua_State) callconv(.c) c_int {
    var dsz: usize = undefined;
    const instr: [*c]const u8 = lua.luaL_checklstring(ctx, 1, &dsz);
    const rc = ds4_infer_c(@as([*]const u8, @ptrCast(instr)), dsz);
    lua.lua_pushnumber(ctx, @floatFromInt(rc));
    return 1;
}

// luaL_openlibs (used by arcan main) intentionally skips `io` because the
// engine doesn't expose a filesystem boundary. lash IS a shell — it needs
// io.open to find user shells under $LASH_BASE / $HOME/.arcan/lash. Open
// io explicitly here so it lands as a global in this isolated lua_State.
extern fn luaopen_io(L: ?*lua.lua_State) c_int;
extern fn luaL_requiref(L: ?*lua.lua_State, modname: [*:0]const u8, openf: ?*const fn (?*lua.lua_State) callconv(.c) c_int, glb: c_int) void;

/// Signal hook: dump Lua calltrace on SIGUSR1 for livelock debugging.
fn watchdog(L: ?*lua.lua_State, _: ?*lua.lua_Debug) callconv(.c) void {
    lua.lua_sethook(lua_state, null, lua.LUA_MASKLINE, 0);

    const state = L orelse return;

    // debug table
    _ = lua.lua_getglobal(state, "debug");
    if (lua.lua_type(state, -1) != lua.LUA_TTABLE) {
        lua.lua_settop(state, lua.lua_gettop(state) - 1); // pop 1
        return;
    }
    _ = lua.lua_getfield(state, -1, "traceback");
    if (lua.lua_type(state, -1) != lua.LUA_TFUNCTION) {
        lua.lua_settop(state, lua.lua_gettop(state) - 2); // pop 2
        return;
    }
    lua.lua_pushvalue(state, 1); // pass error message
    lua.lua_pushinteger(state, 2); // skip this function and traceback
    lua.lua_call(state, 2, 1); // call debug.traceback

    const traceback: [*c]const u8 = lua.lua_tolstring(state, -1, null);
    const msg: [*c]const u8 = if (traceback != null) traceback else "(no trace)\n";
    _ = c.fputs(msg, c.stdout);
    _ = c.fflush(c.stdout);

    lua.lua_settop(state, lua.lua_gettop(state) - 1); // pop 1
}

fn monitor_sigusr(_: c_int) callconv(.c) void {
    lua.lua_sethook(lua_state, &watchdog, lua.LUA_MASKLINE, 1);
}

fn dump_stack(ctx: *lua.lua_State) void {
    const top = lua.lua_gettop(ctx);
    var i: c_int = 1;
    while (i <= top) : (i += 1) {
        const t = lua.lua_type(ctx, i);
        const idx: usize = @intCast(i);
        switch (t) {
            lua.LUA_TBOOLEAN => {
                const val = if (lua.lua_toboolean(ctx, i) != 0) "true" else "false";
                _ = c.fprintf(c.stderr, "%s", val.ptr);
            },
            lua.LUA_TSTRING => {
                _ = c.fprintf(c.stderr, "%zu\t'%s'\n", idx, lua.lua_tolstring(ctx, i, null));
            },
            lua.LUA_TNUMBER => {
                _ = c.fprintf(c.stderr, "%zu\t%g\n", idx, lua.lua_tonumber(ctx, i));
            },
            lua.LUA_TUSERDATA => {
                _ = c.fprintf(c.stderr, "%zu\tuserdata\n", idx);
            },
            else => {
                _ = c.fprintf(c.stderr, "%zu\t%s\n", idx, lua.lua_typename(ctx, t));
            },
        }
    }
    _ = c.fprintf(c.stderr, "\n");
}

fn emptyf(_: ?*lua.lua_State) callconv(.c) c_int {
    _ = c.fprintf(c.stderr, "tui:open() not supported inside arcterm, use tui.root");
    return 0;
}

extern "c" fn putenv(s: [*c]u8) c_int;
extern "c" fn strdup(s: [*c]const u8) [*c]u8;

export fn arcterm_luacli_run(
    shmif: ?*c.arcan_shmif_cont,
    args: ?*c.arg_arr,
) c_int {
    // suppress unused dump_stack
    _ = &dump_stack;

    // Apply env=K=V entries from ARCAN_ARG into our environ. The
    // PTY-shell path (arcterm.zig setup_shell) does this for the
    // exec=<binary> case at arcterm.zig:1218, but cli=lua jumps
    // straight here and used to skip it — so LASH_BASE/LASH_SHELL
    // (set by durian's /global/open/{lash,agent,cat9} spawn paths
    // via `env=K=V` in the resource string) never landed and lash
    // bootstrap fell through to `shell default not found`.
    {
        var ind: c_ushort = 0;
        var val: [*c]const u8 = undefined;
        while (c.arg_lookup(args, "env", ind, &val)) {
            _ = putenv(strdup(val));
            ind += 1;
        }
    }

    lua_state = lua.luaL_newstate();
    const state = lua_state orelse return 1; // EXIT_FAILURE

    // Set up SIGUSR1 handler for debug traceback
    var sa: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    if (@hasField(c.struct_sigaction, "__sigaction_handler")) {
        // glibc: __sigaction_handler is a union with sa_handler/sa_sigaction
        sa.__sigaction_handler.sa_handler = &monitor_sigusr;
    } else {
        // musl: __sa_handler is a union with sa_handler/sa_sigaction
        sa.__sa_handler.sa_handler = &monitor_sigusr;
    }
    _ = c.sigaction(c.SIGUSR1, &sa, null);

    _ = arcan_timemillis();
    lua.luaL_openlibs(state);
    luaL_requiref(state, "io", &luaopen_io, 1);
    lua.lua_settop(state, lua.lua_gettop(state) - 1); // pop io table left by requiref
    lua.lua_settop(state, lua.lua_gettop(state) - arcan_luaopen_bit(state)); // lua_pop(lua, arcan_luaopen_bit(lua))

    // Register ds4 = { infer = <native> } as a global. Mirror of
    // src/engine/arcan_lua.zig:extend_ds4api in durian's VM.
    lua.lua_createtable(state, 0, 0);
    _ = lua.lua_pushstring(state, "infer");
    lua.lua_pushcclosure(state, &ds4_infer_lua, 0);
    lua.lua_settable(state, -3);
    lua.lua_setglobal(state, "ds4");

    // get a table: require 'arcantui' -> stack
    lua.lua_createtable(state, 0, 0);
    const tui: ?*c.tui_context = ltui_inherit(
        state,
        @ptrCast(shmif),
        null,
    );

    // the record option for debugging / easy sharing etc.
    var val: [*c]const u8 = null;
    if (c.arg_lookup(args, "record", 0, &val) and val != null) {
        const fd = c.open(val, c.O_WRONLY | c.O_CREAT, @as(c_uint, 0o600));
        if (fd != -1) {
            var ev: c.arcan_event = c.arcan_event.zeroes();
            ev.unnamed_0.unnamed_0.category = c.EVENT_TARGET;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.kind = c.TARGET_COMMAND_BCHUNK_OUT;
            ev.unnamed_0.unnamed_0.unnamed_0.tgt.ioevs[0].iv = fd;
            const msg_src = "tuiani";
            @memcpy(ev.unnamed_0.unnamed_0.unnamed_0.tgt.unnamed_0.message[0..msg_src.len], msg_src);
            tui_event_inject(tui, &ev);
            _ = c.close(fd);
        } else {
            _ = c.fprintf(c.stderr, "record=%s : couldn't create file for tuiani out\n", val);
        }
    }

    // stack: -2 table, -1 userdata
    if (tui == null) {
        c.arcan_shmif_last_words(shmif, "couldn't setup lua VM");
        c.arcan_shmif_drop(shmif);
        lua.lua_close(state);
        return 1; // EXIT_FAILURE
    }

    // stack: -3 table, -2 userdata, -1 root
    _ = lua.lua_pushlstring(state, "root", 4);
    lua.lua_pushvalue(state, -2);

    // stack: -4 table, -3 userdata, -2 "root", -1 userdata (alias)
    lua.lua_settable(state, -4);

    // stack: -1 table
    lua.lua_settop(state, lua.lua_gettop(state) - 1); // pop 1

    // replace open with empty function
    _ = lua.lua_pushlstring(state, "open", 4);
    lua.lua_pushcclosure(state, &emptyf, 0);
    lua.lua_settable(state, -3);

    // add arguments table
    var ind: c_ushort = 0;
    _ = lua.lua_pushlstring(state, "arguments", 9);
    lua.lua_createtable(state, 0, 0);

    while (c.arg_lookup(args, "args", ind, &val) and val != null) {
        ind += 1;
        lua.lua_pushnumber(state, @floatFromInt(ind));
        _ = lua.lua_pushstring(state, val);
        lua.lua_settable(state, -3);
    }
    lua.lua_settable(state, -3);

    // and now set: tui = require 'arcantui'
    lua.lua_setglobal(state, "tui");

    // parse-run builtin script
    if (0 != lua.luaL_loadbuffer(state, lash_lua.ptr, lash_lua.len, "lash")) {
        const msg: [*c]const u8 = lua.lua_tolstring(state, -1, null);
        if (c.isatty(c.STDOUT_FILENO) != 0) {
            _ = c.fprintf(c.stdout, "lua_cli failed: %s", msg);
        } else {
            _ = c.fprintf(c.stderr, "lua_cli failed: %s", msg);
        }
        c.arcan_tui_destroy(tui, "error running builtin script");
        return 1; // EXIT_FAILURE
    }

    // pcall into it. msgh=0 so any error in our error handler doesn't
    // mask the original error. Print the raw error string on failure.
    if (0 != lua.lua_pcall(state, 0, 0, 0)) {
        _ = c.fprintf(c.stderr, "arcterm[lash] - builtin- loader failed:\n");
        const msg: [*c]const u8 = lua.luaL_optlstring(state, -1, "\tno error message", null);
        _ = c.fprintf(c.stderr, "\nError: %s\n", msg);
    }

    // this should GC the tui connection should it not already be closed
    lua.lua_close(state);

    return 0; // EXIT_SUCCESS
}
