// Bilinear image resize — pure Zig replacement for stb_image_resize2.
// Provides the same C ABI as STB's stbir_resize_uint8_linear so that
// arcan_renderfun.zig and arcan_ttf.zig can call it without changes.

/// Bilinear RGBA image resize. Returns output pointer on success, null on failure.
/// pixel_layout: number of channels (typically 4 for RGBA)
/// stride of 0 means tightly packed (w * channels)
pub export fn stbir_resize_uint8_linear(
    input: [*c]const u8,
    input_w: c_int,
    input_h: c_int,
    input_stride: c_int,
    output: [*c]u8,
    output_w: c_int,
    output_h: c_int,
    output_stride: c_int,
    pixel_layout: c_int,
) callconv(.c) [*c]u8 {
    // Validate parameters
    if (input_w <= 0 or input_h <= 0 or output_w <= 0 or output_h <= 0)
        return null;
    if (pixel_layout <= 0 or pixel_layout > 4)
        return null;
    if (input == null or output == null)
        return null;

    const in_w: usize = @intCast(input_w);
    const in_h: usize = @intCast(input_h);
    const out_w: usize = @intCast(output_w);
    const out_h: usize = @intCast(output_h);
    const channels: usize = @intCast(pixel_layout);

    const in_stride: usize = if (input_stride <= 0) in_w * channels else @intCast(input_stride);
    const out_stride: usize = if (output_stride <= 0) out_w * channels else @intCast(output_stride);

    const in: [*]const u8 = input;
    const out: [*]u8 = output;

    // Special case: 1x1 output — average of all input or just sample center
    if (out_w == 1 and out_h == 1) {
        // Sample center pixel
        const cx = in_w / 2;
        const cy = in_h / 2;
        const src_off = cy * in_stride + cx * channels;
        const dst_off: usize = 0;
        for (0..channels) |ch| {
            out[dst_off + ch] = in[src_off + ch];
        }
        return output;
    }

    for (0..out_h) |oy| {
        // Map output y to input y
        // For out_h==1: sy_fixed = 0 (top row)
        // Otherwise: sy = oy * (in_h - 1) / (out_h - 1)
        const sy_numer: u64 = @as(u64, oy) * @as(u64, in_h - 1) * 256;
        const sy_denom: u64 = if (out_h > 1) @as(u64, out_h - 1) else 1;
        const sy_fixed: u64 = sy_numer / sy_denom; // 8.8 fixed point
        const sy_int: usize = @intCast(sy_fixed >> 8);
        const sy_frac: u32 = @intCast(sy_fixed & 0xFF);

        const y0: usize = sy_int;
        const y1: usize = if (sy_int + 1 < in_h) sy_int + 1 else sy_int;

        const row0 = in + y0 * in_stride;
        const row1 = in + y1 * in_stride;
        const out_row = out + oy * out_stride;

        for (0..out_w) |ox| {
            const sx_numer: u64 = @as(u64, ox) * @as(u64, in_w - 1) * 256;
            const sx_denom: u64 = if (out_w > 1) @as(u64, out_w - 1) else 1;
            const sx_fixed: u64 = sx_numer / sx_denom;
            const sx_int: usize = @intCast(sx_fixed >> 8);
            const sx_frac: u32 = @intCast(sx_fixed & 0xFF);

            const x0: usize = sx_int;
            const x1: usize = if (sx_int + 1 < in_w) sx_int + 1 else sx_int;

            const off00 = x0 * channels;
            const off10 = x1 * channels;

            for (0..channels) |ch| {
                // Fetch 4 surrounding pixels
                const p00: u32 = row0[off00 + ch];
                const p10: u32 = row0[off10 + ch];
                const p01: u32 = row1[off00 + ch];
                const p11: u32 = row1[off10 + ch];

                // Bilinear interpolation in 8.8 fixed point
                // top = p00 * (256 - sx_frac) + p10 * sx_frac
                // bot = p01 * (256 - sx_frac) + p11 * sx_frac
                // result = top * (256 - sy_frac) + bot * sy_frac
                const inv_sx: u32 = 256 - sx_frac;
                const inv_sy: u32 = 256 - sy_frac;

                const top: u32 = p00 * inv_sx + p10 * sx_frac;
                const bot: u32 = p01 * inv_sx + p11 * sx_frac;
                const val: u32 = (top * inv_sy + bot * sy_frac + 32768) >> 16;

                out_row[ox * channels + ch] = @intCast(if (val > 255) 255 else val);
            }
        }
    }

    return output;
}
