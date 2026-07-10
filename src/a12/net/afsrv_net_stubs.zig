// Stub implementations for symbols that afsrv_net links against but
// whose full Zig implementations (net_lua.zig, net_lua_cfg.zig, dir_srv.zig)
// aren't yet wired into the build. Returning safe defaults so the binary
// links; calling these paths at runtime will fail gracefully.

const std = @import("std");

export fn anet_client_lua_getpath(key: [*:0]const u8) callconv(.c) ?[*:0]const u8 {
    _ = key;
    return null;
}

export fn anet_client_execargs(
    name: [*:0]const u8,
    meta: ?*anyopaque,
    manifest: ?*anyopaque,
) callconv(.c) bool {
    _ = name;
    _ = meta;
    _ = manifest;
    return false;
}

export fn anet_lua_init(cfg: ?*anyopaque) callconv(.c) bool {
    _ = cfg;
    return false;
}

export fn dirsrv_global_lock(file: [*c]const u8, line: c_int) callconv(.c) void {
    _ = file;
    _ = line;
}

export fn dirsrv_global_unlock(file: [*c]const u8, line: c_int) callconv(.c) void {
    _ = file;
    _ = line;
}

export fn dirsrv_set_source_mask(mask: c_int) callconv(.c) void {
    _ = mask;
}

export var dirsrv_opts: u64 = 0;

// Process-wide directory/network config. arcan-net's net.zig owns this in
// the full binary; afsrv_net only compiles the client-side slice
// (dir_cl.zig consumes via `extern var global`), so provide the storage
// here with the same defaults net.zig uses.
const anet = @import("anet_types");

pub export var global: anet.struct_global_cfg = blk: {
    var g = std.mem.zeroes(anet.struct_global_cfg);
    g.trust_domain = @constCast("outbound");
    g.backpressure_soft = 1;
    g.backpressure = 1;
    g.directory = -1;
    g.dircl.source_port = 6681;
    g.dirsrv.allow_tunnel = true;
    g.dirsrv.runner_process = true;
    g.dirsrv.resource_dfd = -1;
    g.dirsrv.appl_server_dfd = -1;
    g.dirsrv.appl_server_datadfd = -1;
    g.dirsrv.appl_server_temp_dfd = -1;
    break :blk g;
};
