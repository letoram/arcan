// slug_sdf_accum.cl — OpenCL port of slug_sdf_accum.frag.
// 8-sample MSAA Slug coverage, accumulated into a per-glyph SDF atlas
// via host-supplied EMA alpha:
//   atlas[p] = alpha * fresh + (1 - alpha) * atlas[p]
// Host computes alpha = 1 / (frame_idx + 1) for an exact running mean.

#define kLogBandTextureWidth 12
#define kBandTextureWidth    (1 << kLogBandTextureWidth)

typedef struct {
    int   atlas_x, atlas_y, atlas_w, atlas_h;  // bbox in the SDF atlas
    float u0, v0, u1, v1;                      // em-space corners
    float band_tx_ax, band_tx_ay, band_tx_bx, band_tx_by;
    int   glyph_x, glyph_y, glyph_z, glyph_w;
    float pixels_per_em_x, pixels_per_em_y;
} SlugSdfInstance;

// Identical helpers to slug_glyph.cl (same Lengyel math).
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
    float  t1 = (b.y - d) * ra, t2 = (b.y + d) * ra;
    if (fabs(a.y) < 1.0f / 1024.0f) { t1 = p12.y * rb; t2 = t1; }
    return (float2)((a.x * t1 - b.x * 2.0f) * t1 + p12.x,
                    (a.x * t2 - b.x * 2.0f) * t2 + p12.x);
}
static inline float2 solveVertPoly(float4 p12, float2 p3) {
    float2 a  = p12.xy - p12.zw * 2.0f + p3;
    float2 b  = p12.xy - p12.zw;
    float  ra = 1.0f / a.x;
    float  rb = 0.5f / b.x;
    float  d  = sqrt(fmax(b.x * b.x - a.x * p12.x, 0.0f));
    float  t1 = (b.x - d) * ra, t2 = (b.x + d) * ra;
    if (fabs(a.x) < 1.0f / 1024.0f) { t1 = p12.x * rb; t2 = t1; }
    return (float2)((a.y * t1 - b.y * 2.0f) * t1 + p12.y,
                    (a.y * t2 - b.y * 2.0f) * t2 + p12.y);
}
static inline int2 calcBandLoc(int gx, int gy, uint offset) {
    int bx = gx + (int)offset;
    int by = gy + (bx >> kLogBandTextureWidth);
    bx &= (kBandTextureWidth - 1);
    return (int2)(bx, by);
}
static inline float calcCoverage(float xcov, float ycov, float xwgt, float ywgt) {
    return clamp(fmax(
        fabs(xcov * xwgt + ycov * ywgt) / fmax(xwgt + ywgt, 1.0f / 65536.0f),
        fmin(fabs(xcov), fabs(ycov))), 0.0f, 1.0f);
}
static float slugRender(
    float2 coord, float4 band_xform, int4 glyph_data,
    __global const float4 *curve_tex, int curve_tex_w,
    __global const uint2  *band_tex,
    float2 pixels_per_em)
{
    if ((glyph_data.w & 0x100) != 0) {
        float4 bounds = band_xform;
        const float ramp = 0.5f;
        float dL = (coord.x - bounds.x) * pixels_per_em.x;
        float dR = (bounds.z - coord.x) * pixels_per_em.x;
        float dB = (coord.y - bounds.y) * pixels_per_em.y;
        float dT = (bounds.w - coord.y) * pixels_per_em.y;
        return clamp(dL + ramp, 0.0f, 1.0f) * clamp(dR + ramp, 0.0f, 1.0f)
             * clamp(dB + ramp, 0.0f, 1.0f) * clamp(dT + ramp, 0.0f, 1.0f);
    }
    int2 band_max = (int2)(glyph_data.z & 0xff, glyph_data.w & 0xff);
    int2 band_idx = clamp(
        (int2)((int)floor(coord.x * band_xform.x + band_xform.z),
               (int)floor(coord.y * band_xform.y + band_xform.w)),
        (int2)(0, 0), band_max);
    int gx = glyph_data.x, gy = glyph_data.y;
    float xcov = 0.0f, xwgt = 0.0f;
    uint2 hb = band_tex[gy * kBandTextureWidth + (gx + band_idx.y)];
    int2  hl = calcBandLoc(gx, gy, hb.y);
    for (int i = 0; i < (int)hb.x; ++i) {
        uint2 cl_u = band_tex[hl.y * kBandTextureWidth + (hl.x + i)];
        int2  cl   = (int2)((int)cl_u.x, (int)cl_u.y);
        int   base = cl.y * curve_tex_w + cl.x;
        float4 p12 = curve_tex[base] - (float4)(coord.x, coord.y, coord.x, coord.y);
        float2 p3  = curve_tex[base + 1].xy - coord;
        if (fmax(fmax(p12.x, p12.z), p3.x) * pixels_per_em.x < -0.5f) break;
        uint code = calcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            float2 r = solveHorizPoly(p12, p3) * pixels_per_em.x;
            float ramp = 0.5f;
            if ((code & 1u) != 0u) { xcov += clamp(r.x + ramp, 0.0f, 1.0f);
                xwgt = fmax(xwgt, clamp(1.0f - fabs(r.x) / ramp, 0.0f, 1.0f)); }
            if (code > 1u) { xcov -= clamp(r.y + ramp, 0.0f, 1.0f);
                xwgt = fmax(xwgt, clamp(1.0f - fabs(r.y) / ramp, 0.0f, 1.0f)); }
        }
    }
    float ycov = 0.0f, ywgt = 0.0f;
    uint2 vb = band_tex[gy * kBandTextureWidth + (gx + band_max.y + 1 + band_idx.x)];
    int2  vl = calcBandLoc(gx, gy, vb.y);
    for (int i = 0; i < (int)vb.x; ++i) {
        uint2 cl_u = band_tex[vl.y * kBandTextureWidth + (vl.x + i)];
        int2  cl   = (int2)((int)cl_u.x, (int)cl_u.y);
        int   base = cl.y * curve_tex_w + cl.x;
        float4 p12 = curve_tex[base] - (float4)(coord.x, coord.y, coord.x, coord.y);
        float2 p3  = curve_tex[base + 1].xy - coord;
        if (fmax(fmax(p12.y, p12.w), p3.y) * pixels_per_em.y < -0.5f) break;
        uint code = calcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            float2 r = solveVertPoly(p12, p3) * pixels_per_em.y;
            float ramp = 0.5f;
            if ((code & 1u) != 0u) { ycov -= clamp(r.x + ramp, 0.0f, 1.0f);
                ywgt = fmax(ywgt, clamp(1.0f - fabs(r.x) / ramp, 0.0f, 1.0f)); }
            if (code > 1u) { ycov += clamp(r.y + ramp, 0.0f, 1.0f);
                ywgt = fmax(ywgt, clamp(1.0f - fabs(r.y) / ramp, 0.0f, 1.0f)); }
        }
    }
    return calcCoverage(xcov, ycov, xwgt, ywgt);
}

__kernel void slug_sdf_accum_compute(
    __global       float *atlas,            // R32F coverage atlas
    const int    atlas_stride,              // pixels per atlas row
    __global const float4 *curve_tex, const int curve_tex_w,
    __global const uint2  *band_tex,
    __global const SlugSdfInstance *instances,
    const int    instance_count,
    const float  ema_alpha,                 // 1/(frame+1)
    const int    frame)
{
    const int i  = get_global_id(0);
    const int dx = get_global_id(1);
    const int dy = get_global_id(2);
    if (i >= instance_count) return;
    SlugSdfInstance inst = instances[i];
    if (dx >= inst.atlas_w || dy >= inst.atlas_h) return;

    // Skip converged glyphs (sc=255 in glyph_z bits 20-27).
    int n = (inst.glyph_z >> 20) & 0xff;
    if (n >= 255) return;

    const float fx = (inst.atlas_w > 1) ? (float)dx / (float)(inst.atlas_w - 1) : 0.0f;
    const float fy = (inst.atlas_h > 1) ? (float)dy / (float)(inst.atlas_h - 1) : 0.0f;
    const float u  = mix(inst.u0, inst.u1, fx);
    const float v  = mix(inst.v0, inst.v1, fy);

    const float4 band_xform = (float4)(inst.band_tx_ax, inst.band_tx_ay,
                                        inst.band_tx_bx, inst.band_tx_by);
    const int4   glyph_data = (int4)(inst.glyph_x, inst.glyph_y,
                                      inst.glyph_z, inst.glyph_w);
    const float2 ppe = (float2)(inst.pixels_per_em_x, inst.pixels_per_em_y);

    // 8-sample R2 jitter (matches the .frag's MSAA_SAMPLES = 8).
    const float2 offsets[8] = {
        (float2)( 0.2548777f,  0.0698403f), (float2)( 0.0097553f,  0.1396806f),
        (float2)(-0.2353670f, -0.2904791f), (float2)(-0.4804893f, -0.2206388f),
        (float2)( 0.0047553f,  0.3495209f), (float2)(-0.2403670f,  0.4193612f),
        (float2)( 0.2648777f, -0.4508185f), (float2)( 0.0197553f, -0.3809782f),
    };
    float ip;
    float2 tShift = (float2)(fract((float)frame * 0.7548777f, &ip),
                              fract((float)frame * 0.5698403f, &ip));
    float2 pixel_size = (float2)(1.0f / fmax(ppe.x, 1.0f),
                                  1.0f / fmax(ppe.y, 1.0f));
    float total = 0.0f;
    for (int s = 0; s < 8; ++s) {
        float2 off = offsets[s] + tShift + (float2)(0.5f);
        off.x = fract(off.x, &ip); off.y = fract(off.y, &ip);
        off -= (float2)(0.5f);
        total += slugRender((float2)(u + off.x * pixel_size.x,
                                       v + off.y * pixel_size.y),
                            band_xform, glyph_data,
                            curve_tex, curve_tex_w, band_tex, ppe);
    }
    float fresh = total * (1.0f / 8.0f);

    const int p = (inst.atlas_y + dy) * atlas_stride + (inst.atlas_x + dx);
    const float prev = atlas[p];
    atlas[p] = ema_alpha * fresh + (1.0f - ema_alpha) * prev;
}
