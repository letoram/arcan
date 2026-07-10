// basic_2d.cl — OpenCL port of basic_2d.{vert,frag}.
// Textured 2D quad. Like color_2d.cl but the per-pixel color is sampled
// from a source texture instead of being a constant per-instance.
//
// Host responsibility: precompute the screen-space bbox + a (screen→UV)
// affine for each instance (avoids matrix-multiply per pixel inside the
// kernel). Layout chosen to match color_2d's per-instance shape so the
// loader's relocations follow the same pattern.

typedef struct {
    int   x0, y0, x1, y1;     // pixel bbox on fb (x1/y1 exclusive)
    float uv_ax, uv_bx, uv_cx; // screen (x,y) → src u = ax*x + bx*y + cx
    float uv_ay, uv_by, uv_cy; // screen (x,y) → src v = ay*x + by*y + cy
    int   src_width, src_height;
    float opacity;
} Basic2dInstance;

__kernel void basic_2d_compute(
    __global       uchar4 *fb,
    const int    fb_width,
    const int    fb_height,
    __global const uchar4 *src,           // packed source texture
    __global const Basic2dInstance *instances,
    const int    instance_count)
{
    const int i  = get_global_id(0);
    const int dx = get_global_id(1);
    const int dy = get_global_id(2);
    if (i >= instance_count) return;

    Basic2dInstance inst = instances[i];
    const int x = inst.x0 + dx;
    const int y = inst.y0 + dy;
    if (x >= inst.x1 || y >= inst.y1) return;
    if (x < 0 || x >= fb_width)  return;
    if (y < 0 || y >= fb_height) return;

    const float fx = (float)x, fy = (float)y;
    const float u  = inst.uv_ax * fx + inst.uv_bx * fy + inst.uv_cx;
    const float v  = inst.uv_ay * fx + inst.uv_by * fy + inst.uv_cy;
    const int su = clamp((int)floor(u * (float)inst.src_width),  0, inst.src_width  - 1);
    const int sv = clamp((int)floor(v * (float)inst.src_height), 0, inst.src_height - 1);
    const uchar4 srcpx = src[sv * inst.src_width + su];

    // Straight (non-premultiplied) over with opacity applied to alpha.
    const uchar4 fbpx = fb[y * fb_width + x];
    const float a  = ((float)srcpx.w / 255.0f) * inst.opacity;
    const float ia = 1.0f - a;
    fb[y * fb_width + x] = (uchar4)(
        (uchar)clamp((float)srcpx.x * a + (float)fbpx.x * ia, 0.0f, 255.0f),
        (uchar)clamp((float)srcpx.y * a + (float)fbpx.y * ia, 0.0f, 255.0f),
        (uchar)clamp((float)srcpx.z * a + (float)fbpx.z * ia, 0.0f, 255.0f),
        (uchar)clamp((float)srcpx.w * a + (float)fbpx.w * ia, 0.0f, 255.0f));
}
