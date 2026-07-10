// Zig port of a12/net/dir_lua_cfg.c — Lua configuration interface for directory service.
// Copyright: Bjorn Stahl
// License: 3-Clause BSD, see COPYING file in arcan source repository.
// Reference: https://arcan-fe.com

const std = @import("std");

// Dispatch struct replacing the prior `@cImport({ arcan_shmif.h, a12.h, ... })`
// block. All non-Lua `c.X` references are aliased here from the hand-written
// replacement modules (zero `@cImport` left). Lua bindings come from lua54_api.
const anet = @import("anet_types");
const a12 = @import("a12_types");
const libc = @import("posix");

const c = struct {
    // libc
    pub const close = libc.close;
    pub const fcntl = libc.fcntl;
    pub const FD_CLOEXEC = libc.FD_CLOEXEC;
    pub const FILE = libc.FILE;
    pub const fopen = libc.fopen;
    pub const free = libc.free;
    pub const F_SETFD = libc.F_SETFD;
    pub const getenv = libc.getenv;
    pub const mode_t = libc.mode_t;
    pub const O_DIRECTORY = libc.O_DIRECTORY;
    pub const open = libc.open;
    pub const O_RDONLY = libc.O_RDONLY;
    pub const setenv = libc.setenv;
    pub const snprintf = libc.snprintf;
    pub const strcmp = libc.strcmp;
    pub const strdup = libc.strdup;
    pub const strlen = libc.strlen;

    // anet — directory/config + dir_* Lua bindings (from dir_lua.h)
    pub const anet_directory_lua_init = anet.anet_directory_lua_init;
    pub const dir_appllist = anet.dir_appllist;
    pub const dir_applresolver = anet.dir_applresolver;
    pub const dir_applrevert = anet.dir_applrevert;
    pub const dir_ctrlrevert = anet.dir_ctrlrevert;
    pub const dir_endpoint = anet.dir_endpoint;
    pub const dir_flushreport = anet.dir_flushreport;
    pub const dir_getkey = anet.dir_getkey;
    pub const dir_hookresource = anet.dir_hookresource;
    pub const dir_launchresolver = anet.dir_launchresolver;
    pub const dir_launchtarget = anet.dir_launchtarget;
    pub const dir_linkdirectory = anet.dir_linkdirectory;
    pub const dir_matchkeys = anet.dir_matchkeys;
    pub const dir_messagealias = anet.dir_messagealias;
    pub const dir_refdirectory = anet.dir_refdirectory;
    pub const dir_storekey = anet.dir_storekey;
    pub const dir_write = anet.dir_write;
    pub const struct_global_cfg = anet.struct_global_cfg;

    // a12 — roles
    pub const ROLE_DIR = a12.ROLE_DIR;
};
const lua = @import("lua_api");

// External symbols defined in C
extern var INITIALIZED: bool;
extern var a12_trace_targets: c_int;

extern fn a12_set_trace_level(targets: c_int, fp: *c.FILE) void;
extern fn alt_nbio_register(
    L: *lua.lua_State,
    add: *const fn (fd: c_int, mode: c.mode_t, otag: usize) callconv(.c) bool,
    del: *const fn (fd: c_int, mode: c.mode_t, out: *usize) callconv(.c) bool,
    err: *const fn (L: *lua.lua_State, fd: c_int, tag: usize, src: [*:0]const u8) callconv(.c) void,
) void;

// Module-local state
var CFG: ?*c.struct_global_cfg = null;

// Lua helper
// Lua 5.1 compat: lua_rawlen was lua_objlen in 5.1
fn lua_rawlen_compat(L: ?*lua.lua_State, idx: c_int) usize {
    return @intCast(lua.lua_objlen(L, idx));
}

// Trace group names (mirrors trace_groups[] in C)
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

// Permission table mapping
// Each entry maps a Lua key string to a pointer-to-pointer inside dirsrv opts.
// We use indices into this array rather than storing function pointers.
const PermKey = struct {
    key: [*:0]const u8,
};

const permlut = [_]PermKey{
    .{ .key = "source" },
    .{ .key = "dir" },
    .{ .key = "appl" },
    .{ .key = "resources" },
    .{ .key = "appl_controller" },
    .{ .key = "admin" },
    .{ .key = "monitor" },
    .{ .key = "applhost" },
    .{ .key = "appl_install" },
    .{ .key = "reference" },
};

// Return the **char pointer for the perm slot identified by index i.
fn permval_ptr(i: usize) ?*?[*:0]u8 {
    const cfg = CFG orelse return null;
    return switch (i) {
        0 => @ptrCast(&cfg.dirsrv.allow_src),
        1 => @ptrCast(&cfg.dirsrv.allow_dir),
        2 => @ptrCast(&cfg.dirsrv.allow_appl),
        3 => @ptrCast(&cfg.dirsrv.allow_ares),
        4 => @ptrCast(&cfg.dirsrv.allow_ctrl),
        5 => @ptrCast(&cfg.dirsrv.allow_admin),
        6 => @ptrCast(&cfg.dirsrv.allow_monitor),
        7 => @ptrCast(&cfg.dirsrv.allow_applhost),
        8 => @ptrCast(&cfg.dirsrv.allow_install),
        9 => @ptrCast(&cfg.dirsrv.allow_reference),
        else => null,
    };
}

// Helper: accept bool-or-int-1/0 from Lua
fn alua_tobnumber(L: ?*lua.lua_State, ind: c_int, key: [*:0]const u8) bool {
    if (lua.lua_type(L, ind) == lua.LUA_TBOOLEAN) {
        return lua.lua_toboolean(L, ind) != 0;
    } else if (lua.lua_type(L, ind) == lua.LUA_TNUMBER) {
        const num: c_int = @intFromFloat(lua.lua_tonumber(L, ind));
        if (num != 0 and num != 1) {
            _ = lua.luaL_error(L, "%s = [0 | false | true | 1]\n", key);
        }
        return num == 1;
    } else {
        _ = lua.luaL_error(L, "%s = [int | bool]\n", key);
        return false;
    }
}

// config.directory __index
fn cfg_index_directory(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    if (c.strcmp(key, "allow_tunnel") == 0) {
        lua.lua_pushboolean(L, if (CFG.?.dirsrv.allow_tunnel) 1 else 0);
        return 1;
    }
    if (c.strcmp(key, "log_level") == 0) {
        lua.lua_pushnumber(L, @floatFromInt(a12_trace_targets));
        return 1;
    }
    _ = lua.luaL_error(L, "unknown key: %s, allowed: allow_tunnel, log_level\n", key);
    return 0;
}

// config.directory __newindex
fn cfg_newindex_directory(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);

    if (c.strcmp(key, "allow_tunnel") == 0) {
        CFG.?.dirsrv.allow_tunnel = alua_tobnumber(L, 3, "allow_tunnel");
    } else if (c.strcmp(key, "flush_report") == 0) {
        CFG.?.dirsrv.flush_on_report = alua_tobnumber(L, 3, "flush_report");
    } else if (c.strcmp(key, "discover_beacon") == 0) {
        CFG.?.dirsrv.discover_beacon = alua_tobnumber(L, 3, "discover_beacon");
    } else if (c.strcmp(key, "log_level") == 0) {
        if (lua.lua_type(L, 3) == lua.LUA_TTABLE) {
            const n: c_int = @intCast(lua_rawlen_compat(L, 3));
            var i: c_int = 0;
            while (i < n) : (i += 1) {
                _ = lua.lua_rawgeti(L, 3, i + 1);
                if (lua.lua_type(L, -1) == lua.LUA_TSTRING) {
                    const grp = lua.lua_tolstring(L, -1, null);
                    var found = false;
                    for (trace_groups, 0..) |tg, j| {
                        if (c.strcmp(grp, tg) == 0) {
                            a12_trace_targets |= @as(c_int, 1) << @intCast(j);
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        _ = lua.luaL_error(L, "log_level = ... unknown group: %s\n", grp);
                    }
                    lua.lua_settop(L, -2); // pop
                } else {
                    _ = lua.luaL_error(L, "log_level = [num] | {group1str, group2str, ...}\n");
                }
            }
        } else if (lua.lua_type(L, 3) == lua.LUA_TNUMBER) {
            a12_trace_targets = @intFromFloat(lua.lua_tonumber(L, 3));
        }
    } else if (c.strcmp(key, "log_target") == 0) {
        const path = lua.lua_tolstring(L, 3, null);
        const fpek = c.fopen(path, "w");
        if (fpek == null) {
            _ = lua.luaL_error(L, "couldn't open (w+): config.log_target = %s\n", path);
        } else {
            a12_set_trace_level(a12_trace_targets, fpek.?);
        }
    } else if (c.strcmp(key, "listen_port") == 0) {
        const port: c_int = @intFromFloat(lua.lua_tonumber(L, 3));
        if (port <= 0 or port > 65535) {
            _ = lua.luaL_error(L, "port (%d) = 0 < n < 65536\n", port);
        } else {
            var port_str: [6]u8 = undefined;
            _ = std.fmt.bufPrintZ(&port_str, "{d}", .{port}) catch unreachable;
            CFG.?.meta.port = c.strdup(&port_str);
        }
    } else if (c.strcmp(key, "runner_process") == 0) {
        CFG.?.dirsrv.runner_process = lua.lua_toboolean(L, 3) != 0;
    } else {
        _ = lua.luaL_error(L,
            "unknown key: config.%s, allowed: " ++
            "allow_tunnel, discover_beacon, directory_server, " ++
            "flush_report, log_level, log_target, listen_port, " ++
            "runner_process\n",
            key);
    }
    return 0;
}

// config.security __index
fn cfgsec_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    if (c.strcmp(key, "secret") == 0) {
        _ = lua.lua_pushstring(L, &CFG.?.meta.opts.*.secret);
        return 1;
    }
    if (c.strcmp(key, "soft_auth") == 0) {
        lua.lua_pushboolean(L, if (CFG.?.soft_auth) 1 else 0);
        return 1;
    }
    if (c.strcmp(key, "checksum_cap_mb") == 0) {
        lua.lua_pushnumber(L, @floatFromInt(CFG.?.meta.opts.*.checksum_cap_mb));
        return 1;
    }
    if (c.strcmp(key, "rekey_pqc") == 0) {
        lua.lua_pushboolean(L, if (CFG.?.meta.opts.*.pqc_rekey) 1 else 0);
        return 1;
    }
    if (c.strcmp(key, "rekey_bytes") == 0) {
        lua.lua_pushnumber(L, @floatFromInt(CFG.?.meta.opts.*.rekey_bytes));
        return 1;
    }
    _ = lua.luaL_error(L, "unknown key: %s, allowed: secret, soft_auth, rekey_bytes\n", key);
    return 0;
}

// config.security __newindex
fn cfgsec_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    if (c.strcmp(key, "secret") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (c.strlen(val) > 31 or val[0] == 0) {
            _ = lua.luaL_error(L, "secret = (0 < string < 32)\n");
        } else {
            _ = c.snprintf(&CFG.?.meta.opts.*.secret, 32, "%s", val);
        }
    } else if (c.strcmp(key, "soft_auth") == 0) {
        CFG.?.soft_auth = alua_tobnumber(L, 3, "soft_auth");
    } else if (c.strcmp(key, "rekey_bytes") == 0) {
        CFG.?.meta.opts.*.rekey_bytes = @intFromFloat(lua.luaL_checknumber(L, 3));
    } else if (c.strcmp(key, "rekey_pqc") == 0) {
        CFG.?.meta.opts.*.pqc_rekey = alua_tobnumber(L, 3, "rekey_pqc");
    } else if (c.strcmp(key, "checksum_cap_mb") == 0) {
        CFG.?.meta.opts.*.checksum_cap_mb = @intFromFloat(lua.luaL_checknumber(L, 3));
    } else {
        _ = lua.luaL_error(L, "unknown key: %s, allowed: secret, soft_auth, rekey_bytes", key);
    }
    return 0;
}

// config.permissions __index
fn cfgperm_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    for (permlut, 0..) |pe, i| {
        if (c.strcmp(key, pe.key) == 0) {
            const pp = permval_ptr(i) orelse return 0;
            if (pp.*) |s| {
                _ = lua.lua_pushstring(L, s);
            } else {
                _ = lua.lua_pushstring(L, "");
            }
            return 1;
        }
    }
    return 0;
}

// config.permissions __newindex
fn cfgperm_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);
    for (permlut, 0..) |pe, i| {
        if (c.strcmp(key, pe.key) == 0) {
            const pp = permval_ptr(i) orelse break;
            if (pp.*) |old| {
                c.free(old);
            }
            const val = lua.luaL_checklstring(L, 3, null);
            pp.* = c.strdup(val);
            return 0;
        }
    }
    _ = lua.luaL_error(L, "Unknown key: permissions.%s\n", key);
    return 0;
}

// config.paths __index
fn cfgpath_index(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);

    if (c.strcmp(key, "database") == 0) {
        _ = lua.lua_pushstring(L, CFG.?.db_file);
        return 1;
    }
    if (c.strcmp(key, "appl") == 0) {
        const env = c.getenv("ARCAN_APPLBASEPATH");
        if (env == null) lua.lua_pushnil(L) else {
            _ = lua.lua_pushstring(L, env);
        }
        return 1;
    }
    if (c.strcmp(key, "appl_server_data") == 0) {
        if (CFG.?.dirsrv.appl_server_datapath) |p| { _ = lua.lua_pushstring(L, p); } else lua.lua_pushnil(L);
        return 1;
    }
    if (c.strcmp(key, "appl_server") == 0) {
        if (CFG.?.dirsrv.appl_server_path) |p| { _ = lua.lua_pushstring(L, p); } else lua.lua_pushnil(L);
        return 1;
    }
    if (c.strcmp(key, "appl_server_log") == 0) {
        if (CFG.?.dirsrv.appl_logpath) |p| { _ = lua.lua_pushstring(L, p); } else lua.lua_pushnil(L);
        return 1;
    }
    if (c.strcmp(key, "applhost_loader") == 0) {
        if (CFG.?.dirsrv.applhost_path) |p| { _ = lua.lua_pushstring(L, p); } else lua.lua_pushnil(L);
        return 1;
    }
    if (c.strcmp(key, "keystore") == 0) {
        if (INITIALIZED) {
            _ = lua.luaL_error(L, "config.keystore read-only after init()");
            return 0;
        }
        const env = c.getenv("ARCAN_STATEPATH");
        if (env == null) lua.lua_pushnil(L) else {
            _ = lua.lua_pushstring(L, env);
        }
        return 1;
    }

    _ = lua.luaL_error(L,
        "unknown path: config.paths.%s, " ++
        "accepted: database, appl, appl_server, " ++
        "appl_server_log, applhost_loader, keystore, resources\n",
        key);
    return 0;
}

// config.paths __newindex
fn cfgpath_newindex(L: ?*lua.lua_State) callconv(.c) c_int {
    const key = lua.luaL_checklstring(L, 2, null);

    if (c.strcmp(key, "appl") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.directory != -1) {
            _ = c.close(CFG.?.directory);
        }
        CFG.?.directory = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (CFG.?.directory == -1) {
            _ = lua.luaL_error(L, "config.paths.appl = %s, can't open as directory\n", val);
        } else {
            _ = c.fcntl(CFG.?.directory, c.F_SETFD, c.FD_CLOEXEC);
            _ = c.setenv("ARCAN_APPLBASEPATH", val, 1);
        }
        return 0;
    }

    if (c.strcmp(key, "appl_server_temp") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.appl_server_temp_path) |old| {
            c.free(old);
            _ = c.close(CFG.?.dirsrv.appl_server_temp_dfd);
        }
        const dirfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (dirfd == -1) {
            _ = lua.luaL_error(L, "config.paths.appl_server_temp = %s, can't open as directory\n", val);
        } else {
            CFG.?.dirsrv.appl_server_temp_path = c.strdup(val);
            CFG.?.dirsrv.appl_server_temp_dfd = dirfd;
            _ = c.fcntl(dirfd, c.F_SETFD, c.FD_CLOEXEC);
        }
        return 0;
    }

    if (c.strcmp(key, "applhost_loader") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.applhost_path) |old| c.free(old);
        CFG.?.dirsrv.applhost_path = c.strdup(val);
        return 0;
    }

    if (c.strcmp(key, "appl_server_data") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.appl_server_datapath) |old| {
            c.free(old);
            _ = c.close(CFG.?.dirsrv.appl_server_datadfd);
        }
        const dirfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (dirfd == -1) {
            _ = lua.luaL_error(L, "config.paths.appl_server_data = %s, can't open as directory\n", val);
        } else {
            CFG.?.dirsrv.appl_server_datapath = c.strdup(val);
            CFG.?.dirsrv.appl_server_datadfd = dirfd;
            _ = c.fcntl(dirfd, c.F_SETFD, c.FD_CLOEXEC);
        }
        return 0;
    }

    if (c.strcmp(key, "appl_server") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.appl_server_path) |old| {
            c.free(old);
            _ = c.close(CFG.?.dirsrv.appl_server_dfd);
        }
        const dirfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (dirfd == -1) {
            _ = lua.luaL_error(L, "config.paths.appl_server = %s, can't open as directory\n", val);
        } else {
            CFG.?.dirsrv.appl_server_path = c.strdup(val);
            CFG.?.dirsrv.appl_server_dfd = dirfd;
            _ = c.fcntl(dirfd, c.F_SETFD, c.FD_CLOEXEC);
        }
        return 0;
    }

    if (c.strcmp(key, "applhost") == 0) {
        // deliberately empty — placeholder for future implementation
        return 0;
    }

    if (c.strcmp(key, "appl_server_log") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.appl_logpath) |old| {
            c.free(old);
            _ = c.close(CFG.?.dirsrv.appl_logdfd);
        }
        CFG.?.dirsrv.appl_logpath = c.strdup(val);
        CFG.?.dirsrv.appl_logdfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (CFG.?.dirsrv.appl_logdfd == -1) {
            _ = lua.luaL_error(L, "config.paths.appl_server_log = %s, can't open as directory\n", val);
        } else {
            _ = c.fcntl(CFG.?.dirsrv.appl_logdfd, c.F_SETFD, c.FD_CLOEXEC);
        }
        return 0;
    }

    if (c.strcmp(key, "resources") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.dirsrv.resource_path) |old| {
            c.free(old);
            _ = c.close(CFG.?.dirsrv.resource_dfd);
        }
        const dirfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (dirfd == -1) {
            _ = lua.luaL_error(L, "config.paths.appl_server = %s, can't open as directory\n", val);
        } else {
            CFG.?.dirsrv.resource_path = c.strdup(val);
            CFG.?.dirsrv.resource_dfd = dirfd;
            _ = c.fcntl(dirfd, c.F_SETFD, c.FD_CLOEXEC);
        }
        return 0;
    }

    // Remaining keys are read-only after init
    if (INITIALIZED) {
        _ = lua.luaL_error(L, "config.paths.%s, read/only after init()\n", key);
        return 0;
    }

    if (c.strcmp(key, "database") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        if (CFG.?.db_file) |old| c.free(old);
        CFG.?.db_file = c.strdup(val);
    } else if (c.strcmp(key, "keystore") == 0) {
        const val = lua.luaL_checklstring(L, 3, null);
        const dirfd = c.open(val, c.O_RDONLY | c.O_DIRECTORY);
        if (dirfd == -1) {
            _ = lua.luaL_error(L, "config.paths.keystore = %s, can't open as directory\n", val);
        } else {
            if (CFG.?.meta.keystore.unnamed_0.directory.dirfd > 0) {
                _ = c.close(CFG.?.meta.keystore.unnamed_0.directory.dirfd);
            }
            CFG.?.meta.keystore.unnamed_0.directory.dirfd = dirfd;
            _ = c.fcntl(dirfd, c.F_SETFD, c.FD_CLOEXEC);
            _ = c.setenv("ARCAN_STATEPATH", val, 1);
        }
    } else {
        _ = lua.luaL_error(L,
            "unknown path key (%s), accepted:\n\t\n" ++
            "database, appl, appl_server, keystore, resources\n",
            key);
    }

    return 0;
}

// NBIO stub handlers
// The admin interface only uses nbio for :writes and clocks differently,
// so these are intentional no-ops.
fn add_source(fd: c_int, mode: c.mode_t, otag: usize) callconv(.c) bool {
    _ = fd;
    _ = mode;
    _ = otag;
    return true;
}

fn del_source(fd: c_int, mode: c.mode_t, out: *usize) callconv(.c) bool {
    _ = fd;
    _ = mode;
    _ = out;
    return true;
}

fn error_nbio(L: *lua.lua_State, fd: c_int, tag: usize, src: [*:0]const u8) callconv(.c) void {
    _ = L;
    _ = fd;
    _ = tag;
    _ = src;
}

// Public entry point
pub export fn anet_directory_lua_cfg(C: *c.struct_global_cfg, L: *lua.lua_State) void {
    CFG = C;
    CFG.?.meta.mode = 1; // anet_shmif_cl, but with --directory is -l
    CFG.?.meta.opts.*.local_role = c.ROLE_DIR;

    // Register nbio hooks
    alt_nbio_register(L, add_source, del_source, error_nbio);

    // Override __index/__newindex on "cfgtbl" (the global config table metatable)
    _ = lua.luaL_newmetatable(L, "cfgtbl"); // create if absent, push it
    // luaL_newmetatable pushes existing MT if present; we just overwrite fields
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "cfgtbl");
    lua.lua_pushcfunction(L, cfg_index_directory);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfg_newindex_directory);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_settop(L, -2); // pop cfgtbl

    // "dircl" metatable — used for per-client userdata
    _ = lua.luaL_newmetatable(L, "dircl");
    lua.lua_pushvalue(L, -1);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushvalue(L, -1);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_pushcfunction(L, @ptrCast(&c.dir_write));
    lua.lua_setfield(L, -2, "write");
    lua.lua_pushcfunction(L, @ptrCast(&c.dir_endpoint));
    lua.lua_setfield(L, -2, "endpoint");
    lua.lua_settop(L, -2); // pop dircl

    // "cfgpermtbl" metatable
    _ = lua.luaL_newmetatable(L, "cfgpermtbl");
    lua.lua_pushcfunction(L, cfgperm_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfgperm_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_settop(L, -2);

    // "cfgsectbl" metatable
    _ = lua.luaL_newmetatable(L, "cfgsectbl");
    lua.lua_pushcfunction(L, cfgsec_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfgsec_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_settop(L, -2);

    // "cfgpathtbl" metatable
    _ = lua.luaL_newmetatable(L, "cfgpathtbl");
    lua.lua_pushcfunction(L, cfgpath_index);
    lua.lua_setfield(L, -2, "__index");
    lua.lua_pushcfunction(L, cfgpath_newindex);
    lua.lua_setfield(L, -2, "__newindex");
    lua.lua_settop(L, -2);

    // Build "config" global: attach cfgtbl metatable + sub-tables
    _ = lua.lua_getglobal(L, "config"); // TABLE
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "cfgtbl");
    _ = lua.lua_setmetatable(L, -2);

    // config.permissions
    _ = lua.lua_pushstring(L, "permissions");
    lua.lua_createtable(L, 0, 10);
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "cfgpermtbl");
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_rawset(L, -3);

    // config.security
    _ = lua.lua_pushstring(L, "security");
    lua.lua_createtable(L, 0, 10);
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "cfgsectbl");
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_rawset(L, -3);

    // config.paths
    _ = lua.lua_pushstring(L, "paths");
    lua.lua_createtable(L, 0, 10);
    _ = lua.lua_getfield(L, lua.LUA_REGISTRYINDEX, "cfgpathtbl");
    _ = lua.lua_setmetatable(L, -2);
    lua.lua_rawset(L, -3);

    lua.lua_setglobal(L, "config"); // pop config

    // Expose autostart table
    lua.lua_createtable(L, 0, 0);
    lua.lua_setglobal(L, "autostart");

    // Expose admin functions
    lua.lua_pushcfunction(L, @ptrCast(&c.dir_linkdirectory));
    lua.lua_setglobal(L, "link_directory");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_refdirectory));
    lua.lua_setglobal(L, "reference_directory");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_launchtarget));
    lua.lua_setglobal(L, "launch_target");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_matchkeys));
    lua.lua_setglobal(L, "match_keys");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_storekey));
    lua.lua_setglobal(L, "store_key");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_getkey));
    lua.lua_setglobal(L, "get_key");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_flushreport));
    lua.lua_setglobal(L, "flush_report");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_appllist));
    lua.lua_setglobal(L, "list_appl");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_messagealias));
    lua.lua_setglobal(L, "alias_appl");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_applrevert));
    lua.lua_setglobal(L, "revert_appl");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_ctrlrevert));
    lua.lua_setglobal(L, "revert_ctrl");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_launchresolver));
    lua.lua_setglobal(L, "launch_resolver");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_applresolver));
    lua.lua_setglobal(L, "appl_set_resolver");

    lua.lua_pushcfunction(L, @ptrCast(&c.dir_hookresource));
    lua.lua_setglobal(L, "hook_resource");

    c.anet_directory_lua_init(C, @ptrCast(L));
}
