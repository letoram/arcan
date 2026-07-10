// Comptime-embedded arcan_bootstrap.lua source.
// This file lives in src/engine/ so @embedFile can reach arcan_bootstrap.lua
// (Zig restricts @embedFile to files within the package directory tree).
pub const data = @embedFile("arcan_bootstrap.lua");
