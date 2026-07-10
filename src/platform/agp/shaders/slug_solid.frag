#version 450
// Ultra-minimal fragment shader: solid magenta to prove GPU draw works.
// Matches standard arcan vertex output (location 0 = vec2 texcoord).

layout(location = 0) in vec2 vTexcoord;
layout(location = 0) out vec4 fragColor;

void main() {
    // Checkerboard: magenta top half, cyan bottom half
    if (vTexcoord.y < 0.5)
        fragColor = vec4(1.0, 0.0, 1.0, 1.0);
    else
        fragColor = vec4(0.0, 1.0, 1.0, 1.0);
}
