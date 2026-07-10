// bun_runtime — Bun VM lifecycle wrapper for afsrv_bun.
//
// Phase 3e scaffold: the public surface (init / runEntryPoint /
// deinit) is in place but the bodies short-circuit to
// Error.NotLinked because bun_obj is not yet linked into
// afsrv_bun. Phase 3e-link replaces these with the C-ABI shim
// that drives Bun's Cli.start equivalent — at that point
// init/runEntryPoint will install signal handlers, build a Bun
// VM, loadEntryPoint(path), and pump the event loop.
//
// Keeping this scaffold separate from bun.zig lets the
// frameserver carry the full argv → entry → emit-marker flow
// today, with the only diff between scaffold and 3e-link being
// the bodies of the three functions below.

const std = @import("std");

pub const Error = error{
    NotLinked,
    InitFailed,
    EntryNotFound,
    EvaluationFailed,
};

pub const Runtime = struct {
    initialized: bool = false,
};

pub fn init() Error!Runtime {
    return Error.NotLinked;
}

pub fn runEntryPoint(rt: *Runtime, path: []const u8) Error!void {
    _ = rt;
    _ = path;
    return Error.NotLinked;
}

pub fn deinit(rt: *Runtime) void {
    rt.initialized = false;
}
