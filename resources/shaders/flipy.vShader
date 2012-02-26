uniform mat4 modelview;
uniform mat4 projection;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco = vec2(texcoord.s, 1.0 - texcoord.t);
	gl_Position = (projection * modelview) * vertex;
}
