// slug_glyph.zig — GPU glyph data preparation for Slug-style rendering.
//
// Converts TrueType glyph outlines (from TrueType.glyphShape) into the
// band/curve texture data needed by the Slug pixel shader.
//
// The Slug algorithm (Eric Lengyel, JCGT 2017) renders quadratic Bézier
// curves directly on the GPU: no CPU rasterization, no bitmap cache, no
// hinting. Each pixel evaluates winding number from curve data stored in
// GPU textures.
//
// Data structures:
//   Curve texture — RGBA float16: (x1,y1,x2,y2) per texel, p3 in next texel
//   Band texture  — RGBA uint16: (curve_count, list_offset) per band entry
//
// Band layout per glyph:
//   [horizontal bands (bandMaxY+1)] [vertical bands (bandMaxX+1)] [curve lists]

const std = @import("std");
const Allocator = std.mem.Allocator;
const TrueType = @import("TrueType");

const BAND_TEX_WIDTH: u32 = 4096;

/// A quadratic Bézier curve: C(t) = (1-t)²p1 + 2t(1-t)p2 + t²p3
pub const QuadCurve = struct {
    p1: [2]f32,
    p2: [2]f32,
    p3: [2]f32,

    pub fn maxX(self: QuadCurve) f32 {
        return @max(self.p1[0], @max(self.p2[0], self.p3[0]));
    }
    pub fn maxY(self: QuadCurve) f32 {
        return @max(self.p1[1], @max(self.p2[1], self.p3[1]));
    }
    pub fn minX(self: QuadCurve) f32 {
        return @min(self.p1[0], @min(self.p2[0], self.p3[0]));
    }
    pub fn minY(self: QuadCurve) f32 {
        return @min(self.p1[1], @min(self.p2[1], self.p3[1]));
    }

    /// Does this curve span the given horizontal band [ylo, yhi]?
    /// Uses <= on both sides so curves at exact band boundaries are included
    /// in BOTH adjacent bands. Without this, diagonal strokes produce horizontal
    /// stripe artifacts at band transitions.
    fn crossesHBand(self: QuadCurve, ylo: f32, yhi: f32) bool {
        return self.minY() <= yhi and self.maxY() >= ylo;
    }
    /// Does this curve span the given vertical band [xlo, xhi]?
    fn crossesVBand(self: QuadCurve, xlo: f32, xhi: f32) bool {
        return self.minX() <= xhi and self.maxX() >= xlo;
    }
};

/// Packed glyph data ready for GPU upload.
pub const GlyphGpuData = struct {
    /// Curve control points: each curve is 2 texels.
    /// Texel 0: (x1, y1, x2, y2) in em-space
    /// Texel 1: (x3, y3, 0, 0)
    /// Consecutive curves share texels (p3 of curve N = p1 of curve N+1 if same contour).
    /// For rectangles (is_rect=true): texel 0 = (min_x, min_y, max_x, max_y).
    curve_data: []f32, // packed RGBA f32, length = num_texels * 4
    num_curve_texels: u32,

    /// Band index data: uint16 entries.
    /// Layout: [hband_0..hband_N] [vband_0..vband_M] [curve_lists...]
    /// Each band entry: (curve_count, list_offset)
    /// Each curve list entry: (curve_texel_x, curve_texel_y)
    band_data: []u16, // packed, length = num_band_entries * 4 (RGBA u16 per texel)
    num_band_texels: u32,

    band_max_x: u16,
    band_max_y: u16,
    band_scale: [2]f32,
    band_offset: [2]f32,

    /// True if glyph is an axis-aligned rectangle (underscore, pipe, box-drawing).
    /// Shader uses box SDF instead of Slug winding when this is set.
    is_rect: bool,

    allocator: Allocator,

    pub fn deinit(self: *GlyphGpuData) void {
        self.allocator.free(self.curve_data);
        self.allocator.free(self.band_data);
    }
};

/// Extract quadratic Bézier curves from TrueType glyph shape vertices.
/// Lines are promoted to degenerate quadratics (control point = midpoint).
pub fn extractCurves(alloc: Allocator, vertices: []const TrueType.Vertex) ![]QuadCurve {
    var curves = std.ArrayListUnmanaged(QuadCurve){};
    errdefer curves.deinit(alloc);

    var last_x: f32 = 0;
    var last_y: f32 = 0;

    for (vertices) |v| {
        switch (v.type) {
            .vmove => {
                last_x = @floatFromInt(v.x);
                last_y = @floatFromInt(v.y);
            },
            .vline => {
                const x: f32 = @floatFromInt(v.x);
                const y: f32 = @floatFromInt(v.y);
                // Promote line to degenerate quadratic: control = midpoint
                try curves.append(alloc, .{
                    .p1 = .{ last_x, last_y },
                    .p2 = .{ (last_x + x) * 0.5, (last_y + y) * 0.5 },
                    .p3 = .{ x, y },
                });
                last_x = x;
                last_y = y;
            },
            .vcurve => {
                const x: f32 = @floatFromInt(v.x);
                const y: f32 = @floatFromInt(v.y);
                const cx: f32 = @floatFromInt(v.cx);
                const cy: f32 = @floatFromInt(v.cy);
                try curves.append(alloc, .{
                    .p1 = .{ last_x, last_y },
                    .p2 = .{ cx, cy },
                    .p3 = .{ x, y },
                });
                last_x = x;
                last_y = y;
            },
            .vcubic => {
                // Split cubic into 2 quadratics using 3/4-point method.
                // Better curvature approximation than de Casteljau at t=0.5
                // (osor.io "Rendering Crispy Text On The GPU", 2025).
                const x: f32 = @floatFromInt(v.x);
                const y: f32 = @floatFromInt(v.y);
                const cx0: f32 = @floatFromInt(v.cx);
                const cy0: f32 = @floatFromInt(v.cy);
                const cx1: f32 = @floatFromInt(v.cx1);
                const cy1: f32 = @floatFromInt(v.cy1);

                // 3/4-point: control points 75% toward original cubic controls
                const c0x = last_x + (cx0 - last_x) * 0.75;
                const c0y = last_y + (cy0 - last_y) * 0.75;
                const c1x = x + (cx1 - x) * 0.75;
                const c1y = y + (cy1 - y) * 0.75;
                const mx = (c0x + c1x) * 0.5;
                const my = (c0y + c1y) * 0.5;

                try curves.append(alloc, .{
                    .p1 = .{ last_x, last_y },
                    .p2 = .{ c0x, c0y },
                    .p3 = .{ mx, my },
                });
                try curves.append(alloc, .{
                    .p1 = .{ mx, my },
                    .p2 = .{ c1x, c1y },
                    .p3 = .{ x, y },
                });
                last_x = x;
                last_y = y;
            },
            else => {},
        }
    }

    return curves.toOwnedSlice(alloc);
}

/// Build GPU-ready band and curve data for a glyph.
///
/// num_hbands / num_vbands: how many bands to divide the glyph bounding box into.
/// Typically 4-8 bands per axis for small glyphs, more for complex ones.
pub fn buildGlyphGpuData(
    alloc: Allocator,
    curves: []const QuadCurve,
    num_hbands: u16,
    num_vbands: u16,
) !GlyphGpuData {
    if (curves.len == 0) {
        return .{
            .curve_data = &.{},
            .num_curve_texels = 0,
            .band_data = &.{},
            .num_band_texels = 0,
            .band_max_x = 0,
            .band_max_y = 0,
            .band_scale = .{ 0, 0 },
            .band_offset = .{ 0, 0 },
            .is_rect = false,
            .allocator = alloc,
        };
    }

    // Compute bounding box
    var bbox_min_x: f32 = std.math.inf(f32);
    var bbox_min_y: f32 = std.math.inf(f32);
    var bbox_max_x: f32 = -std.math.inf(f32);
    var bbox_max_y: f32 = -std.math.inf(f32);
    for (curves) |c| {
        bbox_min_x = @min(bbox_min_x, c.minX());
        bbox_min_y = @min(bbox_min_y, c.minY());
        bbox_max_x = @max(bbox_max_x, c.maxX());
        bbox_max_y = @max(bbox_max_y, c.maxY());
    }

    const glyph_w = bbox_max_x - bbox_min_x;
    const glyph_h = bbox_max_y - bbox_min_y;
    if (glyph_w <= 0 or glyph_h <= 0) {
        return .{
            .curve_data = &.{},
            .num_curve_texels = 0,
            .band_data = &.{},
            .num_band_texels = 0,
            .band_max_x = 0,
            .band_max_y = 0,
            .band_scale = .{ 0, 0 },
            .band_offset = .{ 0, 0 },
            .is_rect = false,
            .allocator = alloc,
        };
    }

    // Rectangle detection
    // If glyph is exactly 4 degenerate quadratics forming an axis-aligned
    // rectangle, use a box SDF fast-path in the shader instead of Slug.
    // Targets: underscore, pipe, box-drawing chars, dashes.
    const is_rect = detectAxisAlignedRect(curves);

    const hband_height = glyph_h / @as(f32, @floatFromInt(num_hbands));
    const vband_width = glyph_w / @as(f32, @floatFromInt(num_vbands));

    // Pack curve data
    if (is_rect) {
        // Rectangle fast-path: store bounds in a single texel.
        // Texel 0: (min_x, min_y, max_x, max_y)
        const curve_data = try alloc.alloc(f32, 4);
        errdefer alloc.free(curve_data);
        curve_data[0] = bbox_min_x;
        curve_data[1] = bbox_min_y;
        curve_data[2] = bbox_max_x;
        curve_data[3] = bbox_max_y;

        // Rect needs no bands — shader bypasses band lookup entirely.
        const band_data = try alloc.alloc(u16, 4);
        errdefer alloc.free(band_data);
        @memset(band_data, 0);

        return .{
            .curve_data = curve_data,
            .num_curve_texels = 1,
            .band_data = band_data,
            .num_band_texels = 1,
            .band_max_x = 0,
            .band_max_y = 0,
            .band_scale = .{ 0, 0 },
            .band_offset = .{ 0, 0 },
            .is_rect = true,
            .allocator = alloc,
        };
    }

    // Normal Slug path: 2 texels per curve.
    // Texel 0: (p1.x, p1.y, p2.x, p2.y)
    // Texel 1: (p3.x, p3.y, 0, 0)
    const num_curve_texels: u32 = @intCast(curves.len * 2);
    const curve_data = try alloc.alloc(f32, num_curve_texels * 4);
    errdefer alloc.free(curve_data);

    for (curves, 0..) |c, i| {
        const t0 = i * 2;
        curve_data[t0 * 4 + 0] = c.p1[0];
        curve_data[t0 * 4 + 1] = c.p1[1];
        curve_data[t0 * 4 + 2] = c.p2[0];
        curve_data[t0 * 4 + 3] = c.p2[1];
        curve_data[(t0 + 1) * 4 + 0] = c.p3[0];
        curve_data[(t0 + 1) * 4 + 1] = c.p3[1];
        curve_data[(t0 + 1) * 4 + 2] = 0;
        curve_data[(t0 + 1) * 4 + 3] = 0;
    }

    // Build band lists
    // For each band, collect indices of curves that overlap it
    const total_bands = @as(u32, num_hbands) + @as(u32, num_vbands);
    var band_lists = try alloc.alloc(std.ArrayListUnmanaged(u32), total_bands);
    defer {
        for (band_lists) |*bl| bl.deinit(alloc);
        alloc.free(band_lists);
    }
    for (band_lists) |*bl| bl.* = .{};

    // Horizontal bands
    for (0..num_hbands) |bi| {
        const ylo = bbox_min_y + @as(f32, @floatFromInt(bi)) * hband_height;
        const yhi = ylo + hband_height;
        for (curves, 0..) |c, ci| {
            if (c.crossesHBand(ylo, yhi)) {
                try band_lists[bi].append(alloc, @intCast(ci));
            }
        }
        // Sort by descending max x for early-exit optimization
        const SortCtxH = struct {
            curves: []const QuadCurve,
            pub fn lessThan(ctx: @This(), a: u32, b: u32) bool {
                return ctx.curves[a].maxX() > ctx.curves[b].maxX();
            }
        };
        std.mem.sort(u32, band_lists[bi].items, SortCtxH{ .curves = curves }, SortCtxH.lessThan);
    }

    // Vertical bands
    for (0..num_vbands) |bi| {
        const xlo = bbox_min_x + @as(f32, @floatFromInt(bi)) * vband_width;
        const xhi = xlo + vband_width;
        for (curves, 0..) |c, ci| {
            if (c.crossesVBand(xlo, xhi)) {
                try band_lists[num_hbands + bi].append(alloc, @intCast(ci));
            }
        }
        // Sort by descending max y
        const SortCtxV = struct {
            curves: []const QuadCurve,
            pub fn lessThan(ctx: @This(), a: u32, b: u32) bool {
                return ctx.curves[a].maxY() > ctx.curves[b].maxY();
            }
        };
        std.mem.sort(u32, band_lists[num_hbands + bi].items, SortCtxV{ .curves = curves }, SortCtxV.lessThan);
    }

    // Pack band texture
    // Layout: [hband headers (num_hbands)] [vband headers (num_vbands)] [curve lists]
    // Each header texel: (curve_count, list_offset, 0, 0) in u16
    // Each curve list entry texel: (curve_texel_x, curve_texel_y, 0, 0) in u16

    // Count total curve list entries
    var total_list_entries: u32 = 0;
    for (band_lists) |bl| total_list_entries += @intCast(bl.items.len);

    const num_band_texels = total_bands + total_list_entries;
    const band_data = try alloc.alloc(u16, num_band_texels * 4);
    errdefer alloc.free(band_data);
    @memset(band_data, 0);

    var list_offset: u32 = total_bands; // lists start after all headers
    for (band_lists, 0..) |bl, bi| {
        // Header: (curve_count, list_offset_relative_to_glyph_loc)
        band_data[bi * 4 + 0] = @intCast(bl.items.len);
        band_data[bi * 4 + 1] = @intCast(list_offset);
        band_data[bi * 4 + 2] = 0;
        band_data[bi * 4 + 3] = 0;

        // Curve list entries
        for (bl.items, 0..) |curve_idx, li| {
            const texel_idx = curve_idx * 2; // 2 texels per curve
            const entry_pos = (list_offset + @as(u32, @intCast(li))) * 4;
            band_data[entry_pos + 0] = @intCast(texel_idx % BAND_TEX_WIDTH);
            band_data[entry_pos + 1] = @intCast(texel_idx / BAND_TEX_WIDTH);
            band_data[entry_pos + 2] = 0;
            band_data[entry_pos + 3] = 0;
        }

        list_offset += @intCast(bl.items.len);
    }

    // Band transform: maps em-space coordinate to band index
    // bandIndex = clamp(renderCoord * bandScale + bandOffset, 0, bandMax)
    const band_scale_x = @as(f32, @floatFromInt(num_vbands)) / glyph_w;
    const band_scale_y = @as(f32, @floatFromInt(num_hbands)) / glyph_h;
    const band_offset_x = -bbox_min_x * band_scale_x;
    const band_offset_y = -bbox_min_y * band_scale_y;

    return .{
        .curve_data = curve_data,
        .num_curve_texels = num_curve_texels,
        .band_data = band_data,
        .num_band_texels = num_band_texels,
        .band_max_x = num_vbands - 1,
        .band_max_y = num_hbands - 1,
        .band_scale = .{ band_scale_x, band_scale_y },
        .band_offset = .{ band_offset_x, band_offset_y },
        .is_rect = false,
        .allocator = alloc,
    };
}

/// Detect if curves form a single axis-aligned rectangle.
/// Returns true for exactly 4 degenerate quadratics (lines) that are all
/// horizontal or vertical, forming a closed rectangle.
fn detectAxisAlignedRect(curves: []const QuadCurve) bool {
    if (curves.len != 4) return false;

    const eps = 0.5; // tolerance for axis alignment

    var num_horiz: u32 = 0;
    var num_vert: u32 = 0;

    for (curves) |c| {
        // Check degenerate (p2 ≈ midpoint of p1,p3)
        const mid_x = (c.p1[0] + c.p3[0]) * 0.5;
        const mid_y = (c.p1[1] + c.p3[1]) * 0.5;
        if (@abs(c.p2[0] - mid_x) > eps or @abs(c.p2[1] - mid_y) > eps) return false;

        // Check axis-aligned
        const dx = @abs(c.p3[0] - c.p1[0]);
        const dy = @abs(c.p3[1] - c.p1[1]);

        if (dy < eps and dx > eps) {
            num_horiz += 1; // horizontal line
        } else if (dx < eps and dy > eps) {
            num_vert += 1; // vertical line
        } else {
            return false; // diagonal or degenerate
        }
    }

    return num_horiz == 2 and num_vert == 2;
}

// ════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════

test "extractCurves: simple triangle (3 lines)" {
    const testing = std.testing;
    const vertices = [_]TrueType.Vertex{
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vmove },
        .{ .x = 100, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
        .{ .x = 50, .y = 100, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
    };

    const curves = try extractCurves(testing.allocator, &vertices);
    defer testing.allocator.free(curves);

    try testing.expectEqual(@as(usize, 3), curves.len);
    // First curve: (0,0) → (100,0), control at midpoint (50,0)
    try testing.expectApproxEqAbs(@as(f32, 0), curves[0].p1[0], 0.01);
    try testing.expectApproxEqAbs(@as(f32, 0), curves[0].p1[1], 0.01);
    try testing.expectApproxEqAbs(@as(f32, 100), curves[0].p3[0], 0.01);
}

test "extractCurves: quadratic curve" {
    const testing = std.testing;
    const vertices = [_]TrueType.Vertex{
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vmove },
        .{ .x = 100, .y = 0, .cx = 50, .cy = 80, .cx1 = 0, .cy1 = 0, .type = .vcurve },
    };

    const curves = try extractCurves(testing.allocator, &vertices);
    defer testing.allocator.free(curves);

    try testing.expectEqual(@as(usize, 1), curves.len);
    // Control point should be (50, 80)
    try testing.expectApproxEqAbs(@as(f32, 50), curves[0].p2[0], 0.01);
    try testing.expectApproxEqAbs(@as(f32, 80), curves[0].p2[1], 0.01);
}

test "buildGlyphGpuData: simple box produces 4 curves, 2+2 bands" {
    const testing = std.testing;
    // A box: 4 lines = 4 degenerate quadratics
    const vertices = [_]TrueType.Vertex{
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vmove },
        .{ .x = 100, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
        .{ .x = 100, .y = 100, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
        .{ .x = 0, .y = 100, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
        .{ .x = 0, .y = 0, .cx = 0, .cy = 0, .cx1 = 0, .cy1 = 0, .type = .vline },
    };

    const curves = try extractCurves(testing.allocator, &vertices);
    defer testing.allocator.free(curves);
    try testing.expectEqual(@as(usize, 4), curves.len);

    var gpu = try buildGlyphGpuData(testing.allocator, curves, 2, 2);
    defer gpu.deinit();

    try testing.expectEqual(@as(u16, 1), gpu.band_max_x); // 2 vbands → max index 1
    try testing.expectEqual(@as(u16, 1), gpu.band_max_y); // 2 hbands → max index 1
    try testing.expect(gpu.num_curve_texels == 8); // 4 curves * 2 texels each
    try testing.expect(gpu.num_band_texels > 0);
    try testing.expect(gpu.band_scale[0] > 0);
    try testing.expect(gpu.band_scale[1] > 0);
}

test "buildGlyphGpuData: empty glyph" {
    const testing = std.testing;
    var gpu = try buildGlyphGpuData(testing.allocator, &.{}, 4, 4);
    defer gpu.deinit();
    try testing.expectEqual(@as(u32, 0), gpu.num_curve_texels);
    try testing.expectEqual(@as(u32, 0), gpu.num_band_texels);
}
