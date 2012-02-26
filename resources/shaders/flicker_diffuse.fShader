uniform int timestamp;
uniform sampler2D map_diffuse;
varying vec2 texco;
	
void main(){
	vec4 fragcol = texture2D(map_diffuse, texco);

	if ( int( mod(float(timestamp), 256.0)) == 0)
		fragcol *= vec4(0.5, 0.5, 0.5, 1.0);

	gl_FragColor = fragcol;
}
