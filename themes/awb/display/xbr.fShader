/*
  Hyllian's (1..5)xBR(A..D) Shader

  Copyright (C) 2011/2012 Hyllian/Jararaca - sergiogdb@gmail.com
	Integration / Translation / Refactor - letoram@gmail.com
  
  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

  Incorporates some of the ideas from SABR shader. Thanks to Joshua Street.
*/

#version 120

uniform sampler2D map_diffuse;
uniform vec2 texture_size;
uniform float deltav;
uniform vec4 eq_threshold;
uniform float obj_opacity;

varying vec2 tc;

varying vec4 t1;
varying vec4 t2;
varying vec4 t3;
varying vec4 t4;
varying vec4 t5;
varying vec4 t6;
varying vec4 t7;

const float coef          = 2.0;
const float y_weight      = 48.0;
const float u_weight      = 7.0;
const float v_weight      = 6.0;
const mat3x3 yuv          = mat3x3(0.299, 0.587, 0.114, -0.169, -0.331, 0.499, 0.499, -0.418, -0.0813);
const mat3x3 yuv_weighted = mat3x3(y_weight*yuv[0], u_weight*yuv[1], v_weight*yuv[2]);

vec4 df(const vec4 A, const vec4 B)
{
	return vec4(abs(A-B));
}

float c_df(const vec3 c1, const vec3 c2)
{
	vec3 df = abs(c1 - c2);
	return df.r + df.g + df.b;
}

bvec4 eq(const vec4 A, const vec4 B)
{
	return lessThan(df(A, B), eq_threshold);
}

bvec4 eq2(const vec4 A, const vec4 B)
{
	return lessThan(df(A, B), vec4(2.0));
}

bvec4 and(const bvec4 A, const bvec4 B)
{
	return bvec4(A.x && B.x, A.y && B.y, A.z && B.z, A.w && B.w);
}

bvec4 or(const bvec4 A, const bvec4 B)
{
	return bvec4(A.x || B.x, A.y || B.y, A.z || B.z, A.w || B.w);
}

vec4 weighted_distance(vec4 a, vec4 b, vec4 c, vec4 d, vec4 e, vec4 f, vec4 g, vec4 h)
{
	return (df(a,b) + df(a,c) + df(d,e) + df(d,f) + 4.0*df(g,h));
}

void main()
{
	bvec4 edr, edr_left, edr_up, px; // px = pixel, edr = edge detection rule
	bvec4 interp_restriction_lv1, interp_restriction_lv2_left, interp_restriction_lv2_up;
	bvec4 nc, nc30, nc60, nc45; // new_color
	vec4 fx, fx_left, fx_up, final_fx; // inequations of straight lines.
	vec3 res1, res2, pix1, pix2;
	float blend1, blend2;
	vec4 delta = vec4(deltav);

#ifdef LEVEL_3A
	bvec4 interp_restriction_lv3_left, interp_restriction_lv3_up, edr3_left, edr3_up;
	bvec4 nc15, nc75;
	vec4 fx3_left, fx3_up;
#endif
	
	vec2 fp = fract(tc * texture_size);

	vec3 A1 = texture2D(map_diffuse, t1.xw).rgb;
	vec3 B1 = texture2D(map_diffuse, t1.yw).rgb;
	vec3 C1 = texture2D(map_diffuse, t1.zw).rgb;

	vec3 A = texture2D(map_diffuse, t2.xw).rgb;
	vec3 B = texture2D(map_diffuse, t2.yw).rgb;
	vec3 C = texture2D(map_diffuse, t2.zw).rgb;

	vec3 D = texture2D(map_diffuse, t3.xw).rgb;
	vec3 E = texture2D(map_diffuse, t3.yw).rgb;
	vec3 F = texture2D(map_diffuse, t3.zw).rgb;

	vec3 G = texture2D(map_diffuse, t4.xw).rgb;
	vec3 H = texture2D(map_diffuse, t4.yw).rgb;
	vec3 I = texture2D(map_diffuse, t4.zw).rgb;

	vec3 G5 = texture2D(map_diffuse, t5.xw).rgb;
	vec3 H5 = texture2D(map_diffuse, t5.yw).rgb;
	vec3 I5 = texture2D(map_diffuse, t5.zw).rgb;

	vec3 A0 = texture2D(map_diffuse, t6.xy).rgb;
	vec3 D0 = texture2D(map_diffuse, t6.xz).rgb;
	vec3 G0 = texture2D(map_diffuse, t6.xw).rgb;

	vec3 C4 = texture2D(map_diffuse, t7.xy).rgb;
	vec3 F4 = texture2D(map_diffuse, t7.xz).rgb;
	vec3 I4 = texture2D(map_diffuse, t7.xw).rgb;

	vec4 b = yuv_weighted[0] * mat4x3(B, D, H, F);
	vec4 c = yuv_weighted[0] * mat4x3(C, A, G, I);
	vec4 e = yuv_weighted[0] * mat4x3(E, E, E, E);
	vec4 d = b.yzwx;
	vec4 f = b.wxyz;
	vec4 g = c.zwxy;
	vec4 h = b.zwxy;
	vec4 i = c.wxyz;

	vec4 i4 = yuv_weighted[0] * mat4x3(I4, C1, A0, G5);
	vec4 i5 = yuv_weighted[0] * mat4x3(I5, C4, A1, G0);
	vec4 h5 = yuv_weighted[0] * mat4x3(H5, F4, B1, D0);
	vec4 f4 = h5.yzwx;
	
#ifdef LEVEL_3A
	vec4 c1 = i4.yzwx;
	vec4 g0 = i5.wxyz;
	vec4 b1 = h5.zwxy;
	vec4 d0 = h5.wxyz;
#endif

	vec4 Ao = vec4( 1.0, -1.0, -1.0,  1.0 );
	vec4 Bo = vec4( 1.0,  1.0, -1.0, -1.0 );
	vec4 Co = vec4( 1.5,  0.5, -0.5,  0.5 );
	vec4 Ax = vec4( 1.0, -1.0, -1.0,  1.0 );
	vec4 Bx = vec4( 0.5,  2.0, -0.5, -2.0 );
	vec4 Cx = vec4( 1.0,  1.0, -0.5,  0.0 );
	vec4 Ay = vec4( 1.0, -1.0, -1.0,  1.0 );
	vec4 By = vec4( 2.0,  0.5, -2.0, -0.5 );
	vec4 Cy = vec4( 2.0,  0.0, -1.0,  0.5 );

#ifdef LEVEL_3A
	vec4 Az = vec4( 6.0, -2.0, -6.0,  2.0 );
	vec4 Bz = vec4( 2.0,  6.0, -2.0, -6.0 );
	vec4 Cz = vec4( 5.0,  3.0, -3.0, -1.0 );
	vec4 Aw = vec4( 2.0, -6.0, -2.0,  6.0 );
	vec4 Bw = vec4( 6.0,  2.0, -6.0, -2.0 );
	vec4 Cw = vec4( 5.0, -1.0, -3.0,  3.0 );	
#endif
	
	// These inequations define the line below which interpolation occurs.
	fx      = (Ao*fp.y+Bo*fp.x);
	fx_left = (Ax*fp.y+Bx*fp.x);
	fx_up   = (Ay*fp.y+By*fp.x);
	
#ifdef METHOD_A
    interp_restriction_lv1      = and(notEqual(e,f), notEqual(e,h));
#endif

#ifdef METHOD_B
		bvec4 extexpr = or( or( or( and(not(eq(f,b)), not(eq(h,d))),
			and(and(eq(e,i), not(eq(f,i4))), not(eq(h, i5)))), eq(e,g)), eq(e,c));

		interp_restriction_lv1      = and( and(notEqual(e,f), notEqual(e,h)), extexpr );
#endif

#ifdef METHOD_C
	bvec4 extexpr = or( or( or( or(
		and(not(eq(f,b)), not(eq(f,c))),
		and(not(eq(h,d)), not(eq(h,g)))),
		and(eq(e,i), or(and(not(eq(f,f4)), not(eq(f,i4))), and(not(eq(h,h5)), not(eq(h,i5)))))
	), eq(e,g) ), eq(e, c));

	interp_restriction_lv1      = and( and(notEqual(e,f), notEqual(e,h)), extexpr );
#endif

#ifdef LEVEL_3A
	interp_restriction_lv3_left = and( eq2(g,g0), not(eq2(d0,g0)) );
	interp_restriction_lv3_up   = and( eq2(c,c1), not(eq2(b1,c1)) );

	bvec4 expra = and(notEqual(e, f), notEqual(e, h));
	bvec4 exprb = or(or(and(and(or(and(not(eq(f,b)), not(eq(h,d))), eq(e,i)), not(eq(f,i4))), not(eq(h, i5)) ), eq(e,g)), eq(e,c));
	bvec4 exprc = and(or(or(or(and(or(and(notEqual(f,f4), notEqual(f,i)), notEqual(h, h5)), 
		notEqual(h, i)), notEqual(h,g)), notEqual(f, c)), eq(b,c1)), eq(d,g0));

	interp_restriction_lv1 = and( and(expra, exprb), exprc);

	fx3_left = (Az * fp.y + Bz * fp.x);
	fx3_up   = (Aw * fp.y + Bw * fp.x);
#endif
	
	interp_restriction_lv2_left = and(notEqual(e, g), notEqual(d,g));
	interp_restriction_lv2_up   = and(notEqual(e, c), notEqual(b,c));

	vec4 fx45 = smoothstep(Co - delta, Co + delta, fx);
	vec4 fx30 = smoothstep(Cx - delta, Cx + delta, fx_left);
	vec4 fx60 = smoothstep(Cy - delta, Cy + delta, fx_up);

#ifdef LEVEL_3A
	vec4 fx15 = smoothstep(Cz - delta, Cz + delta, fx3_left);
	vec4 fx75 = smoothstep(Cw - delta, Cw + delta, fx3_up);
#endif
	
	edr      = and(
		lessThan(weighted_distance( e, c, g, i, h5, f4, h, f),
						 weighted_distance( h, d, i5, f, i4, b, e, i))
	, interp_restriction_lv1 );

	edr_left = and( lessThanEqual(coef * df(f,g), df(h,c) ), interp_restriction_lv2_left);
	edr_up   = and( greaterThanEqual( df(f,g), coef * df(h,c) ), interp_restriction_lv2_up);

	nc45 = and(edr, bvec4(fx45));
	nc30 = and(and(edr, edr_left), bvec4(fx30));
	nc60 = and(and(edr, edr_up  ), bvec4(fx60));

#ifdef LEVEL_3A
	edr3_left = interp_restriction_lv3_left;
	edr3_up   = interp_restriction_lv3_up;
	nc15 = and( and(edr, edr_left), and(edr3_left, bvec4(fx15)) );
	nc75 = and( and(edr, edr_up),   and(edr3_up,   bvec4(fx75)) );
	nc   =  or( nc75, or(nc15, or(or(nc30, nc60), nc45)));
	
	vec4 final15 = vec4(nc15) * fx15; 
	vec4 final75 = vec4(nc75) * fx75;
#else
	nc = or(or(nc30, nc60), nc45);
#endif
	
	px = lessThanEqual(df(e,f), df(e,h));

	vec4 final45 = vec4(nc45)*fx45;
	vec4 final30 = vec4(nc30)*fx30;
	vec4 final60 = vec4(nc60)*fx60;	 

#ifdef LEVEL_3A
	vec4 maximo = max(max(max(final15, final75), max(final30, final60)), final45);
#else
	vec4 maximo = max(max(final30, final60), final45);
#endif
	
	pix1 = texture2D(map_diffuse, tc).rgb;
	pix2 = pix1;
	blend1 = 1.0;
	blend2 = 1.0;

	if (nc.x) {pix1 = px.x ? F : H; blend1 = maximo.x;}
	else if (nc.y) {pix1 = px.y ? B : F; blend1 = maximo.y;}
	else if (nc.z) {pix1 = px.z ? D : B; blend1 = maximo.z;}
	else if (nc.w) {pix1 = px.w ? H : D; blend1 = maximo.w;}

	if (nc.w) {pix2 = px.w ? H : D; blend2 = maximo.w;}
	else if (nc.z) {pix2 = px.z ? D : B; blend2 = maximo.z;}
	else if (nc.y) {pix2 = px.y ? B : F; blend2 = maximo.y;}
	else if (nc.x) {pix2 = px.x ? F : H; blend2 = maximo.x;}

	res1 = mix(E, pix1, blend1);
	res2 = mix(E, pix2, blend2);

	vec3 res = mix(res1, res2, step(c_df(E, res1), c_df(E, res2)));
	gl_FragColor = vec4(res, obj_opacity);
}


