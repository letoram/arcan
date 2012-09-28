#version 120

/* filled in by customview loader */
uniform vec2 display;

/* filled in by arcan_shdrmgmt.c */
uniform int timestamp;
uniform float fract_timestamp;
uniform sampler2D map_diffuse;

#define speed 0.25

void main()
{
	vec2 pos = -1.0 + 2.0 * gl_FragCoord.xy / display.xy;
	float tv = float(timestamp) / 25.0;

	float at = atan(pos.y, pos.x);
	float rt = sqrt(dot(pos, pos));

	vec2 uv = vec2(speed * tv, at / 3.1457);
	vec3 col = texture2D(map_diffuse, uv).xyz * rt;

	gl_FragColor = vec4( col, 1.0 );
}
