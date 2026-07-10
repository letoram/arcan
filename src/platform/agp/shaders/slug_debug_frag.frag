#version 450
// Debug fragment shader — uses fg/bg colors from instance data.
// Instead of evaluating Slug curves, renders foreground color as a solid
// rectangle (100% coverage). This proves the data pipeline works.
// When replaced with slug_glyph.frag, real curve evaluation takes over.

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

// Dummy texture bindings to satisfy descriptor set layout (binding 0 + 2 = combined_image_sampler)
layout(set = 0, binding = 0) uniform sampler2D curveTexture;

// Inputs from vertex shader (must match slug_glyph.vert outputs)
layout(location = 0) in vec2 vTexcoord;
layout(location = 1) flat in vec4 vBandTransform;
layout(location = 2) flat in ivec4 vGlyphData;
layout(location = 3) flat in vec4 vFgColor;
layout(location = 4) flat in vec4 vBgColor;

layout(location = 0) out vec4 fragColor;

void main() {
    // Simple debug: fill entire cell with foreground color.
    // This makes every glyph cell a solid fg-colored rectangle.
    vec4 color = vFgColor;
    color.a *= pc.opacity;
    fragColor = color;
}
