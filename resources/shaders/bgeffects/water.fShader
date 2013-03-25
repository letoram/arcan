/* modified version of Viktor Korsuns Water,
 * from "Shader Toy" compilation */

uniform sampler2D map_diffuse;
uniform float obj_opacity;

uniform int timestamp;

uniform vec2 display;

varying vec2 texco;

const float PI = 3.1415926535897932;
const float speed   = 0.2;
const float speed_x = 0.3;
const float speed_y = 0.3;

const float intensity = 3.0;
const float frequency = 4.0;
const int steps = 8;
const int angle = 7;

const float delta   = 20.0;
const float intence = 400.0;
const float emboss  = 0.3;

float col(vec2 coord, float time)
{
    float delta_theta = 2.0 * PI / float(angle);
    float col = 0.0;
    float theta = 0.0;

    for (int i = 0; i < steps; i++){
	vec2 adjc = coord;
	theta = delta_theta * float(i);
	adjc.x += cos(theta)* time * speed + time * speed_x;
	adjc.y -= sin(theta)* time * speed - time * speed_y;
	col = col + cos( (adjc.x*cos(theta) - 
	    adjc.y*sin(theta))*frequency)*intensity;
    }

    return cos(col);
}

void main(void)
{
    float time = 0.5 * ( float(timestamp)  ) / 25.0;
    vec2 p = gl_FragCoord.xy / display.xy;
    vec2 c1 = p;
    vec2 c2 = p;

    float cc1 = col(c1, time);

    c2.x += display.x / delta;
    float dx = emboss * (cc1-col(c2, time)) / delta;

    c2.x = p.x;
    c2.y += display.y / delta;
    float dy = emboss * (cc1-col(c2, time)) / delta;

    c1.x += dx;
    c1.y = -(c1.y+dy);

    float alpha = 1.+dot(dx,dy)*intence*obj_opacity;
    gl_FragColor = texture2D(map_diffuse,texco)*(alpha);
}
