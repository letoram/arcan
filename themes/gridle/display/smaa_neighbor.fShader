/* regular colour output */
uniform sampler2D map_tu0; /* color texture */
uniform sampler2D map_tu1; /* blend texture */

uniform vec2 pixel_size;

varying vec4 offset[2];
varying vec2 texcoord;

int main()
{
    vec4 a;

    a.xz = texture2D(blendTex, texcoord).xz;
    a.y  = texture2D(blendTex, offset[1].zw).g;
    a.w  = texture2D(blendTex, offset[1].xy).a;

    if (dot(a, vec4(1.0, 1.0, 1.0, 1.0)) < 1e-5)
        gl_FragColor = texture2DLod(map_tu0, texcoord, 0.0);
    else {
        vec4 color = vec4(0.0, 0.0, 0.0, 0.0);
        vec2 offset;
        offset.x = a.a > a.b? a.a : -a.b;
        offset.y = a.g > a.r? a.g : -a.r;

        if (abs(offset.x) > abs(offset.y))
            offset.y = 0.0;
        else
            offset.x = 0.0;

        texcoord += offset * pixel_size;

        gl_FragColor = texture2DLod(map_tu1, texcoord, 0.0);
    }
}
