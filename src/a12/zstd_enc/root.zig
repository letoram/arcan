// Root module for the zstd encoder port. Compiled as a single object so
// `pub export fn` declarations in the imported files produce exactly one
// C-ABI symbol each. Importing these from multiple sibling .zig objects
// causes duplicate-symbol errors at link time.

pub const zstd_common = @import("zstd_common.zig");
pub const xxhash = @import("xxhash.zig");
pub const hist = @import("hist.zig");
pub const entropy_common = @import("entropy_common.zig");
pub const fse_decompress = @import("fse_decompress.zig");
pub const fse_compress = @import("fse_compress.zig");
pub const huf_compress = @import("huf_compress.zig");
pub const zstd_compress_literals = @import("zstd_compress_literals.zig");
pub const zstd_compress_sequences = @import("zstd_compress_sequences.zig");
pub const zstd_cwksp = @import("zstd_cwksp.zig");
pub const zstd_cparams = @import("zstd_cparams.zig");
pub const zstd_match_state = @import("zstd_match_state.zig");
pub const zstd_reset = @import("zstd_reset.zig");
pub const zstd_compress = @import("zstd_compress.zig");
pub const zstd_cctx = @import("zstd_cctx.zig");
pub const zstd_block = @import("zstd_block.zig");
pub const zstd_window = @import("zstd_window.zig");
pub const zstd_fast = @import("zstd_fast.zig");
pub const zstd_frame = @import("zstd_frame.zig");

const std = @import("std");

// Stubs for symbols the ported files reference but the upstream
// definitions aren't yet ported. Callers from our arcan-net path don't
// reach these (ZSTD_compress_frameChunk itself is stubbed in zstd_block
// and zstd_frame until slice 5g ports ZSTD_buildSeqStore + entropy
// compression), so returning safe defaults satisfies the linker.

/// Upstream: zstd_compress_superblock.c — builds entropy stats for a block's
/// literals section. Stub returns 0 (no work done). Only reached via the
/// superblock compress path which our arcan-net callers don't exercise.
pub export fn ZSTD_buildBlockEntropyStats_literals(
    src: ?*const anyopaque,
    src_size: usize,
    prev_huf: ?*anyopaque,
    next_huf: ?*anyopaque,
    hufMetadata: ?*anyopaque,
    literalsCompressionIsDisabled: c_int,
    workspace: ?*anyopaque,
    wkspSize: usize,
) callconv(.c) usize {
    _ = src; _ = src_size; _ = prev_huf; _ = next_huf; _ = hufMetadata;
    _ = literalsCompressionIsDisabled; _ = workspace; _ = wkspSize;
    return 0;
}

/// Upstream: zstd_compress_superblock.c — counterpart for the sequences
/// section. Stub returns 0 for the same reason as the literals variant.
pub export fn ZSTD_buildBlockEntropyStats_sequences(
    seqStorePtr: ?*const anyopaque,
    prevEntropy: ?*const anyopaque,
    nextEntropy: ?*anyopaque,
    cctxParams: ?*const anyopaque,
    fseMetadata: ?*anyopaque,
    workspace: ?*anyopaque,
    wkspSize: usize,
) callconv(.c) usize {
    _ = seqStorePtr; _ = prevEntropy; _ = nextEntropy; _ = cctxParams;
    _ = fseMetadata; _ = workspace; _ = wkspSize;
    return 0;
}

// Slice 5g will port ZSTD_compress_frameChunk (the block loop with
// ZSTD_buildSeqStore + ZSTD_entropyCompressSeqStore) and ZSTD_compress_
// insertDictionary. Until then, the frame-chunk emitter in zstd_frame.zig
// is the real wrapper but the inner compress call returns a no-compress
// signal so ZSTD_compressCCtx sees raw blocks at the wire.

comptime {
    // Force Zig to emit every `pub export fn` in the transitive import graph.
    // Each `_ = @import` reference is enough to pull the module's `export fn`
    // declarations into the compilation unit; they're C-ABI-visible at link
    // time without having to be called from here.
    _ = zstd_common;
    _ = xxhash;
    _ = hist;
    _ = entropy_common;
    _ = fse_decompress;
    _ = fse_compress;
    _ = huf_compress;
    _ = zstd_compress_literals;
    _ = zstd_compress_sequences;
    _ = zstd_cwksp;
    _ = zstd_cparams;
    _ = zstd_match_state;
    _ = zstd_reset;
    _ = zstd_compress;
    _ = zstd_cctx;
    _ = zstd_block;
    _ = zstd_window;
    _ = zstd_fast;
    _ = zstd_frame;
}
