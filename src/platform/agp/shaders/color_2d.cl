// color_2d.cl — OpenCL port of color_2d.{vert,frag} from durian's
// Vulkan compositor. Renders N filled quads with per-instance color +
// opacity via src-over blending. Each quad's screen-space bounding box
// is given in pixel coordinates post-projection (the host computes the
// box on the CPU side from the original modelview/projection matrices
// — this kernel doesn't reproduce the per-vertex matrix math because
// the result is identical to "rasterize the axis-aligned bbox").
//
// SPV entry: color_2d_compute
//
// Layout assumption: framebuffer is uchar4 RGBA8, row-major.
// global_size = (instance_count, max_bbox_w, max_bbox_h) for now —
// each (instance, dx, dy) work-item writes one fb pixel after early-
// outing if dx/dy is past its instance's bbox. Wasteful but trivial;
// optimize to per-instance dispatch ranges once the smoke proves it.

typedef struct {
    int x0, y0, x1, y1;  // pixel bounding box on fb (x1/y1 exclusive)
    float r, g, b, a;     // src color, a = opacity
} Color2dInstance;

__kernel void color_2d_compute(
    __global uchar4 *fb,
    const int fb_width,
    const int fb_height,
    __global const Color2dInstance *instances,
    const int instance_count
) {
    const int i  = get_global_id(0);
    const int dx = get_global_id(1);
    const int dy = get_global_id(2);

    if (i >= instance_count) return;

    Color2dInstance inst = instances[i];
    const int x = inst.x0 + dx;
    const int y = inst.y0 + dy;

    if (x >= inst.x1 || y >= inst.y1) return;
    if (x < 0 || x >= fb_width)  return;
    if (y < 0 || y >= fb_height) return;

    const int p = y * fb_width + x;
    const uchar4 fbpx = fb[p];

    // src-over blend, straight (non-premultiplied) src color.
    const float fr = (float)fbpx.x * (1.0f/255.0f);
    const float fg = (float)fbpx.y * (1.0f/255.0f);
    const float fb_ = (float)fbpx.z * (1.0f/255.0f);
    const float fa = (float)fbpx.w * (1.0f/255.0f);

    const float a  = inst.a;
    const float ia = 1.0f - a;

    const float or_ = inst.r * a + fr  * ia;
    const float og  = inst.g * a + fg  * ia;
    const float ob  = inst.b * a + fb_ * ia;
    const float oa  = a       + fa  * ia;

    fb[p] = (uchar4)(
        (uchar)(clamp(or_, 0.0f, 1.0f) * 255.0f),
        (uchar)(clamp(og,  0.0f, 1.0f) * 255.0f),
        (uchar)(clamp(ob,  0.0f, 1.0f) * 255.0f),
        (uchar)(clamp(oa,  0.0f, 1.0f) * 255.0f)
    );
}
