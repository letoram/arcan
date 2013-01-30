/* modified version of IQs 'Tunnel' 
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

	float a = atan(p.y, p.x);
	float r = sqrt(dot(p, p));

	uv.x = 0.75 * time + 0.1 / r;
	uv.y = a / 3.14157;

	vec3 col = texture2D(map_diffuse, uv).xyz;
	gl_FragColor = vec4(col * r, obj_opacity);
}

