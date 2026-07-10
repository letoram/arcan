// Compile-only harness: pulls the zstd_enc modules through semantic
// analysis so `zig test --test-no-exec` validates they build standalone
// before build.zig is wired up (scheduled for a later slice).

const std = @import("std");

pub const zstd_common = @import("zstd_common.zig");
pub const xxhash = @import("xxhash.zig");
pub const hist = @import("hist.zig");
pub const entropy_common = @import("entropy_common.zig");
pub const fse_decompress = @import("fse_decompress.zig");
pub const fse_compress = @import("fse_compress.zig");
pub const huf_compress = @import("huf_compress.zig");
pub const zstd_compress_literals = @import("zstd_compress_literals.zig");
pub const zstd_compress_sequences = @import("zstd_compress_sequences.zig");
pub const zstd_compress = @import("zstd_compress.zig");
pub const zstd_cwksp = @import("zstd_cwksp.zig");
pub const zstd_cparams = @import("zstd_cparams.zig");
pub const zstd_match_state = @import("zstd_match_state.zig");
pub const zstd_reset = @import("zstd_reset.zig");
pub const zstd_cctx = @import("zstd_cctx.zig");
pub const zstd_block = @import("zstd_block.zig");
pub const zstd_window = @import("zstd_window.zig");
pub const zstd_fast = @import("zstd_fast.zig");
pub const zstd_frame = @import("zstd_frame.zig");
pub const runtime_test = @import("runtime_test.zig");

test {
    std.testing.refAllDecls(zstd_common);
    std.testing.refAllDecls(xxhash);
    std.testing.refAllDecls(hist);
    std.testing.refAllDecls(entropy_common);
    std.testing.refAllDecls(fse_decompress);
    std.testing.refAllDecls(fse_compress);
    std.testing.refAllDecls(huf_compress);
    std.testing.refAllDecls(zstd_compress_literals);
    std.testing.refAllDecls(zstd_compress_sequences);
    std.testing.refAllDecls(zstd_compress);
    std.testing.refAllDecls(zstd_cwksp);
    std.testing.refAllDecls(zstd_cparams);
    std.testing.refAllDecls(zstd_match_state);
    std.testing.refAllDecls(zstd_reset);
    std.testing.refAllDecls(zstd_cctx);
    std.testing.refAllDecls(zstd_block);
    std.testing.refAllDecls(zstd_window);
    std.testing.refAllDecls(zstd_fast);
    std.testing.refAllDecls(zstd_frame);
    std.testing.refAllDecls(runtime_test);
}
