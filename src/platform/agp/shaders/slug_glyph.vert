#version 450
// Slug glyph vertex shader — instanced rendering.
// Binding 0: unit quad (pos + uv), per-vertex.
// Binding 1: per-instance cell data (GpuCellInstance, 96 bytes).
//
// Positions each glyph quad at the correct screen location by transforming
// the unit quad [-1,1] to the cell's pixel rectangle via push constants.

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
layout(location = 0) in vec2 pos;    // [-1,1] quad corners
layout(location = 1) in vec2 uv;     // [0,1] texture coordinates

// ── Per-instance (binding 1): cell data from GpuCellInstance ──
layout(location = 2) in vec2 cell_pos;        // screen pixel position (top-left)
layout(location = 3) in vec2 cell_size;       // cell width/height in pixels
layout(location = 4) in vec2 em_min;          // em-space bbox min
layout(location = 5) in vec2 em_max;          // em-space bbox max
layout(location = 6) in vec4 band_transform;  // (scale.x, scale.y, offset.x, offset.y)
layout(location = 7) in ivec4 glyph_data;     // (loc.x, loc.y, bandMaxX, bandMaxY)
layout(location = 8) in vec4 fg_color;        // foreground RGBA [0,1]
layout(location = 9) in vec4 bg_color;        // background RGBA [0,1]

// ── Outputs to fragment shader ──
layout(location = 0) out vec2 vTexcoord;
layout(location = 1) flat out vec4 vBandTransform;
layout(location = 2) flat out ivec4 vGlyphData;
layout(location = 3) flat out vec4 vFgColor;
layout(location = 4) flat out vec4 vBgColor;
layout(location = 5) flat out vec2 vCellPos;
layout(location = 6) flat out vec2 vCellSize;

void main() {
    // Y flip only: TrueType Y-up vs screen Y-down. X is NOT flipped here because
    // the composite pass to swapchain already mirrors X via texture coordinates.
    vTexcoord = mix(em_min, em_max, vec2(uv.x, 1.0 - uv.y));
    vBandTransform = band_transform;
    vGlyphData = glyph_data;
    vFgColor = fg_color;
    vBgColor = bg_color;
    vCellPos = cell_pos;
    vCellSize = cell_size;

    // Dynamic dilation: expand quad by ~0.5px to prevent edge clipping on thin strokes.
    // At small sizes the dilation is proportionally larger. Lengyel's Slug uses this.
    float size_min = min(cell_size.x, cell_size.y);
    float dilation = mix(0.6, 0.2, clamp((size_min - 10.0) / 40.0, 0.0, 1.0));
    vec2 dilated_uv = (uv - 0.5) * (1.0 + dilation / max(cell_size, vec2(1.0))) + 0.5;

    vec2 pixel_pos = cell_pos + dilated_uv * cell_size;
    vec2 ndc = (pixel_pos / pc.sz_output) * 2.0 - 1.0;
    gl_Position = vec4(ndc, 0.0, 1.0);
}
