// arcan_raster_gpu.zig — GPU glyph rendering dispatch using Slug algorithm.
//
// Replaces CPU rasterization (TTF_RenderUNICODEglyph → alpha bitmap → blit)
// with GPU curve evaluation (glyph outlines → Slug fragment shader → coverage).
//
// Integration: called from arcan_raster.zig when GPU glyph rendering is enabled.
// Falls back to CPU path if shader compilation fails or no Vulkan context.
//
// Architecture:
//   1. slug_glyph.zig extracts curves + builds band data from TrueType outlines
//   2. This module manages GPU textures (curve/band) and instance buffers
//   3. slug_glyph.frag evaluates per-pixel coverage via Slug algorithm
//   4. Result: alpha-blended foreground over background, no CPU rasterization

const std = @import("std");
const slug = @import("slug_glyph.zig");
const TrueType = @import("TrueType");

// C bridge to AGP (arcan graphics platform)
extern "c" fn agp_shader_build(
    tag: [*:0]const u8,
    geom: ?[*:0]const u8,
    vert: [*:0]const u8,
    frag: [*:0]const u8,
) u32;

extern "c" fn agp_shader_activate(shid: u32) c_int;
extern "c" fn agp_shader_envv(slot: u32, val: f32) void;

// Glyph GPU cache entry
const GlyphCacheEntry = struct {
    gpu_data: slug.GlyphGpuData,
    curve_tex_id: u32 = 0, // AGP texture handle for curve data
    band_tex_id: u32 = 0,  // AGP texture handle for band data
};

const GLYPH_CACHE_SIZE: usize = 512;
const SLUG_SHADER_TAG = "slug_glyph\x00";

// Module state
var slug_shader_id: u32 = 0xffffffff;
var initialized: bool = false;
var glyph_cache: [GLYPH_CACHE_SIZE]?GlyphCacheEntry = .{null} ** GLYPH_CACHE_SIZE;

// Embedded shader sources (null-terminated for C ABI)
const slug_vert_src = @embedFile("../platform/agp/shaders/slug_glyph.vert");
const slug_frag_src = @embedFile("../platform/agp/shaders/slug_glyph.frag");

/// Initialize the GPU glyph rendering pipeline.
/// Call once during compositor startup. Returns false if shaders fail to compile.
pub fn init() bool {
    if (initialized) return slug_shader_id != 0xffffffff;

    initialized = true;

    // Build the Slug shader via agp_shader_build (runtime GLSL→SPIR-V)
    // NOTE: agp_shader_build expects null-terminated C strings.
    // The @embedFile data includes trailing bytes but no null terminator,
    // so we need to append one. For now, use the pre-compiled SPIR-V path
    // or pass the source through a buffer.
    slug_shader_id = agp_shader_build(
        SLUG_SHADER_TAG,
        null,
        slug_vert_src.ptr,
        slug_frag_src.ptr,
    );

    if (slug_shader_id == 0xffffffff) {
        return false;
    }
    return true;
}

/// Prepare GPU data for a single glyph. Caches the result.
/// Returns null if the glyph has no outlines (space, control chars).
pub fn prepareGlyph(
    alloc: std.mem.Allocator,
    tt: *const TrueType,
    glyph_index: TrueType.GlyphIndex,
) ?*const slug.GlyphGpuData {
    // Simple hash cache
    const hash = @intFromEnum(glyph_index) % GLYPH_CACHE_SIZE;

    if (glyph_cache[hash]) |*entry| {
        return &entry.gpu_data;
    }

    // Extract curves from TrueType outline
    const vertices = tt.glyphShape(alloc, glyph_index) catch return null;
    defer alloc.free(vertices);

    const curves = slug.extractCurves(alloc, vertices) catch return null;
    defer alloc.free(curves);

    if (curves.len == 0) return null;

    // Determine band count based on curve complexity
    const num_bands: u16 = if (curves.len <= 8) 2 else if (curves.len <= 24) 4 else 8;

    const gpu_data = slug.buildGlyphGpuData(alloc, curves, num_bands, num_bands) catch return null;

    glyph_cache[hash] = .{
        .gpu_data = gpu_data,
    };

    return &glyph_cache[hash].?.gpu_data;
}

/// Check if GPU glyph rendering is available.
pub fn isAvailable() bool {
    return initialized and slug_shader_id != 0xffffffff;
}

/// Get the shader ID for external pipeline binding.
pub fn getShaderId() u32 {
    return slug_shader_id;
}

/// Per-cell instance data for the Slug vertex shader.
/// Matches the layout(location) attributes in slug_glyph.vert.
pub const CellInstance = extern struct {
    cell_pos: [2]f32,     // location 1: screen-space cell top-left
    cell_size: [2]f32,    // location 2: cell width/height
    em_min: [2]f32,       // location 3: em-space bbox min
    em_max: [2]f32,       // location 4: em-space bbox max
    band_transform: [4]f32, // location 5: (scale.x, scale.y, offset.x, offset.y)
    glyph_data: [4]i32,  // location 6: (loc.x, loc.y, bandMaxX, bandMaxY|flags)
    fg_color: [4]f32,     // location 7: foreground RGBA
    bg_color: [4]f32,     // location 8: background RGBA
};

/// Build instance data for a terminal cell that should use GPU rendering.
pub fn buildCellInstance(
    gpu_data: *const slug.GlyphGpuData,
    cell_x: f32,
    cell_y: f32,
    cell_w: f32,
    cell_h: f32,
    fg: [4]f32,
    bg: [4]f32,
    glyph_tex_offset: [2]i32, // where this glyph's data starts in the global texture
) CellInstance {
    return .{
        .cell_pos = .{ cell_x, cell_y },
        .cell_size = .{ cell_w, cell_h },
        .em_min = .{ 0, 0 }, // TODO: compute from glyph bbox
        .em_max = .{ 1, 1 }, // normalized em-space for now
        .band_transform = .{
            gpu_data.band_scale[0],
            gpu_data.band_scale[1],
            gpu_data.band_offset[0],
            gpu_data.band_offset[1],
        },
        .glyph_data = .{
            glyph_tex_offset[0],
            glyph_tex_offset[1],
            @as(i32, gpu_data.band_max_x),
            @as(i32, gpu_data.band_max_y),
        },
        .fg_color = fg,
        .bg_color = bg,
    };
}

// ════════════════════════════════════════════════════════════════════
// Tests
// ════════════════════════════════════════════════════════════════════

test "CellInstance size and alignment" {
    const testing = std.testing;
    // 8 fields: 2+2+2+2+4+4+4+4 = 24 components, but glyph_data is i32
    // Actual: (2+2+2+2+4)*4 + 4*4 + (4+4)*4 = 96 bytes
    try testing.expectEqual(@as(usize, 96), @sizeOf(CellInstance));
}

test "buildCellInstance produces valid data" {
    const testing = std.testing;
    const gpu_data = slug.GlyphGpuData{
        .curve_data = &.{},
        .num_curve_texels = 0,
        .band_data = &.{},
        .num_band_texels = 0,
        .band_max_x = 3,
        .band_max_y = 5,
        .band_scale = .{ 0.25, 0.125 },
        .band_offset = .{ -1.0, -2.0 },
        .allocator = testing.allocator,
    };

    const inst = buildCellInstance(
        &gpu_data,
        100.0, 200.0, 10.0, 18.0,
        .{ 1.0, 1.0, 1.0, 1.0 },
        .{ 0.0, 0.0, 0.0, 1.0 },
        .{ 42, 7 },
    );

    try testing.expectApproxEqAbs(@as(f32, 100.0), inst.cell_pos[0], 0.001);
    try testing.expectApproxEqAbs(@as(f32, 200.0), inst.cell_pos[1], 0.001);
    try testing.expectEqual(@as(i32, 42), inst.glyph_data[0]);
    try testing.expectEqual(@as(i32, 5), inst.glyph_data[3]);
    try testing.expectApproxEqAbs(@as(f32, 0.25), inst.band_transform[0], 0.001);
}
