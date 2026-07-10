// Zig port of a12/net/net_lua_cfg.c — Lua configuration interface for network settings.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com
//
// Open question: part of this should move to arcan or be duplicated there,
// then chainloading is just passing the config.lua we have ourselves.
// The same would apply to afsrv_net, though that shouldn't launch lwa itself;
// that should come through handover where the shmifsrv part spawns the binary
// so that we can drop exec permissions.
//
// This would cause some issues with platform configuration options, though
// those are probably best handled in the database.
//
// Another is if we should expose a lua tui both here and directory if we can
// open a shmif connection. This would be mainly for notification, status
// update and allocating a handover.

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. All non-Lua `c.X` references are aliased here from the hand-written
// replacement modules (zero `@cImport` left). Lua bindings come from lua54_api.
const shmif = @import("shmif_types");
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc
    pub const access = libc.access;
    pub const asprintf = libc.asprintf;
    pub const close = libc.close;
    pub const faccessat = libc.faccessat;
    pub const F_OK = libc.F_OK;
    pub const free = libc.free;
    pub const getenv = libc.getenv;
    pub const lseek = libc.lseek;
    pub const malloc = libc.malloc;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const open = libc.open;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const pipe = libc.pipe;
    pub const R_OK = libc.R_OK;
    pub const realpath = libc.realpath;
    pub const SEEK_END = libc.SEEK_END;
    pub const snprintf = libc.snprintf;
    pub const strchr = libc.strchr;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;
    pub const W_OK = libc.W_OK;

    // shmif — arg_arr
    pub const arg_lookup = shmif.arg_lookup;
    pub const struct_arg_arr = shmif.struct_arg_arr;

    // anet — directory / launcher meta
    pub const struct_global_cfg = anet.struct_global_cfg;
    pub const struct_launcher_meta = anet.struct_launcher_meta;
};

const lua = @import("lua_api");

// lua_rawlen_compat: wraps lua_rawlen (Lua 5.2+) or lua_objlen (Lua 5.1).
// The C source uses a preprocessor compat shim; our lua54_api provides
// lua_objlen as an inline wrapper around lua_rawlen.
inline fn lua_rawlen_compat(L: ?*lua.lua_State, idx: c_int) usize {
    return @intCast(lua.lua_objlen(L, idx));
}

// Shared state with net_lua.zig
// INITIALIZED is owned by net_lua.zig; we declare an extern reference here.
extern var INITIALIZED: bool;

// Module-level state

var CFG: ?*c.struct_global_cfg = null;
var Lst: ?*lua.lua_State = null;

// runner_cfg: paths and flags for the appl launcher
// Use [*c]u8 (the natural type from strdup/C allocation) to avoid casts at
// every assignment site.  null-testing via `if (ptr) |p|` works on [*c]T.

const RunnerCfg = struct {
    runner_path: [*c]u8 = null,
    fap_cache: [*c]u8 = null,
    state_path: [*c]u8 = null,
    binary_cache: [*c]u8 = null,
    unpack_temp: [*c]u8 = null,
    encode_path: [*c]u8 = null,
    encode_arg: [*c]u8 = null,

    block_update: bool = false,
    cleanup_exit: bool = true,
};

var runner_cfg = RunnerCfg{};

// a12_trace_targets — extern from a12 library

extern var a12_trace_targets: c_int;

// trace_groups — must match a12 library ordering

const trace_groups = [_][*:0]const u8{
    "video",
    "audio",
    "system",
    "event",
    "transfer",
    "debug",
    "missing",
    "alloc",
    "crypto",
    "vdetail",
    "binary",
    "security",
    "directory",
};

// Helpers

fn valid_file(fn_: [*c]const u8) bool {
    if (fn_ == null) return false;
    // Avoid c.struct_stat: musl demotes struct timespec to opaque in some
    // cImport builds.  Use access() + O_RDONLY open to check file-ness.
    if (c.access(fn_, c.F_OK) != 0) return false;
    const fd = c.open(fn_, c.O_RDONLY);
    if (fd < 0) return false;
    defer _ = c.close(fd);
    // Seek to end: directories return an error with lseek on Linux.
    const end = c.lseek(fd, 0, c.SEEK_END);
    return end >= 0;
}

fn valid_directory(fn_: [*c]const u8) bool {
    if (fn_ == null) return false;
    const dfd = c.open(fn_, c.O_RDONLY | c.O_DIRECTORY);
    if (dfd == -1) return false;
    const ok = c.faccessat(dfd, ".", c.R_OK | c.W_OK, 0);
    _ = c.close(dfd);
    return ok == 0;
}

// cfg_newindex: client-mode config table __newindex
// Handles config.identity and config.log_level.

fn cfg_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const cfg = CFG.?;

    if (c.strcmp(key, "identity") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (val[0] == 0) {
            _ = lua.luaL_error(L, "identity = ... zero-length string not permitted");
        }
        const ident_sz = @sizeOf(@TypeOf(cfg.dircl.ident));
        if (c.strlen(val) >= ident_sz) {
            _ = lua.luaL_error(L, "identity = ... identity too long (%zu)", c.strlen(val));
        }
        _ = c.snprintf(&cfg.dircl.ident, ident_sz, "%s", val);
    } else if (c.strcmp(key, "log_level") == 0) {
        if (lua.lua_type(L, 3) == lua.LUA_TTABLE) {
            const tbl_len = lua_rawlen_compat(L, 3);
            var i: usize = 0;
            while (i < tbl_len) : (i += 1) {
                _ = lua.lua_rawgeti(L, 3, @intCast(i + 1));
                if (lua.lua_type(L, -1) == lua.LUA_TSTRING) {
                    const grp = lua.lua_tolstring(L, -1, null);
                    var found = false;
                    for (trace_groups, 0..) |name, j| {
                        if (c.strcmp(grp, name) == 0) {
                            a12_trace_targets |= @as(c_int, 1) << @intCast(j);
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        _ = lua.luaL_error(L, "log_level = ... unknown group: %s\n", grp);
                    }
                    lua.lua_pop(L, 1);
                } else {
                    _ = lua.luaL_error(L, "log_level = [num] | {group1str, group2str, ...}\n");
                }
            }
        } else if (lua.lua_type(L, 3) == lua.LUA_TNUMBER) {
            a12_trace_targets = @intFromFloat(lua.lua_tonumber(L, 3));
        }
    }

    return 0;
}

// cfg_index: client-mode config table __index

fn cfg_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const cfg = CFG.?;

    if (c.strcmp(key, "identity") == 0) {
        _ = lua.lua_pushstring(L, &cfg.dircl.ident);
        return 1;
    }

    if (c.strcmp(key, "log_level") == 0) {
        lua.lua_pushnumber(L, @floatFromInt(a12_trace_targets));
        return 1;
    }

    _ = lua.luaL_error(L, "unknown key: %s, allowed: allow_tunnel, log_level\n", key);
    return 0;
}

// cfgrunner_index / cfgrunner_newindex

fn cfgrunner_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const cfg = CFG.?;

    if (c.strcmp(key, "reconnect") == 0) {
        lua.lua_pushboolean(L, if (cfg.dircl.reconnect) 1 else 0);
        return 1;
    } else if (c.strcmp(key, "block_state") == 0) {
        lua.lua_pushboolean(L, if (cfg.dircl.block_state) 1 else 0);
        return 1;
    } else if (c.strcmp(key, "encode_path") == 0) {
        _ = lua.lua_pushstring(L, runner_cfg.encode_path);
        return 1;
    } else if (c.strcmp(key, "encode_arg") == 0) {
        _ = lua.lua_pushstring(L, runner_cfg.encode_arg);
        return 1;
    }

    return 0;
}

fn cfgrunner_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const cfg = CFG.?;

    if (c.strcmp(key, "block_state") == 0) {
        cfg.dircl.block_state = (lua.lua_toboolean(L, 3) != 0);
    } else if (c.strcmp(key, "reconnect") == 0) {
        cfg.dircl.reconnect = (lua.lua_toboolean(L, 3) != 0);
    } else if (c.strcmp(key, "encode_path") == 0) {
        if (runner_cfg.encode_path) |old| c.free(old);
        runner_cfg.encode_path = c.strdup(lua.lua_tolstring(L, 3, null));
    } else if (c.strcmp(key, "encode_arg") == 0) {
        if (runner_cfg.encode_arg) |old| c.free(old);
        runner_cfg.encode_arg = c.strdup(lua.lua_tolstring(L, 3, null));
    }

    return 0;
}

// cfgpath_index / cfgpath_newindex

fn cfgpath_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const out = anet_client_lua_getpath(key);

    if (out) |p| {
        _ = lua.lua_pushstring(L, p);
        return 1;
    }

    return 0;
}

fn cfgpath_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    const cfg = CFG.?;

    if (INITIALIZED) {
        _ = lua.luaL_error(L, "config.paths.%s, read/only after init()\n", key);
    }

    if (c.strcmp(key, "database") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (c.strcmp(val, ":memory:") != 0 and !valid_file(val)) {
            _ = lua.luaL_error(L, "config.paths.database = %s, not a valid / existing file or :memory:\n", val);
        }
        if (cfg.db_file) |old| c.free(old);
        cfg.db_file = c.strdup(val);
        return 0;
    } else if (c.strcmp(key, "runner") == 0) {
        if (runner_cfg.runner_path) |old| c.free(old);
        runner_cfg.runner_path = c.strdup(lua.luaL_checklstring(L, 3, null));
        if (!valid_file(runner_cfg.runner_path)) {
            _ = lua.luaL_error(L, "config.paths.runner= %s, not a valid directory\n", runner_cfg.runner_path);
        }
        return 0;
    } else if (c.strcmp(key, "fap_cache") == 0) {
        if (runner_cfg.fap_cache) |old| c.free(old);
        runner_cfg.fap_cache = c.strdup(lua.luaL_checklstring(L, 3, null));
        if (!valid_directory(runner_cfg.fap_cache)) {
            _ = lua.luaL_error(L, "config.paths.fap_cache = %s, not a valid directory\n", runner_cfg.fap_cache);
        }
        return 0;
    } else if (c.strcmp(key, "state") == 0) {
        if (runner_cfg.state_path) |old| c.free(old);
        runner_cfg.state_path = c.strdup(lua.luaL_checklstring(L, 3, null));
        if (!valid_directory(runner_cfg.state_path)) {
            _ = lua.luaL_error(L, "config.paths.state = %s, not a valid directory\n", runner_cfg.state_path);
        }
        return 0;
    } else if (c.strcmp(key, "binary_cache") == 0) {
        if (runner_cfg.binary_cache) |old| c.free(old);
        runner_cfg.binary_cache = c.strdup(lua.luaL_checklstring(L, 3, null));
        if (!valid_directory(runner_cfg.binary_cache)) {
            _ = lua.luaL_error(L, "config.paths.binary_cache = %s, not a valid directory\n", runner_cfg.binary_cache);
        }
        return 0;
    } else if (c.strcmp(key, "unpack_temp") == 0) {
        if (runner_cfg.unpack_temp) |old| c.free(old);
        runner_cfg.unpack_temp = c.strdup(lua.luaL_checklstring(L, 3, null));
        if (!valid_directory(runner_cfg.unpack_temp)) {
            _ = lua.luaL_error(L, "config.paths.unpack_temp = %s, not a valid directory\n", runner_cfg.unpack_temp);
        }
        return 0;
    } else {
        _ = lua.luaL_error(L, "unknown path key: %s, accepted:\n\t\n", key, "database, runner_path, fap_cache, state_path, binary_cache, unpack_temp, runner\n");
    }

    return 0;
}

// anet_client_lua_getpath
// Returns a pointer to one of the path strings by name, or null.

pub export fn anet_client_lua_getpath(key: [*c]const u8) [*c]u8 {
    const cfg = CFG orelse return null;

    if (c.strcmp(key, "database") == 0) return cfg.db_file;
    if (c.strcmp(key, "runner_path") == 0) return runner_cfg.runner_path;
    if (c.strcmp(key, "fap_cache") == 0) return runner_cfg.fap_cache;
    if (c.strcmp(key, "state_path") == 0) return runner_cfg.state_path;
    if (c.strcmp(key, "unpack_temp") == 0) return runner_cfg.unpack_temp;
    if (c.strcmp(key, "binary_cache") == 0) return runner_cfg.binary_cache;
    if (c.strcmp(key, "encode_path") == 0) return runner_cfg.encode_path;
    if (c.strcmp(key, "encode_arg") == 0) return runner_cfg.encode_arg;

    return null;
}

// anet_client_lua_cfg
// Called when config.client = true is set.  Resets the config metatable to
// client-mode handlers and populates config.paths, config.runner, config.security,
// config.video.  Also populates the global 'env' table from environ.

pub export fn anet_client_lua_cfg(cfg: *c.struct_global_cfg, L: *lua.lua_State) void {
    CFG = cfg;
    Lst = L;

    // Redo __index/__newindex on cfgtbl for client mode.
    _ = lua.luaL_getmetatable(L, "cfgtbl");
    lua.lua_pushcfunction(L, cfg_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfg_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_pop(L, 1);

    // Create cfgpathtbl metatable.
    _ = lua.luaL_newmetatable(L, "cfgpathtbl");
    lua.lua_pushcfunction(L, cfgpath_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfgpath_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_pop(L, 1);

    // Create cfgrunnertbl metatable.
    _ = lua.luaL_newmetatable(L, "cfgrunnertbl");
    lua.lua_pushcfunction(L, cfgrunner_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfgrunner_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_pop(L, 1);

    // Re-push the global 'config' table and attach cfgtbl metatable.
    _ = lua.lua_getglobal(L, "config"); // TABLE

    _ = lua.luaL_getmetatable(L, "cfgtbl");
    _ = lua.lua_setmetatable(L, -2);

    // config.paths
    _ = lua.lua_pushstring(L, "paths"); // TABLE, "paths"
    lua.lua_createtable(L, 0, 10); // TABLE, "paths", TABLE(paths)
    _ = lua.luaL_getmetatable(L, "cfgpathtbl");
    _ = lua.lua_setmetatable(L, -2); // TABLE, "paths", TABLE(paths+meta)
    lua.lua_rawset(L, -3); // TABLE

    // config.runner (with nested args and env tables)
    _ = lua.lua_pushstring(L, "runner"); // TABLE, "runner"
    lua.lua_createtable(L, 0, 10); // TABLE, "runner", TABLE(runner)
    _ = lua.luaL_getmetatable(L, "cfgrunnertbl");
    _ = lua.lua_setmetatable(L, -2);

    _ = lua.lua_pushstring(L, "args"); // TABLE, TABLE(runner), "args"
    lua.lua_createtable(L, 0, 10); // TABLE, TABLE(runner), "args", TABLE(args)
    lua.lua_rawset(L, -3); // TABLE, TABLE(runner)

    _ = lua.lua_pushstring(L, "env"); // TABLE, TABLE(runner), "env"
    lua.lua_createtable(L, 0, 10); // TABLE, TABLE(runner), "env", TABLE(env)
    lua.lua_rawset(L, -3); // TABLE, TABLE(runner)

    lua.lua_rawset(L, -3); // TABLE

    // config.security
    _ = lua.lua_pushstring(L, "security"); // TABLE, "security"
    lua.lua_createtable(L, 0, 10); // TABLE, "security", TABLE
    lua.lua_rawset(L, -3); // TABLE

    // config.video
    _ = lua.lua_pushstring(L, "video"); // TABLE, "video"
    lua.lua_createtable(L, 0, 10); // TABLE, "video", TABLE
    lua.lua_rawset(L, -3); // TABLE

    lua.lua_setglobal(L, "config"); // nil

    // Populate global 'env' table from the process environment.
    const environ_ptr: [*]?[*:0]u8 = @extern([*]?[*:0]u8, .{ .name = "environ" });
    lua.lua_newtable(L);
    var pos: usize = 0;
    while (environ_ptr[pos]) |entry| : (pos += 1) {
        const eq = c.strchr(entry, '=');
        if (eq) |eqp| {
            const key_len: usize = @intFromPtr(eqp) - @intFromPtr(entry);
            _ = lua.lua_pushlstring(L, entry, key_len);
            _ = lua.lua_pushstring(L, eqp + 1);
        } else {
            _ = lua.lua_pushstring(L, entry);
            lua.lua_pushboolean(L, 1);
        }
        lua.lua_rawset(L, -3);
    }
    lua.lua_setglobal(L, "env");
}

// lua_execargs
// (INITIALIZED path) Builds launcher_meta from config.runner in the Lua state.

fn lua_execargs(
    name: [*:0]const u8,
    path: [*:0]const u8,
    res: *c.struct_launcher_meta,
    _: ?*c.struct_arg_arr,
) bool {
    const L = Lst.?;
    const cfg = CFG.?;

    // Open control pipes.
    if (c.pipe(&res.pstdin) == -1 or c.pipe(&res.pstdout) == -1) {
        return false;
    }

    _ = lua.lua_getglobal(L, "config");
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "executor: bad lua state [config table missing]\n");
    }

    _ = lua.lua_pushstring(L, "runner");
    _ = lua.lua_rawget(L, -2);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "executor: config.runner is not a table\n");
    }

    _ = lua.lua_pushstring(L, "env");
    _ = lua.lua_rawget(L, -2);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "executor: config.runner.env is not a table\n");
    }

    // Count keys in env table.
    var counter: usize = 0;
    lua.lua_pushnil(L);
    while (lua.lua_next(L, -2) != 0) {
        counter += 1;
        lua.lua_pop(L, 1);
    }

    // Allocate env array (NULL terminated).
    const env_sz = @sizeOf([*c]u8) * (counter + 1);
    res.env = @ptrCast(@alignCast(c.malloc(env_sz)));
    const env_ptr = res.env.?;
    env_ptr[counter] = null;
    lua.lua_pushnil(L);
    counter = 0;
    while (lua.lua_next(L, -2) != 0) {
        const k = lua.luaL_checklstring(L, -2, null);
        const v = lua.luaL_checklstring(L, -1, null);
        _ = c.asprintf(@as(*?[*]u8, @ptrCast(&env_ptr[counter])), "%s=%s", k, v);
        counter += 1;
        lua.lua_pop(L, 1);
    }
    lua.lua_pop(L, 1); // pop env table; stack: TABLE(config), TABLE(runner)

    // Set binary path. Force this `may` binary as the runner so the LWA-
    // mode arcan engine runs in-process (see src/main.zig `lwa`
    // subcommand). The Lua-side runner_cfg.runner_path is now vestigial
    // for the arcan-flavored runner — we hard-route to self-exe regardless
    // to eliminate the historical `arcan_lwa` external dependency. The
    // tui (afsrv_terminal) branch in anet_client_execargs is unaffected.
    const self_exe_lua: ?[*:0]u8 = c.realpath("/proc/self/exe", null);
    if (self_exe_lua == null) return false;
    res.bin = self_exe_lua;

    // Read config.runner.args
    _ = lua.lua_pushstring(L, "args");
    _ = lua.lua_rawget(L, -2);
    if (lua.lua_type(L, -1) != lua.LUA_TTABLE) {
        _ = lua.luaL_error(L, "executor: config.runner.args is not a table");
    }

    const rawlen: usize = lua_rawlen_compat(L, -1);
    // 10 fixed argv slots (name, lwa, -d, db, -M, -1, -O, LOGFD, -C, -)
    // + rawlen Lua-supplied + 1 trailing path + 1 NULL terminator.
    const argc: usize = 11 + rawlen + 1;
    const argv_sz = @sizeOf([*c]u8) * argc;
    res.argv = @ptrCast(@alignCast(c.malloc(argv_sz)));
    const argv_ptr = res.argv.?;

    var argi: usize = 0;
    _ = c.asprintf(@as(*?[*]u8, @ptrCast(&argv_ptr[argi])), "anet-arcan: %s", name);
    argi += 1;
    argv_ptr[argi] = c.strdup("lwa");
    argi += 1;
    argv_ptr[argi] = c.strdup("-d");
    argi += 1;
    argv_ptr[argi] = cfg.db_file;
    argi += 1;
    argv_ptr[argi] = c.strdup("-M");
    argi += 1;
    argv_ptr[argi] = c.strdup("-1");
    argi += 1;
    argv_ptr[argi] = c.strdup("-O");
    argi += 1;
    _ = c.asprintf(@as(*?[*]u8, @ptrCast(&argv_ptr[argi])), "LOGFD:%d", res.pstdout[1]);
    argi += 1;
    argv_ptr[argi] = c.strdup("-C");
    argi += 1;
    argv_ptr[argi] = c.strdup("-");
    argi += 1;

    var i: usize = 1;
    while (i <= rawlen) : (i += 1) {
        _ = lua.lua_rawgeti(L, -1, @intCast(i));
        argv_ptr[argi] = c.strdup(lua.luaL_checklstring(L, -1, null));
        lua.lua_pop(L, 1);
        argi += 1;
    }
    lua.lua_pop(L, 2); // pop args table + runner table

    // Append the executable path (either "./<appl>" or --force-appl override).
    argv_ptr[argi] = c.strdup(path);
    argi += 1;
    argv_ptr[argi] = null;

    return true;
}

// anet_client_execargs
// Legacy fallback when INITIALIZED is false.  Exports via C ABI.

pub export fn anet_client_execargs(
    name: [*:0]const u8,
    path: [*:0]const u8,
    res: *c.struct_launcher_meta,
    M: ?*c.struct_arg_arr,
) bool {
    if (INITIALIZED) return lua_execargs(name, path, res, M);

    const env_cap: usize = 16;
    const argv_cap: usize = 16;

    const env_sz = @sizeOf([*c]u8) * env_cap;
    const argv_sz = @sizeOf([*c]u8) * argv_cap;

    res.env = @ptrCast(@alignCast(c.malloc(env_sz)));
    @memset(@as([*]u8, @ptrCast(res.env))[0..env_sz], 0);

    res.argv = @ptrCast(@alignCast(c.malloc(argv_sz)));
    @memset(@as([*]u8, @ptrCast(res.argv))[0..argv_sz], 0);

    if (c.pipe(&res.pstdin) == -1 or c.pipe(&res.pstdout) == -1) {
        return false;
    }

    const preserve_keys = [_][*:0]const u8{
        "HOME",
        "XDG_RUNTIME_DIR",
        "XDG_CONFIG_HOME",
        "ARCAN_CONNPATH",
        "ARCAN_BINPATH",
        "ARCAN_SCRIPTPATH",
        // Renderer tunables — without these in the allowlist, an LWA spawned
        // via may-net inherits arcan's compiled defaults regardless of what
        // the parent systemd unit / shell exports. ARCAN_FONT_SIZE_OVERRIDE
        // is the only way to scale appls that hardcode \f,SIZE in their
        // text markup (e.g. letoram's consort uses \f,12 in config.lua);
        // dropping it from the env makes the "make fonts bigger" knob
        // effectively unreachable from outside the appl's own source.
        "ARCAN_FONT_SIZE_OVERRIDE",
        "ARCAN_FONT_WEIGHT",
        "ARCAN_FONT_HINT",
    };

    var env_i: usize = 0;
    const env_slot = res.env.?;
    for (preserve_keys) |pk| {
        const val = c.getenv(pk) orelse continue;
        _ = c.asprintf(@as(*?[*]u8, @ptrCast(&env_slot[env_i])), "%s=%s", pk, val);
        env_i += 1;
    }

    // Environment override for stub/test runner.
    if (c.getenv("ANET_RUNNER")) |runner| {
        res.bin = runner;
        return true;
    }

    var argv_i: usize = 0;
    const argv_slot = res.argv.?;

    // arg_lookup returns bool
    if (c.arg_lookup(M, "tui", 0, null)) {
        res.bin = c.strdup("afsrv_terminal");
        argv_slot[argv_i] = c.strdup("anet-runner-tui");
        argv_i += 1;
        env_slot[env_i] = c.strdup("ARCAN_ARG=cli=lua");
        env_i += 1;
        if (c.asprintf(@as(*?[*]u8, @ptrCast(&env_slot[env_i])), "LASH_BASE=./%s", name) == -1) return false;
        env_i += 1;
        if (c.asprintf(@as(*?[*]u8, @ptrCast(&env_slot[env_i])), "LASH_SHELL=%s", name) == -1) return false;
        env_i += 1;
    } else {
        // Spawn this same `may` binary with the `lwa` subcommand. The
        // arcan engine's runtime LWA branch (selected via
        // ARCAN_CONNPATH/ARCAN_SOCKIN_FD, forwarded via preserve_keys
        // above) covers both LWA-mode (env set) and server-mode arcan
        // (env unset) from a single code path — no per-spawn binary
        // switch needed. Supersedes the historical `arcan_lwa` external
        // binary.
        const self_exe_fallback: ?[*:0]u8 = c.realpath("/proc/self/exe", null);
        if (self_exe_fallback == null) return false;
        res.bin = self_exe_fallback;
        argv_slot[argv_i] = c.strdup("anet-runner-arcan");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("lwa");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-d");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup(":memory:");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-M");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-1");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-O");
        argv_i += 1;
        if (c.asprintf(@as(*?[*]u8, @ptrCast(&argv_slot[argv_i])), "LOGFD:%d", res.pstdout[1]) == -1) return false;
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-C");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup("-");
        argv_i += 1;
        argv_slot[argv_i] = c.strdup(path);
        argv_i += 1;
    }

    return true;
}
