uniform sampler2D map_diffuse;
uniform vec2 wnd;
uniform float obj_opacity;
varying vec2 texco;

/*
 * simple spectogram, adapted from guycooks reference at shadertoy 
 */

#define bars 32.0
#define bar_sz (1.0 / bars)
#define bar_gap (0.1 * bar_sz)

float h2rgb(float h){
	if (h < 0.0) h += 1.0;
	if (h < 0.166666) return 0.1 + 4.8 * h;
	if (h < 0.5) return 0.9;
	if (h < 0.66666) return 0.1 + 4.8 * (0.666666 - h);
	return 0.1;
}

vec3 i2c(float i){
	float h = 0.6666 - (i * 0.66666);
	return vec3(h2rgb(h + 0.33333), h2rgb(h), h2rgb(h - 0.33333));
}

void main()
{
	vec2 uv = vec2(1.0 - texco.s, 1.0 - texco.t);
	float start = floor(uv.x * bars) / bars;
	if (uv.x - start < bar_gap || uv.x > start + bar_sz - bar_gap){
		gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0);
		return;
	} 

	float intens = 0.0;
	for (float s = 0.0; s < bar_sz; s += bar_sz * 0.02){
		intens += texture2D(map_diffuse, vec2(start + s, 0.5)).g;
	}

	intens *= 0.02;
	intens = clamp(intens, 0.005, 1.0);
	
	float i = float(intens > uv.y);
	gl_FragColor = vec4(i2c(intens) * i, obj_opacity);
}
