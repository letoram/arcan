#version 450
// Slug glyph fragment shader — GLSL 450 port of Eric Lengyel's Slug algorithm.
// SPDX-License-Identifier: MIT OR Apache-2.0
// Copyright 2017, Eric Lengyel. Ported for arcan Vulkan compositor.
//
// Evaluates quadratic Bézier curve coverage per pixel using dual-ray winding
// number computation. No CPU rasterization, no bitmap cache, no hinting.

// ── Texture bindings ──
// Matches arcan descriptor set layout: binding 0 = sampler, binding 1 = UBO, binding 2 = sampler
layout(set = 0, binding = 0) uniform sampler2D curveTexture;   // RGBA float16: (x1,y1,x2,y2), (x3,y3,0,0)
layout(set = 0, binding = 2) uniform usampler2D bandTexture;   // RGBA uint16: band data + curve lists
layout(set = 0, binding = 3) uniform sampler2D sdfAtlas;       // R16F: cached SDF coverage

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
layout(location = 5) flat in vec2 vCellPos;
layout(location = 6) flat in vec2 vCellSize;

layout(location = 0) out vec4 fragColor;

// ── Band texture width (must match slug_glyph.zig BAND_TEX_WIDTH) ──
#define kLogBandTextureWidth 12

// ════════════════════════════════════════════════════════════════════
// Core Slug Algorithm (Eric Lengyel, JCGT 2017)
// ════════════════════════════════════════════════════════════════════

// Calculate root eligibility code from sign pattern of y-coordinates.
// Returns bits 0 and 8 indicating which roots of the quadratic contribute.
uint CalcRootCode(float y1, float y2, float y3) {
    uint i1 = floatBitsToUint(y1) >> 31u;
    uint i2 = floatBitsToUint(y2) >> 30u;
    uint i3 = floatBitsToUint(y3) >> 29u;

    uint shift = (i2 & 2u) | (i1 & ~2u);
    shift = (i3 & 4u) | (shift & ~4u);

    return ((0x2E74u >> shift) & 0x0101u);
}

// Solve for x-coordinates where quadratic Bézier crosses y = 0.
// p12 = (x1, y1, x2, y2), p3 = (x3, y3)
vec2 SolveHorizPoly(vec4 p12, vec2 p3) {
    vec2 a = p12.xy - p12.zw * 2.0 + p3;
    vec2 b = p12.xy - p12.zw;
    float ra = 1.0 / a.y;
    float rb = 0.5 / b.y;

    float d = sqrt(max(b.y * b.y - a.y * p12.y, 0.0));
    float t1 = (b.y - d) * ra;
    float t2 = (b.y + d) * ra;

    // Nearly linear case: solve -2b·t + c = 0
    // Threshold raised from 1/65536 to catch degenerate quadratics from
    // promoted line segments. In float32, lines produce a ≈ 2e-5 due to
    // rounding in midpoint calculation, which exceeds 1/65536 = 1.5e-5.
    if (abs(a.y) < 1.0 / 1024.0) { t1 = p12.y * rb; t2 = t1; }

    return vec2(
        (a.x * t1 - b.x * 2.0) * t1 + p12.x,
        (a.x * t2 - b.x * 2.0) * t2 + p12.x
    );
}

// Solve for y-coordinates where quadratic Bézier crosses x = 0.
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

// Calculate band texture location with wrapping.
ivec2 CalcBandLoc(ivec2 glyphLoc, uint offset) {
    ivec2 bandLoc = ivec2(glyphLoc.x + int(offset), glyphLoc.y);
    bandLoc.y += bandLoc.x >> kLogBandTextureWidth;
    bandLoc.x &= (1 << kLogBandTextureWidth) - 1;
    return bandLoc;
}

// Combine horizontal and vertical ray coverages into final alpha.
// Lengyel's exact formula (SlugPixelShader.hlsl): single expression,
// no branches, no magic thresholds. The min-floor prevents geometric dropout.
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

// ════════════════════════════════════════════════════════════════════
// Main render function
// ════════════════════════════════════════════════════════════════════

float SlugRender(vec2 renderCoord, vec4 bandTransform, ivec4 glyphData) {
    // Effective pixel dimensions of the em square
    vec2 emsPerPixel = max(fwidth(renderCoord), vec2(1.0 / 4096.0));
    vec2 pixelsPerEm = 1.0 / emsPerPixel;

    // ── Rectangle fast-path ──
    // Bit 8 of glyphData.w flags axis-aligned rectangles (underscore, pipe, etc).
    // bandTransform is repurposed to carry (min_x, min_y, max_x, max_y) in em-space.
    // Use box SDF instead of full Slug winding — perfect crisp edges.
    if ((glyphData.w & 0x100) != 0) {
        vec4 bounds = bandTransform; // repurposed for rect bounds
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
    bandMax.x &= 0xFF;   // mask off SDF atlas data packed in upper bits
    bandMax.y &= 0x00FF;

    // Determine which bands the current pixel falls in
    ivec2 bandIndex = clamp(
        ivec2(renderCoord * bandTransform.xy + bandTransform.zw),
        ivec2(0, 0), bandMax
    );
    ivec2 glyphLoc = glyphData.xy;

    // ── Horizontal ray (leftward from pixel) ──
    float xcov = 0.0;
    float xwgt = 0.0;

    uvec2 hbandData = texelFetch(bandTexture, ivec2(glyphLoc.x + bandIndex.y, glyphLoc.y), 0).xy;
    ivec2 hbandLoc = CalcBandLoc(glyphLoc, hbandData.y);

    for (int curveIndex = 0; curveIndex < int(hbandData.x); curveIndex++) {
        // Fetch curve location from band index
        ivec2 curveLoc = ivec2(texelFetch(bandTexture, ivec2(hbandLoc.x + curveIndex, hbandLoc.y), 0).xy);

        // Fetch 3 control points, make sample-relative
        vec4 p12 = texelFetch(curveTexture, curveLoc, 0) - vec4(renderCoord, renderCoord);
        vec2 p3 = texelFetch(curveTexture, ivec2(curveLoc.x + 1, curveLoc.y), 0).xy - renderCoord;

        // Early exit: curves sorted by descending max-x
        if (max(max(p12.x, p12.z), p3.x) * pixelsPerEm.x < -0.5) break;

        uint code = CalcRootCode(p12.y, p12.w, p3.y);
        if (code != 0u) {
            vec2 r = SolveHorizPoly(p12, p3) * pixelsPerEm.x;

            // Adaptive AA ramp: narrower at small sizes for crisper thin strokes.
            // ramp = 0.5 at 12px, 0.5 at 48px+ (standard Slug). Scale with emsPerPixel.
            float ramp = 0.5; // standard Slug ramp width

            if ((code & 1u) != 0u) {
                xcov += clamp(r.x + ramp, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.x) / ramp, 0.0, 1.0));
            }
            if (code > 1u) {
                xcov -= clamp(r.y + ramp, 0.0, 1.0);
                xwgt = max(xwgt, clamp(1.0 - abs(r.y) / ramp, 0.0, 1.0));
            }
        }
    }

    // ── Vertical ray (downward from pixel) ──
    float ycov = 0.0;
    float ywgt = 0.0;

    uvec2 vbandData = texelFetch(bandTexture, ivec2(glyphLoc.x + bandMax.y + 1 + bandIndex.x, glyphLoc.y), 0).xy;
    ivec2 vbandLoc = CalcBandLoc(glyphLoc, vbandData.y);

    for (int curveIndex = 0; curveIndex < int(vbandData.x); curveIndex++) {
        ivec2 curveLoc = ivec2(texelFetch(bandTexture, ivec2(vbandLoc.x + curveIndex, vbandLoc.y), 0).xy);
        vec4 p12 = texelFetch(curveTexture, curveLoc, 0) - vec4(renderCoord, renderCoord);
        vec2 p3 = texelFetch(curveTexture, ivec2(curveLoc.x + 1, curveLoc.y), 0).xy - renderCoord;

        // Early exit: matches official Slug threshold (-0.5 for both axes)
        if (max(max(p12.y, p12.w), p3.y) * pixelsPerEm.y < -0.5) break;

        uint code = CalcRootCode(p12.x, p12.z, p3.x);
        if (code != 0u) {
            vec2 r = SolveVertPoly(p12, p3) * pixelsPerEm.y;
            float ramp = 0.5;

            if ((code & 1u) != 0u) {
                ycov -= clamp(r.x + ramp, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.x) / ramp, 0.0, 1.0));
            }
            if (code > 1u) {
                ycov += clamp(r.y + ramp, 0.0, 1.0);
                ywgt = max(ywgt, clamp(1.0 - abs(r.y) / ramp, 0.0, 1.0));
            }
        }
    }

    return CalcCoverage(xcov, ycov, xwgt, ywgt);
}

// ════════════════════════════════════════════════════════════════════
// Multi-sample jittered AA (R2 quasirandom + temporal rotation)
// ════════════════════════════════════════════════════════════════════

#define MSAA_SAMPLES 4

float SlugRenderMS(vec2 renderCoord, vec4 bandTransform, ivec4 glyphData) {
    vec2 pixelSize = max(fwidth(renderCoord), vec2(1.0 / 4096.0));

    // R2 low-discrepancy quasirandom offsets, centered in [-0.5, 0.5]
    const vec2 offsets[4] = vec2[4](
        vec2( 0.2548777,  0.0698403),
        vec2( 0.0097553,  0.1396806),
        vec2(-0.2353670, -0.2904791),
        vec2(-0.4804893, -0.2206388)
    );

    // Temporal rotation via frame counter
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
// Entry point — SDF atlas read path + MSAA + subpixel RGB fallback
// ════════════════════════════════════════════════════════════════════

void main() {
    int flags = vGlyphData.w;
    bool has_glyph = (vGlyphData.x != 0 || vGlyphData.y != 0 || vGlyphData.z != 0 || (flags & 0xFF) != 0);

    if (!has_glyph) {
        // No glyph curves — fill background
        fragColor = vBgColor;
        fragColor.a *= pc.opacity;
    } else {
        // Standard SlugRender path — subpixel RGB with MSAA
        vec2 pixelSize = max(fwidth(vTexcoord), vec2(1.0 / 4096.0));
        float subStep = pixelSize.x / 3.0;

        float cov_r = SlugRenderMS(vTexcoord + vec2(-subStep, 0.0), vBandTransform, vGlyphData);
        float cov_g = SlugRenderMS(vTexcoord,                       vBandTransform, vGlyphData);
        float cov_b = SlugRenderMS(vTexcoord + vec2( subStep, 0.0), vBandTransform, vGlyphData);

        fragColor.r = mix(vBgColor.r, vFgColor.r, cov_r);
        fragColor.g = mix(vBgColor.g, vFgColor.g, cov_g);
        fragColor.b = mix(vBgColor.b, vFgColor.b, cov_b);
        fragColor.a = mix(vBgColor.a, vFgColor.a, max(cov_r, max(cov_g, cov_b)));
        fragColor.a *= pc.opacity;
    }

    // ── GPU decorations: underline, strikethrough, borders, cursor ──
    // Flags packed in vGlyphData.w bits 9-15
    if ((flags & 0xFF00) != 0) {
        vec2 cellUV = (gl_FragCoord.xy - vCellPos) / vCellSize;
        float dt = max(1.0, vCellSize.y * 0.05) / vCellSize.y;
        vec4 fg = vec4(vFgColor.rgb, vFgColor.a * pc.opacity);

        // Cursor flag (0x8000) intentionally has no GPU decoration.
        // Filling the cell with fg flashed as a red rectangle on resize;
        // drawing an underscore collided with the underline decoration
        // and looked like a dash on every cursor line. Let the terminal
        // backend render its own cursor glyph instead.
        if ((flags & 0x200) != 0 && cellUV.y > 1.0 - dt)
            fragColor = fg; // underline
        if ((flags & 0x400) != 0 && abs(cellUV.y - 0.5) < dt * 0.5)
            fragColor = fg; // strikethrough
        if ((flags & 0x800) != 0 && cellUV.y < dt)
            fragColor = fg; // border top
        if ((flags & 0x1000) != 0 && cellUV.y > 1.0 - dt)
            fragColor = fg; // border bottom
        if ((flags & 0x2000) != 0 && cellUV.x < dt)
            fragColor = fg; // border left
        if ((flags & 0x4000) != 0 && cellUV.x > 1.0 - dt)
            fragColor = fg; // border right
    }
}
