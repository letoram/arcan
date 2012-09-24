#version 120

uniform sampler2D map_tu0; /* edge       */
uniform sampler2D map_tu1; /* area   LUT */
uniform sampler2D map_tu2; /* search LUT */

uniform vec2 pixel_size;

varying vec2 texco;
varying vec2 pixcoord;
varying vec4 offset[3];

float SearchDiag1(vec2 texco, vec2 dir, float c) {
    texco += dir * pixel_size;
    vec2 e = vec2(0.0, 0.0);
    float i;
    for (i = 0.0; i < float(8); i++) {
        e.rg = texture2DLod(map_tu0, texco, 0.0).rg;
        if (dot(e, vec2(1.0, 1.0)) < 1.9) break;
        texco += dir * pixel_size;
    }
    return i + float(e.g > 0.9) * c;
}

float SearchDiag2(vec2 texco, vec2 dir, float c) {
    texco += dir * pixel_size;
    vec2 e = vec2(0.0, 0.0);
    float i;
    for (i = 0.0; i < float(8); i++) {
        e.g = texture2DLod(map_tu0, texco, 0.0).g;
        e.r = texture2DLod(map_tu0, texco + ivec2(1, 0), 0.0).r;
        if (dot(e, vec2(1.0, 1.0)) < 1.9) break;
        texco += dir * pixel_size;
    }
    return i + float(e.g > 0.9) * c;
}

vec2 AreaDiag(vec2 dist, vec2 e) {
    vec2 texco = float(20) * e + dist;
    texco = (1.0 / vec2(160.0, 560.0)) * texco + (0.5 * (1.0 / vec2(160.0, 560.0)));
    texco.x += 0.5;
    texco.y += (1.0 / 7.0);

    return texture2DLod(map_tu1, texco, 0.0).rg;
}

vec2 CalculateDiagWeights(vec2 texco, vec2 e) {
    vec2 weights = vec2(0.0, 0.0);

    vec2 d;
    d.x = e.r > 0.0? SearchDiag1(texco, vec2(-1.0, 1.0), 1.0) : 0.0;
    d.y = SearchDiag1(texco, vec2(1.0, -1.0), 0.0);

    if (d.r + d.g > 2.0) {
        vec4 coords = (vec4(-d.r, d.r, d.g, -d.g) * pixel_size.xyxy + texco.xyxy);
        vec4 c;
        c.x = texture2DLod(map_tu0, coords.xy + ivec2(-1, 0), 0.0).g;
        c.y = texture2DLod(map_tu0, coords.xy, 0.0).r;
        c.z = texture2DLod(map_tu0, coords.zw + ivec2( 1, 0), 0.0).g;
        c.w = texture2DLod(map_tu0, coords.zw + ivec2( 1,-1), 0.0).r;
        vec2 e = 2.0 * c.xz + c.yw;
        float t = float(8) - 1.0;
        e *= step(d.rg, vec2(t, t));

        weights += AreaDiag(d, e);
    }

    d.x = SearchDiag2(texco, vec2(-1.0, -1.0), 0.0);
    float right = texture2DLod(map_tu0, texco + ivec2(1, 0), 0.0).r;
    d.y = right > 0.0? SearchDiag2(texco, vec2(1.0, 1.0), 1.0) : 0.0;

    if (d.r + d.g > 2.0) {
        vec4 coords = (vec4(-d.r, -d.r, d.g, d.g) * pixel_size.xyxy + texco.xyxy);
        vec4 c;
        c.x = texture2DLod(map_tu0, coords.xy + ivec2(-1, 0), 0.0).g;
        c.y = texture2DLod(map_tu0, coords.xy + ivec2( 0,-1), 0.0).r;
        c.zw = texture2DLod(map_tu0, coords.zw + ivec2( 1, 0), 0.0).gr;
        vec2 e = 2.0 * c.xz + c.yw;
        float t = float(8) - 1.0;
        e *= step(d.rg, vec2(t, t));

        weights += AreaDiag(d, e).gr;
    }

    return weights;
}

float SearchLength(vec2 e, float bias, float scale) {
    e.r = bias + e.r * scale;
     e.g = -e.g;
    return 255.0 * texture2DLod(map_tu2, e, 0.0).r;
}

float SearchXLeft(vec2 texco, float end) {
    vec2 e = vec2(0.0, 1.0);
    while (texco.x > end &&
           e.g > 0.8281 &&
           e.r == 0.0) {
        e = texture2DLod(map_tu0, texco, 0.0).rg;
        texco -= vec2(2.0, 0.0) * pixel_size;
    }

    texco.x += 0.25 * pixel_size.x;
    texco.x += pixel_size.x;
    texco.x += 2.0 * pixel_size.x;
    texco.x -= pixel_size.x * SearchLength(e, 0.0, 0.5);

    return texco.x;
}

float SearchXRight(vec2 texco, float end) {
    vec2 e = vec2(0.0, 1.0);
    while (texco.x < end &&
           e.g > 0.8281 &&
           e.r == 0.0) {
        e = texture2DLod(map_tu0, texco, 0.0).rg;
        texco += vec2(2.0, 0.0) * pixel_size;
    }

    texco.x -= 0.25 * pixel_size.x;
    texco.x -= pixel_size.x;
    texco.x -= 2.0 * pixel_size.x;
    texco.x += pixel_size.x * SearchLength(e, 0.5, 0.5);
    return texco.x;
}

float SearchYUp(vec2 texco, float end) {
    vec2 e = vec2(1.0, 0.0);
    while (texco.y > end &&
           e.r > 0.8281 &&
           e.g == 0.0) {
        e = texture2DLod(map_tu0, texco, 0.0).rg;
        texco -= vec2(0.0, 2.0) * pixel_size;
    }

    texco.y += 0.25 * pixel_size.y;
    texco.y += pixel_size.y;
    texco.y += 2.0 * pixel_size.y;
    texco.y -= pixel_size.y * SearchLength(e.gr, 0.0, 0.5);
    return texco.y;
}

float SearchYDown(vec2 texco, float end) {
    vec2 e = vec2(1.0, 0.0);
    while (texco.y < end &&
           e.r > 0.8281 &&
           e.g == 0.0) {
        e = texture2DLod(map_tu0, texco, 0.0).rg;
        texco += vec2(0.0, 2.0) * pixel_size;
    }

    texco.y -= 0.25 * pixel_size.y;
    texco.y -= pixel_size.y;
    texco.y -= 2.0 * pixel_size.y;
    texco.y += pixel_size.y * SearchLength(e.gr, 0.5, 0.5);
    return texco.y;
}

vec2 roundv2(vec2 inv)
{
    return sign(inv) * floor( abs(inv) + 0.5 );
}

vec2 Area(vec2 dist, float e1, float e2) {
    vec2 texco = float(16) * roundv2(4.0 * vec2(e1, e2)) + dist;
    texco = (1.0 / vec2(160.0, 560.0)) * texco + (0.5 * (1.0 / vec2(160.0, 560.0)));
    texco.y += (1.0 / 7.0);

    return texture2DLod(map_tu1, texco, 0.0).rg;
}

void DetectHorizontalCornerPattern(inout vec2 weights, vec2 texco, vec2 d) {
    vec4 coords = (vec4(d.x, 0.0, d.y, 0.0) * pixel_size.xyxy + texco.xyxy);
    vec2 e;
    e.r = texture2DLod(map_tu0, coords.xy + ivec2(0.0, 1.0), 0.0).r;
    bool left = abs(d.x) < abs(d.y);
    e.g = texture2DLod(map_tu0, coords.xy + ivec2(0.0, -2.0), 0.0).r;
    if (left) weights *= clamp(float(25) / 100.0 + 1.0 - e, 0.0, 1.0);

    e.r = texture2DLod(map_tu0, coords.zw + ivec2(1.0, 1.0), 0.0).r;
    e.g = texture2DLod(map_tu0, coords.zw + ivec2(1.0,-2.0), 0.0).r;
    if (!left) weights *= clamp(float(25) / 100.0 + 1.0 - e, 0.0, 1.0);
}

void DetectVerticalCornerPattern(inout vec2 weights, vec2 texco, vec2 d) {
    vec4 coords = (vec4(0.0, d.x, 0.0, d.y) * pixel_size.xyxy + texco.xyxy);
    vec2 e;
    e.r = texture2DLod(map_tu0, coords.xy + ivec2(1.0, 0.0), 0.0).g;
    bool left = abs(d.x) < abs(d.y);
    e.g = texture2DLod(map_tu0, coords.xy + ivec2(-2.0,0.0), 0.0).g;
    if (left) weights *= clamp(float(25) / 100.0 + 1.0 - e, 0.0, 1.0);

    e.r = texture2DLod(map_tu0, coords.zw + ivec2(1.0, 1.0), 0.0).g;
    e.g = texture2DLod(map_tu0, coords.zw + ivec2(-2.0, 1.0), 0.0).g;
    if (!left) weights *= clamp(float(25) / 100.0 + 1.0 - e, 0.0, 1.0);
}

void main()
{
    vec4 weights = vec4(0.0, 0.0, 0.0, 0.0);
    vec2 e = texture2D(map_tu0, texco).rg;

    if (e.g > 0.0) {
        weights.rg = CalculateDiagWeights(texco, e);
        if (dot(weights.rg, vec2(1.0, 1.0)) == 0.0) {
        vec2 d;
        vec2 coords;
        coords.x = SearchXLeft(offset[0].xy, offset[2].x);
        coords.y = offset[1].y;
        d.x = coords.x;
        float e1 = texture2DLod(map_tu0, coords, 0.0).r;
        coords.x = SearchXRight(offset[0].zw, offset[2].y);
        d.y = coords.x;
        d = d / pixel_size.x - pixcoord.x;
        vec2 sqrt_d = sqrt(abs(d));
        float e2 = texture2DLod(map_tu0, coords + ivec2(1,0), 0.0).r;
        weights.rg = Area(sqrt_d, e1, e2);
        DetectHorizontalCornerPattern(weights.rg, texco, d);
        } else
            e.r = 0.0;
    }

    if (e.r > 0.0) {
        vec2 d;
        vec2 coords;
        coords.y = SearchYUp(offset[1].xy, offset[2].z);
        coords.x = offset[0].x;
        d.x = coords.y;

        float e1 = texture2DLod(map_tu0, coords, 0.0).g;
        coords.y = SearchYDown(offset[1].zw, offset[2].w);
        d.y = coords.y;
        d = d / pixel_size.y - pixcoord.y;
        vec2 sqrt_d = sqrt(abs(d));

        float e2 = texture2DLod(map_tu0, coords + ivec2(0, 1), 0.0).g;
        weights.ba = Area(sqrt_d, e1, e2);

        DetectVerticalCornerPattern(weights.ba, texco, d);
    }

    gl_FragColor = weights;
}
