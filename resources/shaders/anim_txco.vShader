uniform mat4 modelview;
uniform mat4 projection;
uniform int timestamp;

uniform vec2 speedfact;

attribute vec4 vertex;
attribute vec2 texcoord;

varying vec2 texco;

void main(void)
{
	texco.s = texcoord.s + fract(float(timestamp) / speedfact.x);
	texco.t = texcoord.t + fract(float(timestamp) / speedfact.y);
	
	gl_Position = (projection * modelview) * vertex;
}

