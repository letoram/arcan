/* 
 * GLSL port of Hyllian's Data Dependent Triangulation Shader 
 * (C) 2011-2012 Hyllian / Jararaca - sergiogdb@gmail.com
 *
 * License: GPLv2
 */

#version 120

uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;
varying vec2 loc;

varying vec4 t1;
varying vec4 t2;
varying vec4 t3;
varying vec4 t4;
varying vec4 t5;
varying vec4 t6;
varying vec4 t7;

const float coef = 2.0;

const float yw     = 48.0;
const float uw     = 7.0;
const float vw     = 6.0;
const mat3x3 yuv   = mat3x3(0.299, 0.587, 0.114, -0.169, -0.331, 0.499, 0.499, -0.418, -0.0813);
const mat3x3 yuv_w = mat3x3(yw * yuv[0], uw * yuv[1], vw * yuv[2]);
const vec4 eq_threshold = vec4(15.0);

#ifdef SCALEF2
const vec4  delta  = vec4(0.5);
#endif

#ifdef SCALEF3
const vec4 delta   = vec4(0.4);
#endif

#ifdef SCALEF4
const vec4 delta   = vec4(0.3);
#endif

#ifdef SCALEF5
const vec4 delta  = vec4(0.2);
#endif

vec4 df(const vec4 a, const vec4 b)
{
    return vec4( abs(a - b) );
}

float h_df(const vec3 c1, const vec3 c2)
{
    vec3 ldf = abs(c1 - c2);
    return ldf.r + ldf.g + ldf.b;
}

bvec4 b_eq(const vec4 a, const vec4 b)
{
    vec4   tf = df(a, b);
    bvec4 res = lessThan(tf, eq_threshold);
    return res;
}

vec4 wght_dist(const vec4 a, const vec4 b, const vec4 c, const vec4 d, const vec4 e, const vec4 f, const vec4 g, const vec4 h)
{
    return
	df(a,b) + df(a,c) +
	df(d,e) + df(d,f) +
	4.0 * df(g,h);
}

void main()
{
    bvec4 edr, edr_left, edr_up, px;
    bvec4 interp_restr_lv1, interp_restr_lv2_left, interp_restr_lv2_up;
    bvec4 nc, nc30, nc60, nc45;

    vec4 fx, fx_left, fx_up, fx_final;
    vec3 res1, res2, pix1, pix2;

    float blend1, blend2;

    vec2 fp = fract(loc);

    vec3 A1 = texture2D(map_diffuse, t1.xw).rgb;
    vec3 B1 = texture2D(map_diffuse, t1.yw).rgb;
    vec3 C1 = texture2D(map_diffuse, t1.zw).rgb;

    vec3 A  = texture2D(map_diffuse, t2.xw).rgb;
    vec3 B  = texture2D(map_diffuse, t2.yw).rgb;
    vec3 C  = texture2D(map_diffuse, t2.zw).rgb;

    vec3 D  = texture2D(map_diffuse, t3.xw).rgb;
    vec3 E  = texture2D(map_diffuse, t3.yw).rgb;
    vec3 F  = texture2D(map_diffuse, t3.zw).rgb;

    vec3 G  = texture2D(map_diffuse, t4.xw).rgb;
    vec3 H  = texture2D(map_diffuse, t4.yw).rgb;
    vec3 I  = texture2D(map_diffuse, t4.zw).rgb;

    vec3 G5 = texture2D(map_diffuse, t5.xw).rgb;
    vec3 H5 = texture2D(map_diffuse, t5.yw).rgb;
    vec3 I5 = texture2D(map_diffuse, t5.zw).rgb;

    vec3 A0 = texture2D(map_diffuse, t6.xw).rgb;
    vec3 D0 = texture2D(map_diffuse, t6.yw).rgb;
    vec3 G0 = texture2D(map_diffuse, t6.zw).rgb;

    vec3 C4 = texture2D(map_diffuse, t7.xw).rgb;
    vec3 F4 = texture2D(map_diffuse, t7.yw).rgb;
    vec3 I4 = texture2D(map_diffuse, t7.zw).rgb;

    vec4 b = yuv_w[0] * mat4x3(B, D, H, F);
    vec4 c = yuv_w[0] * mat4x3(C, A, G, I);
    vec4 e = yuv_w[0] * mat4x3(E, E, E, E);
    vec4 d = b.yzwx;
    vec4 f = b.wxyz;
    vec4 g = c.zwxy;
    vec4 h = b.zwxy;
    vec4 i = c.wxyz;

    vec4 i4 = yuv_w[0] * mat4x3(I4, C1, A0, G5);
    vec4 i5 = yuv_w[0] * mat4x3(I5, C4, A1, G0);
    vec4 h5 = yuv_w[0] * mat4x3(H5, F4, B1, D0);
    vec4 f4 = h5.yzwx;

    vec4 Ao = vec4( 1.0, -1.0, -1.0, 1.0 );
    vec4 Bo = vec4( 1.0,  1.0, -1.0,-1.0 );
    vec4 Co = vec4( 1.5,  0.5, -0.5, 0.5 );
    vec4 Ax = vec4( 1.0, -1.0, -1.0, 1.0 );
    vec4 Bx = vec4( 0.5,  2.0, -0.5,-2.0 );
    vec4 Cx = vec4( 1.0,  1.0, -0.5, 0.0 );
    vec4 Ay = vec4( 1.0, -1.0, -1.0, 1.0 );
    vec4 By = vec4( 2.0,  0.5, -2.0,-0.5 );
    vec4 Cy = vec4( 2.0,  0.0, -1.0, 0.5 );

    fx      = Ao * fp.y + Bo * fp.x;
    fx_left = Ax * fp.y + Bx * fp.x;
    fx_up   = Ay * fp.y + By * fp.x;

#ifdef METHOD_A
    interp_restr_lv1      = notEqual(e,f) && notEqual(e,h);
#endif

#ifdef METHOD_B
    interp_restr_lv1      = notEqual(e,f) && notEqual(e,h) && 
	( !b_eq(f,b) && !b_eq(h,d) || b_eq(e,i) && !b_eq(f,i4) && !b_eq(h,i5) || b_eq(e,g) || b_eq(e,c) );
#endif

#ifdef METHOD_C
    interp_restr_lv1      = notEqual(e,f) && notEqual(e,h) &&
	( !b_eq(f,b) && !b_eq(f,c) || !b_eq(h,d) && !b_eq(h,g) || b_eq(e,i) && (!b_eq(f,f4) && !b_eq(f,i4) || !b_eq(h,h5) && !b_eq(h,i5)) || b_eq(e,g) || b_eq(e,c));
#endif

    interp_restr_lv2_left = notEqual(e,g) && notEqual(d,g);
    interp_restr_lv2_up   = notEqual(e,c) && notEqual(b,c);

    vec4 fx45 = smoothstep(Co - delta, Co + delta, fx);
    vec4 fx30 = smoothstep(Cx - delta, Cx + delta, fx_left);
    vec4 fx60 = smoothstep(Cy - delta, Cy + delta, fx_up);

    edr      = lessThan(wght_dist(e, c, g, i, h5, f4, h, f), wght_dist( h, d, i5, f, i4, b, e, i)) && interp_restr_lv1;

    edr_left = lessThanEqual(coef * df(f, g), df(h, c)) && interp_restr_lv2_left;
    edr_up   = greaterThanEqual(df(f,g), coef * df(h, c) ) && interp_restr_lv2_up;

    nc45 = ( edr &&             bvec4(fx45));
    nc30 = ( edr && edr_left && bvec4(fx30));
    nc60 = ( edr && edr_up   && bvec4(fx60));

    px = lessThanEqual(df(f,g), df(e, h));

    nc = (nc30 || nc60 || nc45);

    vec4 final45 = vec4(nc45) * fx45;
    vec4 final30 = vec4(nc30) * fx30;
    vec4 final60 = vec4(nc60) * fx60;

    vec4 maximo = max(max(final30, final60), final45);

    if (nc.x){
	pix1 = px.x ? F : H;
	blend1 = maximo.x;
    }
    else if (nc.y){
	pix1 = px.y ? B : F; 
	blend1 = maximo.y;
    }
    else if (nc.z){
	pix1 = px.z ? D : B; 
	blend1 = maximo.z;
    }
    else if (nc.w){
	pix1 = px.w ? H : D;
	 blend1 = maximo.w;
    }

    if (nc.w){
	pix2 = px.w ? H : D;
	blend2 = maximo.w;
    }
    else if (nc.z){
	pix2 = px.z ? D : B; 
	blend2 = maximo.z;
    }
    else if (nc.y){
	pix2 = px.y ? B : F;
	blend2 = maximo.y;
    }
    else if (nc.x){
	pix2 = px.x ? F : H;
	blend2 = maximo.x;
    }

    res1 = mix(E, pix1, blend1);
    res2 = mix(E, pix2, blend2);

    vec3 der1 = abs(E - res1);
    vec3 der2 = abs(E - res2);

    vec3 res = mix(res1, res2, step( der1.r + der1.g + der1.b, der2.r + der2.g + der2.b ));
    gl_FragColor = vec4(res, obj_opacity);
}
