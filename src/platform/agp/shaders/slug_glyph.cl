// slug_glyph.cl — OpenCL port of slug_glyph.{vert,frag}.
// Eric Lengyel's Slug algorithm (JCGT 2017): per-pixel quadratic-Bézier
// coverage via dual horizontal/vertical ray winding. No bitmap cache,
// no hinting. MIT-or-Apache-2.0 (upstream); port copyright Anthropic.
//
// Differences from the .frag:
//   • No fwidth(): host supplies `pixels_per_em` per instance (computed
//     from the quad's screen-space transform and em-square size).
//   • Textures replaced by __global buffers:
//       curve_tex:  float4 array indexed as (col, row) with stride = curve_tex_w.
//                   Each curve takes 2 entries: tex[base]   = (x1,y1,x2,y2),
//                                               tex[base+1] = (x3,y3,_,_).
//       band_tex:   uint2 array indexed as (col, row) with stride = 1<<12.
//                   Encodes per-band curve-count + list-offset, plus the
//                   curve-location list itself.
//   • flat-in vertex interpolants become fields of a per-instance struct.

#define kLogBandTextureWidth 12
#define kBandTextureWidth    (1 << kLogBandTextureWidth)

typedef struct {
    int   x0, y0, x1, y1;        // pixel bbox on fb (x1/y1 exclusive)
    float u0, v0, u1, v1;        // em-space coords at the 4 bbox corners
    float band_tx_ax, band_tx_ay; // bandTransform xy
    float band_tx_bx, band_tx_by; // bandTransform zw (offsets)
    int   glyph_x, glyph_y;       // glyphData.xy — band-table base in band_tex
    int   glyph_z, glyph_w;       // glyphData.zw — band-extents + flags
    float fg_r, fg_g, fg_b, fg_a;
    float bg_r, bg_g, bg_b, bg_a;
    float pixels_per_em_x, pixels_per_em_y;
    int   cell_x, cell_y;         // for decoration flags (underline/border/...)
    int   cell_w, cell_h;
} SlugGlyphInstance;

// Match the .frag's CalcRootCode: produce a 9-bit mask from sign pattern.
static inline uint calcRootCode(float y1, float y2, float y3) {
    uint i1 = as_uint(y1) >> 31u;
    uint i2 = as_uint(y2) >> 30u;
    uint i3 = as_uint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

static inline float2 solveHorizPoly(float4 p12, float2 p3) {
    float2 a  = p12.xy - p12.zw * 2.0f + p3;
    float2 b  = p12.xy - p12.zw;
    float  ra = 1.0f / a.y;
    float  rb = 0.5f / b.y;
    float  d  = sqrt(fmax(b.y * b.y - a.y * p12.y, 0.0f));
    float  t1 = (b.y - d) * ra;
    float  t2 = (b.y + d) * ra;
    if (fabs(a.y) < 1.0f / 1024.0f) { t1 = p12.y * rb; t2 = t1; }
    return (float2)(
        (a.x * t1 - b.x * 2.0f) * t1 + p12.x,
        (a.x * t2 - b.x * 2.0f) * t2 + p12.x);
}

static inline float2 solveVertPoly(float4 p12, float2 p3) {
    float2 a  = p12.xy - p12.zw * 2.0f + p3;
    float2 b  = p12.xy - p12.zw;
    float  ra = 1.0f / a.x;
    float  rb = 0.5f / b.x;
    float  d  = sqrt(fmax(b.x * b.x - a.x * p12.x, 0.0f));
    float  t1 = (b.x - d) * ra;
    float  t2 = (b.x + d) * ra;
    if (fabs(a.x) < 1.0f / 1024.0f) { t1 = p12.x * rb; t2 = t1; }
    return (float2)(
        (a.y * t1 - b.y * 2.0f) * t1 + p12.y,
        (a.y * t2 - b.y * 2.0f) * t2 + p12.y);
}

static inline int2 calcBandLoc(int gx, int gy, uint offset) {
    int bx = gx + (int)offset;
    int by = gy + (bx >> kLogBandTextureWidth);
    bx &= (kBandTextureWidth - 1);
    return (int2)(bx, by);
}

static inline float calcCoverage(float xcov, float ycov, float xwgt, float ywgt) {
    float coverage = fmax(
        fabs(xcov * xwgt + ycov * ywgt) / fmax(xwgt + ywgt, 1.0f / 65536.0f),
        fmin(fabs(xcov), fabs(ycov)));
    return clamp(coverage, 0.0f, 1.0f);
}

// Evaluate Slug coverage at em-space `coord` for the glyph described
// by `band_xform` + `glyph_data` (matches the .frag's SlugRender).
static float slugRender(
    float2 coord,
    float4 band_xform,
    int4 glyph_data,
    __global const float4 *curve_tex, int curve_tex_w,
    __global const uint2  *band_tex,
    float2 pixels_per_em)
{
    // Rectangle fast-path (flag bit 8 of glyph_data.w).
    if ((glyph_data.w & 0x100) != 0) {
        float4 bounds = band_xform;
        const float ramp = 0.5f;
        float dL = (coord.x - bounds.x) * pixels_per_em.x;
        float dR = (bounds.z - coord.x) * pixels_per_em.x;
        float dB = (coord.y - bounds.y) * pixels_per_em.y;
        float dT = (bounds.w - coord.y) * pixels_per_em.y;
        return clamp(dL + ramp, 0.0f, 1.0f)
             * clamp(dR + ramp, 0.0f, 1.0f)
             * clamp(dB + ramp, 0.0f, 1.0f)
             * clamp(dT + ramp, 0.0f, 1.0f);
    }

    int2 band_max = (int2)(glyph_data.z & 0xff, glyph_data.w & 0xff);
    int2 band_idx = clamp(
        (int2)((int)floor(coord.x * band_xform.x + band_xform.z),
               (int)floor(coord.y * band_xform.y + band_xform.w)),
        (int2)(0, 0), band_max);
    int gx = glyph_data.x, gy = glyph_data.y;

    // Horizontal ray.
    float xcov = 0.0f, xwgt = 0.0f;
    uint2 hb = band_tex[gy * kBandTextureWidth + (gx + band_idx.y)];
    int2  hl = calcBandLoc(gx, gy, hb.y);
    for (int i = 0; i < (int)hb.x; ++i) {
        uint2 cl_u = band_tex[hl.y * kBandTextureWidth + (hl.x + i)];
        int2  cl   = (int2)((int)cl_u.x, (int)cl_u.y);
        int   base = cl.y * curve_tex_w + cl.x;
        float4 p12 = curve_tex[base]     - (float4)(coord.x, coord.y, coord.x, coord.y);
        float2 p3  = curve_tex[base + 1].xy - coord;
        if (fmax(fmax(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5f) break;
        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            float2 r = solveHorizPoly(p12, p3) * pixels_per_em.x;
            float ramp = 0.5f;
            if ((code & 1u) != 0u) {
                xcov += clamp(r.x + ramp, 0.0f, 1.0f);
                xwgt = fmax(xwgt, clamp(1.0f - fabs(r.x) / ramp, 0.0f, 1.0f));
            }
            if (code > 1u) {
                xcov -= clamp(r.y + ramp, 0.0f, 1.0f);
                xwgt = fmax(xwgt, clamp(1.0f - fabs(r.y) / ramp, 0.0f, 1.0f));
            }
        }
    }

    // Vertical ray.
    float ycov = 0.0f, ywgt = 0.0f;
    uint2 vb = band_tex[gy * kBandTextureWidth + (gx + band_max.y + 1 + band_idx.x)];
    int2  vl = calcBandLoc(gx, gy, vb.y);
    for (int i = 0; i < (int)vb.x; ++i) {
        uint2 cl_u = band_tex[vl.y * kBandTextureWidth + (vl.x + i)];
        int2  cl   = (int2)((int)cl_u.x, (int)cl_u.y);
        int   base = cl.y * curve_tex_w + cl.x;
        float4 p12 = curve_tex[base]     - (float4)(coord.x, coord.y, coord.x, coord.y);
        float2 p3  = curve_tex[base + 1].xy - coord;
        if (fmax(fmax(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5f) break;
        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            float2 r = solveVertPoly(p12, p3) * pixels_per_em.y;
            float ramp = 0.5f;
            if ((code & 1u) != 0u) {
                ycov -= clamp(r.x + ramp, 0.0f, 1.0f);
                ywgt = fmax(ywgt, clamp(1.0f - fabs(r.x) / ramp, 0.0f, 1.0f));
            }
            if (code > 1u) {
                ycov += clamp(r.y + ramp, 0.0f, 1.0f);
                ywgt = fmax(ywgt, clamp(1.0f - fabs(r.y) / ramp, 0.0f, 1.0f));
            }
        }
    }

    return calcCoverage(xcov, ycov, xwgt, ywgt);
}

// 4-sample R2 jittered AA (matches the .frag's SlugRenderMS).
static float slugRenderMS(
    float2 coord,
    float4 band_xform,
    int4 glyph_data,
    __global const float4 *curve_tex, int curve_tex_w,
    __global const uint2  *band_tex,
    float2 pixels_per_em,
    int frame)
{
    const float2 offsets[4] = {
        (float2)( 0.2548777f,  0.0698403f),
        (float2)( 0.0097553f,  0.1396806f),
        (float2)(-0.2353670f, -0.2904791f),
        (float2)(-0.4804893f, -0.2206388f),
    };
    float2 tShift = (float2)(
        fract((float)frame * 0.7548777f, (private float *)0),
        fract((float)frame * 0.5698403f, (private float *)0));
    // NOTE: OpenCL's fract has a pointer-to-integer-part output arg;
    // we don't need it here, so feed a private scratch each call.
    float2 pixel_size = (float2)(1.0f / fmax(pixels_per_em.x, 1.0f),
                                 1.0f / fmax(pixels_per_em.y, 1.0f));
    float total = 0.0f;
    for (int i = 0; i < 4; ++i) {
        float2 off_frac = offsets[i] + tShift + (float2)(0.5f);
        float ip;
        off_frac.x = fract(off_frac.x, &ip);
        off_frac.y = fract(off_frac.y, &ip);
        off_frac -= (float2)(0.5f);
        total += slugRender(coord + off_frac * pixel_size,
                            band_xform, glyph_data,
                            curve_tex, curve_tex_w, band_tex, pixels_per_em);
    }
    return total * 0.25f;
}

__kernel void slug_glyph_compute(
    __global       uchar4 *fb,
    const int    fb_width,
    const int    fb_height,
    __global const float4 *curve_tex,
    const int    curve_tex_w,
    __global const uint2  *band_tex,
    __global const SlugGlyphInstance *instances,
    const int    instance_count,
    const float  opacity,
    const int    frame)
{
    const int i  = get_global_id(0);
    const int dx = get_global_id(1);
    const int dy = get_global_id(2);
    if (i >= instance_count) return;

    SlugGlyphInstance inst = instances[i];
    const int x = inst.x0 + dx;
    const int y = inst.y0 + dy;
    if (x >= inst.x1 || y >= inst.y1) return;
    if (x < 0 || x >= fb_width)  return;
    if (y < 0 || y >= fb_height) return;

    // Bilinear-interpolate (u, v) from corner em-coords using the
    // local (dx, dy) within the bbox.
    const float bbw = (float)(inst.x1 - inst.x0);
    const float bbh = (float)(inst.y1 - inst.y0);
    const float fx  = bbw > 0 ? (float)dx / bbw : 0.0f;
    const float fy  = bbh > 0 ? (float)dy / bbh : 0.0f;
    const float u   = mix(inst.u0, inst.u1, fx);
    const float v   = mix(inst.v0, inst.v1, fy);

    const float4 band_xform = (float4)(inst.band_tx_ax, inst.band_tx_ay,
                                        inst.band_tx_bx, inst.band_tx_by);
    const int4   glyph_data = (int4)(inst.glyph_x, inst.glyph_y,
                                       inst.glyph_z, inst.glyph_w);
    const float2 ppe = (float2)(inst.pixels_per_em_x, inst.pixels_per_em_y);

    const int flags = inst.glyph_w;
    const bool has_glyph =
        (inst.glyph_x != 0 || inst.glyph_y != 0 || inst.glyph_z != 0 || (flags & 0xff) != 0);

    float r, g, b, a;
    if (!has_glyph) {
        r = inst.bg_r; g = inst.bg_g; b = inst.bg_b; a = inst.bg_a;
    } else {
        const float subStep = 1.0f / (3.0f * fmax(ppe.x, 1.0f));
        float cov_r = slugRenderMS((float2)(u - subStep, v), band_xform, glyph_data,
                                   curve_tex, curve_tex_w, band_tex, ppe, frame);
        float cov_g = slugRenderMS((float2)(u,            v), band_xform, glyph_data,
                                   curve_tex, curve_tex_w, band_tex, ppe, frame);
        float cov_b = slugRenderMS((float2)(u + subStep, v), band_xform, glyph_data,
                                   curve_tex, curve_tex_w, band_tex, ppe, frame);
        r = mix(inst.bg_r, inst.fg_r, cov_r);
        g = mix(inst.bg_g, inst.fg_g, cov_g);
        b = mix(inst.bg_b, inst.fg_b, cov_b);
        a = mix(inst.bg_a, inst.fg_a, fmax(cov_r, fmax(cov_g, cov_b)));
    }
    a *= opacity;

    // Decorations (flag bits 0x200..0x4000).
    if ((flags & 0xff00) != 0) {
        const float cux = (float)(x - inst.cell_x) / fmax((float)inst.cell_w, 1.0f);
        const float cuy = (float)(y - inst.cell_y) / fmax((float)inst.cell_h, 1.0f);
        const float dt  = fmax(1.0f, (float)inst.cell_h * 0.05f) / fmax((float)inst.cell_h, 1.0f);
        const float fa  = inst.fg_a * opacity;
        bool dec = false;
        if ((flags & 0x200)  != 0 && cuy > 1.0f - dt)              dec = true;
        if ((flags & 0x400)  != 0 && fabs(cuy - 0.5f) < dt * 0.5f) dec = true;
        if ((flags & 0x800)  != 0 && cuy < dt)                     dec = true;
        if ((flags & 0x1000) != 0 && cuy > 1.0f - dt)              dec = true;
        if ((flags & 0x2000) != 0 && cux < dt)                     dec = true;
        if ((flags & 0x4000) != 0 && cux > 1.0f - dt)              dec = true;
        if (dec) { r = inst.fg_r; g = inst.fg_g; b = inst.fg_b; a = fa; }
    }

    fb[y * fb_width + x] = (uchar4)(
        (uchar)clamp(r * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(g * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(b * 255.0f, 0.0f, 255.0f),
        (uchar)clamp(a * 255.0f, 0.0f, 255.0f));
}
