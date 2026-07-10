#version 450

layout(set = 0, binding = 0) uniform sampler2D map_diffuse;

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

layout(location = 0) in vec2 texco;
layout(location = 0) out vec4 fragColor;

void main() {
    vec4 col = texture(map_diffuse, texco);
    col.a *= pc.opacity;
    fragColor = col;
}
