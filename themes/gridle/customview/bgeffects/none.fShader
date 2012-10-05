#version 120
varying vec2 texco;
uniform sampler2D map_diffuse;

void main()
{
	gl_FragColor = vec4( texture2D(map_diffuse, texco).rgb, 1.0 );
}
