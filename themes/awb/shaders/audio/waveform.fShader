uniform sampler2D map_diffuse;
uniform vec2 wnd;
uniform float obj_opacity;

varying vec2 texco;

/* 
 * simple waveform example 
 */
void main()
{
	vec2 uv    = texco;  
	float wave = texture2D(map_diffuse, vec2(uv.x, 0.75) ).r;
	vec3 col = vec3(0.0);
	col += smoothstep(0.0, 0.15, abs(wave - uv.y));
	gl_FragColor = vec4(vec3(1.0) - col, obj_opacity);
}
