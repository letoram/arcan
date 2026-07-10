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

layout(location = 0) out vec4 fragColor;

void main() {
    // obj_col stored in texturem[0][0..2] (reuse since COLOR_2D doesn't sample textures)
    vec3 obj_col = vec3(pc.texturem[0][0], pc.texturem[0][1], pc.texturem[0][2]);
    fragColor = vec4(obj_col, pc.opacity);
}
