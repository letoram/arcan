// Runtime end-to-end compress + decompress round-trip at level 3.
// Feeds our pure-Zig encoder into std.compress.zstd.Decompress.
// Added for slice 5g of the encoder port.

const std = @import("std");
const common = @import("zstd_common.zig");
const enc = @import("zstd_cctx.zig");
// Pull fse_decompress in so its FSE_decompress_wksp_bmi2 export is linked —
// entropy_common (used during HUF table reads when decoding literals we
// ourselves emitted during level-3 compression) resolves to it.
const _fse_decompress = @import("fse_decompress.zig");

comptime {
    _ = _fse_decompress;
}

test "compress short source: does not hang" {
    const cctx = enc.ZSTD_createCCtx() orelse return error.CreateFailed;
    defer _ = enc.ZSTD_freeCCtx(cctx);

    // 5 bytes — below the minBlockSize (6) in buildSeqStore, so this should
    // hit the "noCompress" fast path with no match-finder invocation.
    const src = [_]u8{ 1, 2, 3, 4, 5 };
    var out: [256]u8 = undefined;
    const out_sz = enc.ZSTD_compressCCtx(cctx, &out, out.len, @ptrCast(@constCast(&src)), src.len, 3);
    try std.testing.expect(common.ZSTD_isError(out_sz) == 0);
}

test "compress 20 unique bytes: entropy path" {
    const cctx = enc.ZSTD_createCCtx() orelse return error.CreateFailed;
    defer _ = enc.ZSTD_freeCCtx(cctx);

    const src = "ABCDEFGHIJKLMNOPQRST";
    var out: [256]u8 = undefined;
    const out_sz = enc.ZSTD_compressCCtx(cctx, &out, out.len, @ptrCast(@constCast(src.ptr)), src.len, 3);
    try std.testing.expect(common.ZSTD_isError(out_sz) == 0);
}

test "compress+decompress round trip at level 3" {
    const cctx = enc.ZSTD_createCCtx() orelse return error.CreateFailed;
    defer _ = enc.ZSTD_freeCCtx(cctx);

    const src = "Hello, Zig-native zstd!".* ** 100;
    var out: [4096]u8 = undefined;
    const out_sz = enc.ZSTD_compressCCtx(
        cctx,
        &out,
        out.len,
        @constCast(&src),
        src.len,
        3,
    );
    if (common.ZSTD_isError(out_sz) != 0) return error.CompressFailed;

    // Decompress via Zig std.
    const zstd = std.compress.zstd;
    var src_reader = std.Io.Reader.fixed(out[0..out_sz]);
    const scratch_len = zstd.default_window_len + zstd.block_size_max;
    const scratch = try std.testing.allocator.alloc(u8, scratch_len);
    defer std.testing.allocator.free(scratch);
    var decomp = zstd.Decompress.init(&src_reader, scratch, .{});
    var dst: [4096]u8 = undefined;
    var dst_writer = std.Io.Writer.fixed(&dst);
    const n = try decomp.reader.streamRemaining(&dst_writer);
    try std.testing.expectEqualSlices(u8, src[0..], dst[0..n]);
}
