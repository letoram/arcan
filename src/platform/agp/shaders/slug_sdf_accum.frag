#version 450
// SDF Accumulation fragment shader.
// Computes 4-sample MSAA SlugRender with temporal R2 jitter and writes
// running-mean coverage to R16F atlas. Uses hardware EMA blending:
//   result = alpha * fresh + (1-alpha) * previous
// where alpha = blend_constant, set per-frame to 1/(frame+1) for exact mean.

// ── Texture bindings ──
layout(set = 0, binding = 0) uniform sampler2D curveTexture;
layout(set = 0, binding = 2) uniform usampler2D bandTexture;

// ── Push constants ──
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

// ── Inputs from vertex shader ──
layout(location = 0) in vec2 vTexcoord;
layout(location = 1) flat in vec4 vBandTransform;
layout(location = 2) flat in ivec4 vGlyphData;
layout(location = 3) flat in vec4 vFgColor;
layout(location = 4) flat in vec4 vBgColor;

layout(location = 0) out float fragSdf;

// ── Band texture width ──
#define kLogBandTextureWidth 12

// ════════════════════════════════════════════════════════════════════
// Core Slug Algorithm (identical to slug_glyph.frag)
// ════════════════════════════════════════════════════════════════════

uint CalcRootCode(float y1, float y2, float y3) {
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;
    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);
    return ((0x2E74u >> shift) & 0x0101u);
}

vec2 SolveHorizPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;
    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;
    if (abs(a.y) < 1.0 / 1024.0) { t1 = p12.y * rb; t2 = t1; }
    return vec2(
        (a.x * t1 - b.x * 2.0) * t1 + p12.x,
        (a.x * t2 - b.x * 2.0) * t2 + p12.x
    );
}

vec2 SolveVertPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.x;
    float rb = 0.5 / b.x;
    float d = sqrt(max(b.x * b.x - a.x * p12.x, 0.0));
    float t1 = (b.x - d) * ra;
    float t2 = (b.x + d) * ra;
    if (abs(a.x) < 1.0 / 1024.0) { t1 = p12.x * rb; t2 = t1; }
    return vec2(
        (a.y * t1 - b.y * 2.0) * t1 + p12.y,
        (a.y * t2 - b.y * 2.0) * t2 + p12.y
    );
}

ivec2 CalcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 bandLoc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    bandLoc.y += bandLoc.x >> kLogBandTextureWidth;
    bandLoc.x &= (1 << kLogBandTextureWidth) - 1;
    return bandLoc;
}

float CalcCoverage(float xcov, float ycov, float xwgt, float ywgt) {
    // Lengyel reference: fallback is min(abs(xcov), abs(ycov)), NOT average.
    // min acts as logical AND: both rays must agree there's coverage.
    // Average leaks partial coverage from one ray when the other reads zero,
    // causing spurious lit pixels on diagonal strokes (e.g. '7').
    float coverage = max(
        abs(xcov * xwgt + ycov * ywgt) / max(xwgt + ywgt, 1.0 / 65536.0),
        min(abs(xcov), abs(ycov))
    );
    return clamp(coverage, 0.0, 1.0);
}

float SlugRender(vec2 renderCoord, vec4 bandTransform, ivec4 glyphData) {
    vec2 emsPerPixel = max(fwidth(renderCoord), vec2(1.0 / 4096.0));
    vec2 pixelsPerEm = 1.0 / emsPerPixel;

    // Rectangle fast-path
    if ((glyphData.w & 0x100) != 0) {
        vec4 bounds = bandTransform;
        float ramp = 0.5;
        float dLeft   = (renderCoord.x - bounds.x) * pixelsPerEm.x;
        float dRight  = (bounds.z - renderCoord.x) * pixelsPerEm.x;
        float dBottom = (renderCoord.y - bounds.y) * pixelsPerEm.y;
        float dTop    = (bounds.w - renderCoord.y) * pixelsPerEm.y;
        return clamp(dLeft + ramp, 0.0, 1.0)
             * clamp(dRight + ramp, 0.0, 1.0)
             * clamp(dBottom + ramp, 0.0, 1.0)
             * clamp(dTop + ramp, 0.0, 1.0);
    }

    ivec2 bandMax = glyphData.zw;
    bandMax.x &= 0xFF;
    bandMax.y &= 0x00FF;

    ivec2 bandIndex = clamp(
        ivec2(renderCoord * bandTransform.xy + bandTransform.zw),
        ivec2(0, 0), bandMax
    );
    ivec2 glyphLoc = glyphData.xy;

    float xcov = 0.0, xwgt = 0.0;
    uvec2 hbandData = texelFetch(bandTexture, ivec2(glyphLoc.x + bandIndex.y, glyphLoc.y), 0).xy;
    ivec2 hbandLoc = CalcBandLoc(glyphLoc, hbandData.y);
    for (int curveIndex = 0; curveIndex < int(hbandData.x); curveIndex++) {
        ivec2 curveLoc = ivec2(texelFetch(bandTexture, ivec2(hbandLoc.x + curveIndex, hbandLoc.y), 0).xy);
        vec4 p12 = texelFetch(curveTexture, curveLoc, 0) - vec4(renderCoord, renderCoord);
        vec2 p3 = texelFetch(curveTexture, ivec2(curveLoc.x + 1, curveLoc.y), 0).xy - renderCoord;
        if (max(max(p12.x, p12.z), p3.x) * pixelsPerEm.x < -0.5) break;
        uint code = CalcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = SolveHorizPoly(p12, p3) * pixelsPerEm.x;
            float ramp = 0.5;
            if ((code & 1u) != 0u) { xcov += clamp(r.x + ramp, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.x) / ramp, 0.0, 1.0)); }
            if (code > 1u) { xcov -= clamp(r.y + ramp, 0.0, 1.0); xwgt = max(xwgt, clamp(1.0 - abs(r.y) / ramp, 0.0, 1.0)); }
        }
    }

    float ycov = 0.0, ywgt = 0.0;
    uvec2 vbandData = texelFetch(bandTexture, ivec2(glyphLoc.x + bandMax.y + 1 + bandIndex.x, glyphLoc.y), 0).xy;
    ivec2 vbandLoc = CalcBandLoc(glyphLoc, vbandData.y);
    for (int curveIndex = 0; curveIndex < int(vbandData.x); curveIndex++) {
        ivec2 curveLoc = ivec2(texelFetch(bandTexture, ivec2(vbandLoc.x + curveIndex, vbandLoc.y), 0).xy);
        vec4 p12 = texelFetch(curveTexture, curveLoc, 0) - vec4(renderCoord, renderCoord);
        vec2 p3 = texelFetch(curveTexture, ivec2(curveLoc.x + 1, curveLoc.y), 0).xy - renderCoord;
        if (max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5) break;
        uint code = CalcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            vec2 r = SolveVertPoly(p12, p3) * pixelsPerEm.y;
            float ramp = 0.5;
            if ((code & 1u) != 0u) { ycov -= clamp(r.x + ramp, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.x) / ramp, 0.0, 1.0)); }
            if (code > 1u) { ycov += clamp(r.y + ramp, 0.0, 1.0); ywgt = max(ywgt, clamp(1.0 - abs(r.y) / ramp, 0.0, 1.0)); }
        }
    }

    return CalcCoverage(xcov, ycov, xwgt, ywgt);
}

// ════════════════════════════════════════════════════════════════════
// 4-sample MSAA with R2 quasirandom temporal jitter
// ════════════════════════════════════════════════════════════════════

#define MSAA_SAMPLES 8

float SlugRenderMS(vec2 renderCoord, vec4 bandTransform, ivec4 glyphData) {
    vec2 pixelSize = max(fwidth(renderCoord), vec2(1.0 / 4096.0));

    const vec2 offsets[8] = vec2[8](
        vec2( 0.2548777,  0.0698403),
        vec2( 0.0097553,  0.1396806),
        vec2(-0.2353670, -0.2904791),
        vec2(-0.4804893, -0.2206388),
        vec2( 0.0047553,  0.3495209),
        vec2(-0.2403670,  0.4193612),
        vec2( 0.2648777, -0.4508185),
        vec2( 0.0197553, -0.3809782)
    );

    int frame = int(pc.fract_timestamp);
    vec2 tShift = vec2(
        fract(float(frame) * 0.7548777),
        fract(float(frame) * 0.5698403)
    );

    float total = 0.0;
    for (int i = 0; i < MSAA_SAMPLES; i++) {
        vec2 offset = fract(offsets[i] + tShift + vec2(0.5)) - vec2(0.5);
        total += SlugRender(renderCoord + offset * pixelSize, bandTransform, glyphData);
    }
    return total / float(MSAA_SAMPLES);
}

// ════════════════════════════════════════════════════════════════════

void main() {
    if (vGlyphData.x == 0 && vGlyphData.y == 0 && vGlyphData.z == 0 && vGlyphData.w == 0) {
        discard;
    }

    // Converged glyphs (sc=255) skip — keep previous value
    int n = (vGlyphData.z >> 20) & 0xFF;
    if (n >= 255) discard;

    // 4-sample MSAA with temporal R2 jitter — different samples each frame
    fragSdf = SlugRenderMS(vTexcoord, vBandTransform, vGlyphData);
}
