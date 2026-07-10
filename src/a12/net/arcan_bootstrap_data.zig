// Pure-Zig replacement for engine/arcan_bootstrap.h — embeds
// arcan_bootstrap.lua as a byte array and exposes `arcan_bootstrap_lua` +
// `arcan_bootstrap_lua_len` with C linkage so dir_lua_appl.zig (and the
// equivalent C paths in the upstream directory server) can luaL_loadbuffer
// the sandbox preamble straight out of the binary.

const bootstrap_bytes = @embedFile("arcan_bootstrap.lua");

pub export const arcan_bootstrap_lua: [*]const u8 = bootstrap_bytes.ptr;
pub export const arcan_bootstrap_lua_len: usize = bootstrap_bytes.len;
