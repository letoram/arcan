/* pretty much identical to the smaa_edge,
 * with the only change of tracking one less offset */

uniform vec2 pixel_size; /* 1/Width, 1/Height */

uniform mat4 modelview;
uniform mat4 projection;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;
varying vec4 offset[2];

void main()
{
    texco = texcoord;

    offset[0] = texcoord.xyxy + pixel_size.xyxy * vec4(-1.0, 0.0, 0.0, -1.0);
    offset[1] = texcoord.xyxy + pixel_size.xyxy * vec4( 1.0, 0.0, 0.0,  1.0);

    gl_Position = (projection * modelview) * vertex;
}
