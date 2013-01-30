/* modified version of IQs 'Fly' 
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

	float an = time * 0.25;
	float x = p.x * cos(an) - p.y * sin(an);
	float y = p.y * sin(an) + p.y * cos(an);

	uv.x = 0.25 * x / abs(y);
	uv.y = 0.20 * time + 0.25 / abs(y);

	gl_FragColor = vec4(texture2D(map_diffuse, uv).xyz * y * y, 1.0);
}

