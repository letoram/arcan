// Zig port of a12/net/net_lua.c — Minimal Lua bindings for arcan-net operations.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. All non-Lua `c.X` references are aliased here from the hand-written
// replacement modules (zero `@cImport` left). Lua bindings come from lua54_api.
const anet = @import("anet_types");
const libc = @import("posix");

const c = struct {
    // libc
    pub const fprintf = libc.fprintf;
    pub const strcmp = libc.strcmp;

    // anet — directory/global config
    pub const struct_global_cfg = anet.struct_global_cfg;
};

// stderr is an extern var — not a compile-time const and can't live inside
// the dispatch struct. Keep it at file scope and rewrite call sites from
// `c.stderr` to `stderr()`.
inline fn stderr() *libc.FILE {
    return libc.stderr;
}

const lua = @import("lua_api");

// Module-level state
// Mirrors the C file-scope globals: CFG, L, INITIALIZED.

var CFG: ?*c.struct_global_cfg = null;
var L: ?*lua.lua_State = null;

// INITIALIZED is exported so net_lua_cfg.zig can read it via extern.
pub var INITIALIZED: bool = false;

// Forward declarations for functions implemented in net_lua_cfg (C side)

extern fn anet_directory_lua_cfg(cfg: *c.struct_global_cfg, L: *lua.lua_State) void;
extern fn anet_client_lua_cfg(cfg: *c.struct_global_cfg, L: *lua.lua_State) void;

// Lua metamethod: config __index (no-op, returns nothing)

fn cfg_index(L_arg: ?*lua.lua_State) callconv(.c) c_int {
    _ = L_arg;
    return 0;
}

// Lua metamethod: config __newindex
// Accepts config.client = bool or config.directory_server = bool and
// dispatches into the appropriate configuration mode.

fn cfg_newindex(L_arg: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L_arg, 2, null);
    var dir: bool = true;

    if (c.strcmp(key, "client") == 0) {
        if (lua.lua_type(L_arg, 3) != lua.LUA_TBOOLEAN) {
            _ = lua.luaL_error(L_arg, "invalid value: config.client = .. boolean expected");
        }
        // client=true means NOT directory mode
        dir = (lua.lua_toboolean(L_arg, 3) == 0);
    } else if (c.strcmp(key, "directory_server") == 0) {
        // HAVE_DIRSRV branch (we define HAVE_DIRSRV in @cDefine above)
        if (lua.lua_type(L_arg, 3) != lua.LUA_TBOOLEAN) {
            _ = lua.luaL_error(L_arg, "invalid value: config.directory_server = .. boolean expected");
        }
        dir = (lua.lua_toboolean(L_arg, 3) != 0);
    } else {
        _ = lua.luaL_error(L_arg, "unknown key: config.%s, expected directory_server or client = true | false", key);
    }

    const cfg = CFG orelse {
        _ = lua.luaL_error(L_arg, "internal error: CFG not initialised");
        return 0;
    };

    if (dir) {
        // HAVE_DIRSRV
        anet_directory_lua_cfg(cfg, L_arg.?);
    } else {
        anet_client_lua_cfg(cfg, L_arg.?);
    }

    return 0;
}

// lookup_entrypoint
// Looks up a global Lua function by name.  Returns true and leaves the
// function on the stack; returns false and pops if it is not a function.

fn lookup_entrypoint(L_arg: *lua.lua_State, ep: [*:0]const u8) bool {
    _ = lua.lua_getglobal(L_arg, ep);

    if (!lua.lua_isfunction(L_arg, -1)) {
        lua.lua_pop(L_arg, 1);
        return false;
    }

    return true;
}

// anet_lua_init
// Public entry point exported to C.
// Creates a fresh Lua VM, installs the config metatable, runs config_file
// (if set), and calls init() if it exists.

pub export fn anet_lua_init(cfg: *c.struct_global_cfg) bool {
    const L_new = lua.luaL_newstate() orelse {
        _ = c.fprintf(stderr(), "luaL_newstate() - failed\n");
        return false;
    };

    L = L_new;
    CFG = cfg;

    lua.luaL_openlibs(L_new);

    // Create the 'config' table with a metamethod-gated metatable so that
    // only directory_server = bool and client = bool are accepted until the
    // mode has been chosen.
    lua.lua_newtable(L_new);
    _ = lua.luaL_newmetatable(L_new, "cfgtbl");
    lua.lua_pushcfunction(L_new, cfg_index);
    lua.lua_setfield(L_new, -2, "__index");
    lua.lua_pushcfunction(L_new, cfg_newindex);
    lua.lua_setfield(L_new, -2, "__newindex");
    _ = lua.lua_setmetatable(L_new, -2);
    lua.lua_setglobal(L_new, "config");

    if (cfg.config_file) |config_file| {
        const status = lua.luaL_dofile(L_new, config_file);
        if (status != 0) {
            const msg = lua.lua_tolstring(L_new, -1, null);
            _ = c.fprintf(stderr(), "%s: failed, %s\n", config_file, msg);
            return false;
        }

        if (lookup_entrypoint(L_new, "init")) {
            if (lua.lua_pcall(L_new, 0, 0, 0) != 0) {
                const msg = lua.lua_tolstring(L_new, -1, null);
                _ = c.fprintf(stderr(), "%s: failed, %s\n", config_file, msg);
                return false;
            }
            INITIALIZED = true;
        }
    }

    return true;
}
