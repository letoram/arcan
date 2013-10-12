uniform sampler2D map_diffuse;
uniform vec2 wnd;
uniform float obj_opacity;
uniform int timestamp;

varying vec2 texco;

/* 
 * soundsinuswave by eitraz@shadertoy
 */

const float waves = 8.0;

void main()
{
	vec2 uv  = -1.0 + 2.0 * (vec2(1.0 - texco.s, 1.0 - texco.t));
	vec3 col = vec3(0.0);
	float time = float(timestamp) * 0.5;

	for (float i = 0.0; i < waves + 1.0; i++){
		float freq = texture2D(map_diffuse, vec2(i / waves, 0.75)).r * 7.0;
		vec2 p = vec2(uv);
		p.x += i * 0.04 + freq * 0.03;
		p.y += sin(p.x * 10.0 + time) * cos(p.x * 2.0) *
			freq * 0.2 * ((i + 1.0) / waves);
		float intens = abs(0.01 / p.y) * clamp(freq, 0.35, 2.0);
		col += vec3(1.0 * intens * (i / 5.0), 0.5 * intens, 1.75 * intens) 
			* (3.0 / waves);
	}

	gl_FragColor = vec4(col, obj_opacity); 
}
