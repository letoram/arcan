uniform vec2 pixel_size;
uniform mat4 projection;
uniform mat4 modelview;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;
varying vec2 pixcoord;
varying vec4 offset[3];

void main()
{
    texco = texcoord;

    offset[0] = texcoord.xyxy + pixel_size.xyxy * vec4(-0.25, -0.125, 1.25, -0.125);
    offset[1] = texcoord.xyxy + pixel_size.xyxy * vec4(-0.125, -0.25, -0.125, 1.25);
    offset[2] = vec4(offset[0].xz, offset[1].yw) +
                vec4(-2.0, 2.0, -2.0, 2.0) *
                pixel_size.xxyy * float(16);

    pixcoord = texcoord / pixel_size;
    gl_Position = ( (projection * modelview) * vertex );
}
