/* SABR v1.1 Shader
Joshua Street

Portions of this algorithm were taken from Hyllian's 5xBR v3.7c
shader.

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
*/

uniform sampler2D map_diffuse;
uniform vec2 texture_size;

varying vec2 tc;
varying vec4 xyp_1_2_3;
varying vec4 xyp_5_10_15;
varying vec4 xyp_6_7_8;
varying vec4 xyp_9_14_9;
varying vec4 xyp_11_12_13;
varying vec4 xyp_16_17_18;
varying vec4 xyp_21_22_23;

// Inequation coefficients for interpolation
const vec4 Ai  = vec4( 1.0, -1.0, -1.0,  1.0);
const vec4 B45 = vec4( 1.0,  1.0, -1.0, -1.0);
const vec4 C45 = vec4( 1.5,  0.5, -0.5,  0.5);
const vec4 B15 = vec4( 0.5,  2.0, -0.5, -2.0);
const vec4 C15 = vec4( 1.0,  1.0, -0.5,  0.0);
const vec4 B60 = vec4( 2.0,  0.5, -2.0, -0.5);
const vec4 C60 = vec4( 2.0,  0.0, -1.0,  0.5);

const vec4 S45 = vec4(0.2, 0.2, 0.2, 0.2);
const vec4 S15 = vec4(0.1, 0.2, 0.1, 0.2);
const vec4 S60 = S15.yxwz;

const vec4 M45 = vec4(0.4, 0.4, 0.4, 0.4);
const vec4 M15 = vec4(0.2, 0.4, 0.2, 0.4);
const vec4 M60 = M15.yxwz;
const vec4 shift = vec4(0.2);

const float coef = 2.0;
// Threshold for if luminance values are "equal"
const vec4 threshold = vec4(20.0 / 48.0);

// Conversion from RGB to Luminance
const vec3 lum = vec3(0.2126, 0.7152, 0.0722);

bvec4 _and_(bvec4 A, bvec4 B) {
    return bvec4(A.x && B.x, A.y && B.y, A.z && B.z, A.w && B.w);
}

bvec4 _or_(bvec4 A, bvec4 B) {
    return bvec4(A.x || B.x, A.y || B.y, A.z || B.z, A.w || B.w);
}

vec4 lum_to(vec3 v0, vec3 v1, vec3 v2, vec3 v3) {
    return vec4(
    dot(lum, v0),
    dot(lum, v1),
    dot(lum, v2),
    dot(lum, v3));
}

vec4 lum_df(vec4 A, vec4 B) {
    return abs(A - B);
}

bvec4 lum_eq(vec4 A, vec4 B) {
    return lessThan(lum_df(A, B), threshold);
}

vec4 lum_wd(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h) {
    return lum_df(a, b) + lum_df(a, c) + lum_df(d, e) + lum_df(d, f) + 4.0 * lum_df(g, h);
}

void main() {
/*
    Mask for algorhithm
    |-----+-----+-----+-----+-----+
    |     |  1  |  2  |  3  |     |
    |-----+-----+-----+-----+-----+
    |  5  |  6  |  7  |  8  |  9  |
    |-----+-----+-----+-----+-----+
    | 10  | 11  | 12  | 13  | 14  |
    +-----+-----+-----+-----+-----+
    | 15  | 16  | 17  | 18  | 19  |
    +-----+-----+-----+-----+-----+
    |     | 21  | 22  | 23  |     |
    +-----+-----+-----+-----+-----+
*/

// Store mask values
    vec3 P1  = texture2D(map_diffuse, xyp_1_2_3.xw   ).rgb;
    vec3 P2  = texture2D(map_diffuse, xyp_1_2_3.yw   ).rgb;
    vec3 P3  = texture2D(map_diffuse, xyp_1_2_3.zw   ).rgb;

    vec3 P6  = texture2D(map_diffuse, xyp_6_7_8.xw   ).rgb;
    vec3 P7  = texture2D(map_diffuse, xyp_6_7_8.yw   ).rgb;
    vec3 P8  = texture2D(map_diffuse, xyp_6_7_8.zw   ).rgb;

    vec3 P11 = texture2D(map_diffuse, xyp_11_12_13.xw).rgb;
    vec3 P12 = texture2D(map_diffuse, xyp_11_12_13.yw).rgb;
    vec3 P13 = texture2D(map_diffuse, xyp_11_12_13.zw).rgb;

    vec3 P16 = texture2D(map_diffuse, xyp_16_17_18.xw).rgb;
    vec3 P17 = texture2D(map_diffuse, xyp_16_17_18.yw).rgb;
    vec3 P18 = texture2D(map_diffuse, xyp_16_17_18.zw).rgb;

    vec3 P21 = texture2D(map_diffuse, xyp_21_22_23.xw).rgb;
    vec3 P22 = texture2D(map_diffuse, xyp_21_22_23.yw).rgb;
    vec3 P23 = texture2D(map_diffuse, xyp_21_22_23.zw).rgb;

    vec3 P5  = texture2D(map_diffuse, xyp_5_10_15.xy ).rgb;
    vec3 P10 = texture2D(map_diffuse, xyp_5_10_15.xz ).rgb;
    vec3 P15 = texture2D(map_diffuse, xyp_5_10_15.xw ).rgb;

    vec3 P9  = texture2D(map_diffuse, xyp_9_14_9.xy  ).rgb;
    vec3 P14 = texture2D(map_diffuse, xyp_9_14_9.xz  ).rgb;
    vec3 P19 = texture2D(map_diffuse, xyp_9_14_9.xw  ).rgb;

// Store luminance values of each point 
    vec4 p7  = lum_to(P7,  P11, P17, P13);
    vec4 p8  = lum_to(P8,  P6,  P16, P18);
    vec4 p11 = p7.yzwx;                      // P11, P17, P13, P7
    vec4 p12 = lum_to(P12, P12, P12, P12);
    vec4 p13 = p7.wxyz;                      // P13, P7,  P11, P17
    vec4 p14 = lum_to(P14, P2,  P10, P22);
    vec4 p16 = p8.zwxy;                      // P16, P18, P8,  P6
    vec4 p17 = p7.zwxy;                      // P11, P17, P13, P7
    vec4 p18 = p8.wxyz;                      // P18, P8,  P6,  P16
    vec4 p19 = lum_to(P19, P3,  P5,  P21);
    vec4 p22 = p14.wxyz;                     // P22, P14, P2,  P10
    vec4 p23 = lum_to(P23, P9,  P1,  P15);

    vec2 fp = fract(tc * texture_size);

    vec4 t45   = vec4(Ai * fp.y + B45 * fp.x);
    vec4 t15   = vec4(Ai * fp.y + B15 * fp.x);
    vec4 t60   = vec4(Ai * fp.y + B60 * fp.x);

    bvec4 fx45 = greaterThan(t45, C45 - S45);
    bvec4 fx15 = greaterThan(t15, C15 - S15);
    bvec4 fx60 = greaterThan(t60, C60 - S60);
    bvec4 fxrn = greaterThan(t45, C45);

    vec4 ma45 = smoothstep(C45 - M45, C45 + M45, t45);
    vec4 ma15 = smoothstep(C15 - M15, C15 + M15, t15);
    vec4 ma60 = smoothstep(C60 - M60, C60 + M60, t60);
    vec4 marn = smoothstep(C45 - M45 + shift, C45 + M45 + shift, t45);

    vec4 e45   = lum_wd(p12, p8, p16, p18, p22, p14, p17, p13);
    vec4 econt = lum_wd(p17, p11, p23, p13, p7, p19, p12, p18);
    vec4 e15   = lum_df(p13, p16);
    vec4 e60   = lum_df(p8, p17);

    bvec4 r45_1   = _and_(notEqual(p12, p13), notEqual(p12, p17));
    bvec4 r45_2   = _and_(not(lum_eq(p13, p7)), not(lum_eq(p13, p8)));
    bvec4 r45_3   = _and_(not(lum_eq(p17, p11)), not(lum_eq(p17, p16)));
    bvec4 r45_4_1 = _and_(not(lum_eq(p13, p14)), not(lum_eq(p13, p19)));
    bvec4 r45_4_2 = _and_(not(lum_eq(p17, p22)), not(lum_eq(p17, p23)));
    bvec4 r45_4   = _and_(lum_eq(p12, p18), _or_(r45_4_1, r45_4_2));
    bvec4 r45_5   = _or_(lum_eq(p12, p16), lum_eq(p12, p8));
    bvec4 r45     = _and_(r45_1, _or_(_or_(_or_(r45_2, r45_3), r45_4), r45_5));
    bvec4 r15 = _and_(notEqual(p12, p16), notEqual(p11, p16));
    bvec4 r60 = _and_(notEqual(p12, p8), notEqual(p7, p8));

    bvec4 edr45 = _and_(lessThan(e45, econt), r45);
    bvec4 edrrn = lessThan(e45, econt);
    bvec4 edr15 = _and_(edr45, _and_(lessThanEqual(coef * e15, e60), r15));
    bvec4 edr60 = _and_(edr45, _and_(lessThanEqual(coef * e60, e15), r60));

    vec4 px = step(lum_df(p12, p17), lum_df(p12, p13));

    vec4 mac;
    mac.x = edr15.x && fx15.x ? ma15.x : edr60.x && fx60.x ? ma60.x : edr45.x && fx45.x ? ma45.x : edrrn.x && fxrn.x ? marn.x : 0.0;
    mac.y = edr15.y && fx15.y ? ma15.y : edr60.y && fx60.y ? ma60.y : edr45.y && fx45.y ? ma45.y : edrrn.y && fxrn.y ? marn.y : 0.0;
    mac.z = edr15.z && fx15.z ? ma15.z : edr60.z && fx60.z ? ma60.z : edr45.z && fx45.z ? ma45.z : edrrn.z && fxrn.z ? marn.z : 0.0;
    mac.w = edr15.w && fx15.w ? ma15.w : edr60.w && fx60.w ? ma60.w : edr45.w && fx45.w ? ma45.w : edrrn.w && fxrn.w ? marn.w : 0.0;

    vec3 res = mix(P12, mix(P13, P17, px.x), mac.x);
    res = mix(res, mix(P7, P13, px.y), mac.y);
    res = mix(res, mix(P11, P7, px.z), mac.z);
    res = mix(res, mix(P17, P11, px.w), mac.w);
    gl_FragColor = vec4(res, 1.0);
}
