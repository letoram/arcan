/* modified version of IQs 'Tunnel' 
 * from "Shader Toy" collection
 */

uniform int timestamp;
uniform vec2 display;

uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

const float speed = 0.8;

void main()
{
	vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / display.xy;
	vec2 uv;
	float time = speed * ( float(timestamp)  ) / 25.0;
	float r = pow( pow(p.x * p.x, 16.0) + pow(p.y * p.y, 16.0), 1.0/32.0);
	
	uv.x = 0.5 * time + 0.5 / r;
	uv.y = 1.0 * atan(p.y, p.x) / 3.14157;

	vec3 col = texture2D(map_diffuse, uv).xyz;
	gl_FragColor = vec4(col * r * r * r, obj_opacity);
}

