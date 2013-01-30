/* modified version of IQs 'relief Tunnel' 
 * from "Shader Toy" collection
 */

uniform int timestamp;
uniform vec2 display;

uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

const float speed = 0.4;

void main()
{
	vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / display.xy;
	vec2 uv;
	float time = speed * ( float(timestamp)  ) / 25.0;

	float r = sqrt(dot(p, p));
	float a = atan(p.y, p.x) + 0.5 * sin(0.5 * r - 0.5 * time);
	float s = 0.5 + 0.5 * cos(7.0 * a);
	s = smoothstep(0.0, 1.0, s);
	s = smoothstep(0.0, 1.0, s);
	s = smoothstep(0.0, 1.0, s);
	s = smoothstep(0.0, 1.0, s);

	uv.x = time + 1.0 / (r + 0.2 * s); 
	uv.y = 3.0 * a / 3.14157;

	float w = (0.5 + 0.5 * s) * r * r;

	vec3 col = texture2D(map_diffuse, uv).xyz;
	float ao = 0.5 + 0.5 * cos(7.0 * a);
	ao = smoothstep(0.0, 0.4, ao) - smoothstep(0.4, 0.7, ao);
	ao = 1.0 - 0.5 * ao * r;

	gl_FragColor = vec4(col * w * ao, obj_opacity);
}

