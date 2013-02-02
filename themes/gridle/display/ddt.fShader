/* 
 * GLSL port of Hyllian's Data Dependent Triangulation Shader 
 * (C) 2011-2012 Hyllian / Jararaca - sergiogdb@gmail.com
 *
 * License: GPLv2
 */

#version 120

uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 loc;
varying vec2 v_xy;
varying vec2 v_zw;
varying vec2 texco;

void main(){
    vec2 pos = fract(loc) - vec2(0.5, 0.5);
    vec2 dir = sign(pos);

    vec2 g1 = dir * v_xy;
    vec2 g2 = dir * v_zw;

    vec3 a = texture2D(map_diffuse, texco          ).rgb;
    vec3 b = texture2D(map_diffuse, texco + g1     ).rgb;
    vec3 c = texture2D(map_diffuse, texco      + g2).rgb;
    vec3 d = texture2D(map_diffuse, texco + g1 + g2).rgb;

    vec3 rv = vec3(65536, 255, 1);

    float ra = dot(a, rv);
    float rb = dot(b, rv);
    float rc = dot(c, rv);
    float rd = dot(d, rv);

    float p = abs(pos.x);
    float q = abs(pos.y);

    float k = distance(pos, g1);
    float l = distance(pos, g2);

    if (abs(ra - rd) < abs(rb - rc)){
	if (k < l)
	    c = a + d - b;
	else
	    b = a + d - c;
    }
    else
	d = b + c - a;

    vec3 icol =
	(   (1.0 - p) * (1.0 - q) ) * a + 
	p * (1.0 - q) * b +
	((1 - p) * q) * c + 
	( p      * q) * d;

    gl_FragColor = vec4(icol, obj_opacity);
}
