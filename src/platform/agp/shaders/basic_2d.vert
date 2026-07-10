#version 450

layout(push_constant) uniform PC {
    mat4 modelview;   // 0
    mat4 projection;  // 64
    mat4 texturem;    // 128
    float opacity;    // 192
    float trans_blend;
    float trans_move;
    float trans_rotate;
    float trans_scale;
    vec2 sz_input;
    vec2 sz_output;
    vec2 sz_storage;
    int rtgt_id;
    float fract_timestamp;
    int timestamp;    // 244
} pc;

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;
layout(location = 0) out vec2 texco;

void main() {
    gl_Position = pc.projection * pc.modelview * vec4(pos, 0.0, 1.0);
    texco = uv;
}
