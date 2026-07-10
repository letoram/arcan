// Pure-Zig definition of the directory-server `INITIALIZED` flag. Upstream
// defines it as a file-scope bool in net_lua.c; we provide it here so the
// `extern var INITIALIZED` in dir_lua_cfg.zig / net_lua_cfg.zig links.
//
// The process-wide `global` (struct_global_cfg) is owned by
// src/a12/net/net.zig, which populates it from argv parsing.

pub export var INITIALIZED: bool = false;
