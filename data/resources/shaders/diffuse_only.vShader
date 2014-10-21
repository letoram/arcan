uniform mat4 modelview;
uniform mat4 projection;
uniform bool flip_t;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco = texcoord;
	if (flip_t){
		texco.t = 1.0 - texco.t;
	}
	gl_Position = (projection * modelview) * vertex;
}
