// slug_solid.cl — OpenCL port of slug_solid.frag.
// Debug fill: top half magenta, bottom half cyan. Used to prove the
// rasterization+draw path before slug glyph rendering is wired in.
//
// Dispatch: global = (width, height), one work-item per output pixel.

__kernel void slug_solid_compute(
    __global       uchar4 *fb,
    const int    fb_width,
    const int    fb_height)
{
    const int x = get_global_id(0);
    const int y = get_global_id(1);
    if (x >= fb_width || y >= fb_height) return;

    // y < height/2 → magenta; else cyan.
    const uchar4 color = (y * 2 < fb_height)
        ? (uchar4)(255, 0, 255, 255)
        : (uchar4)(0, 255, 255, 255);
    fb[y * fb_width + x] = color;
}
