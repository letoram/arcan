// slug_debug_frag.cl — OpenCL port of slug_debug_frag.frag.
// Fills each glyph cell with the instance's foreground color. Used to
// prove the per-glyph data pipeline before real Slug curve evaluation
// takes over (slug_glyph.cl).
//
// One work-item per (glyph_instance, dx, dy) → one fb pixel inside the
// glyph's bounding box. Layout mirrors color_2d.cl's per-instance dispatch.

typedef struct {
    int x0, y0, x1, y1;    // pixel bounding box on fb (x1/y1 exclusive)
    float fg_r, fg_g, fg_b, fg_a;
    float bg_r, bg_g, bg_b, bg_a;  // unused in debug fill
} SlugDebugInstance;

__kernel void slug_debug_compute(
    __global uchar4 *fb,
    const int fb_width,
    const int fb_height,
    __global const SlugDebugInstance *instances,
    const int instance_count,
    const float opacity)
{
    const int i  = get_global_id(0);
    const int dx = get_global_id(1);
    const int dy = get_global_id(2);
    if (i >= instance_count) return;

    SlugDebugInstance inst = instances[i];
    const int x = inst.x0 + dx;
    const int y = inst.y0 + dy;
    if (x >= inst.x1 || y >= inst.y1) return;
    if (x < 0 || x >= fb_width)  return;
    if (y < 0 || y >= fb_height) return;

    // Solid fg with opacity multiplied in (matches the .frag's color.a *= pc.opacity).
    const float a  = inst.fg_a * opacity;
    fb[y * fb_width + x] = (uchar4)(
        (uchar)clamp(inst.fg_r * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(inst.fg_g * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(inst.fg_b * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(a         * 255.0f, 0.0f, 255.0f));
}
