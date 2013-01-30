/* modified version of Adrian Boeings "Metablob"
 * from "Shader Toy" collection
 */

uniform int timestamp;
uniform vec2 display;

uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

#define speed 0.5
#define timestep 25.0

#define area1 8.0
#define area2 16.0
#define falloff 0.4

void main()
{
    vec2 p = -1.0 + 2.0 * gl_FragCoord.xy / display.xy;
    float time = speed * ( float(timestamp)  ) / timestep;

/* oscillate light 1 */
    vec2 move1;
    move1.x = cos(time)*0.4;
    move1.y = sin(time*1.5)*0.8;

/* oscillate light 2 */
    vec2 move2;
    move2.x = cos(time*2.0)*0.4;
    move2.y = sin(time*3.0)*0.4;
  
    float r1 =(dot(p-move1,p-move1))*area1;
    float r2 =(dot(p+move2,p+move2))*area2;

    float metaball = 2.0 * (1.0/r1 + 1.0/r2);
    float col = falloff * metaball; 

    gl_FragColor = vec4(col, col, col, obj_opacity) * texture2D(map_diffuse, texco);
}
