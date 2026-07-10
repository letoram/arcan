#version 450
// SDF Accumulation vertex shader.
// Positions each glyph quad at its SDF atlas region (not screen position).
// Uses same per-instance data as slug_glyph.vert.

layout(push_constant) uniform PC {
    mat4 modelview;
    mat4 projection;
    mat4 texturem;
    float opacity;
    float trans_blend;
    float trans_move;
    float trans_rotate;
    float trans_scale;
    vec2 sz_input;
    vec2 sz_output;
    vec2 sz_storage;
    int rtgt_id;
    float fract_timestamp;
    int timestamp;
} pc;

// ── Per-vertex (binding 0): unit quad ──
layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;

// ── Per-instance (binding 1): cell data from GpuCellInstance ──
layout(location = 2) in vec2 cell_pos;
layout(location = 3) in vec2 cell_size;
layout(location = 4) in vec2 em_min;
layout(location = 5) in vec2 em_max;
layout(location = 6) in vec4 band_transform;
layout(location = 7) in ivec4 glyph_data;
layout(location = 8) in vec4 fg_color;
layout(location = 9) in vec4 bg_color;

// ── Outputs to fragment shader ──
layout(location = 0) out vec2 vTexcoord;
layout(location = 1) flat out vec4 vBandTransform;
layout(location = 2) flat out ivec4 vGlyphData;
layout(location = 3) flat out vec4 vFgColor;
layout(location = 4) flat out vec4 vBgColor;

void main() {
    // Y flip: TrueType Y-up vs screen Y-down
    vTexcoord = mix(em_min, em_max, vec2(uv.x, 1.0 - uv.y));
    vBandTransform = band_transform;
    vGlyphData = glyph_data;
    vFgColor = fg_color;
    vBgColor = bg_color;

    // Extract SDF atlas region from packed glyph_data
    int sdf_x = (glyph_data.z >> 8) & 0xFFF;
    int sdf_y = (glyph_data.w >> 12) & 0xFFF;

    // Position quad at SDF atlas region (not screen position)
    vec2 atlas_pos = vec2(float(sdf_x), float(sdf_y));
    vec2 pixel_pos = atlas_pos + uv * cell_size;
    // NDC for SDF atlas (sz_output set to atlas dimensions)
    vec2 ndc = (pixel_pos / pc.sz_output) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
}
