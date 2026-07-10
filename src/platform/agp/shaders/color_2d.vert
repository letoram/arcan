#version 450

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

layout(location = 0) in vec2 pos;
layout(location = 1) in vec2 uv;

void main() {
    gl_Position = pc.projection * pc.modelview * vec4(pos, 0.0, 1.0);
}
