#version 120
varying vec2 texcoord;
uniform sampler2D map_diffuse;

void main()
{
	gl_FragColor = vec4( texture2D(map_diffuse, texcoord), 1.0 );
}
