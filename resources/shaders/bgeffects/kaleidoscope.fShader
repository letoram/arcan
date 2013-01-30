/* modified version of IQs 'Kaleidoscope' 
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

	uv.x = 7.0 * a / 3.14157;
	uv.y = -time + sin(7.0 * r + time) + 0.7 * cos(time + 0.7 * a);
	
	float w = 0.5 + 0.5 * (sin(time + 7.0 * r) + 0.7 * cos(time + 7.0*a));
	
	vec3 col = texture2D(map_diffuse, uv * 0.5).xyz;
	gl_FragColor = vec4(col * w, obj_opacity);

}

