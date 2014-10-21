uniform vec3 wdiffuse;
uniform vec3 wambient;
uniform sampler2D map_diffuse;
	
varying vec3 lightdir;
varying vec3 fnormal;
varying vec2 txco;

void main() {
	vec4 color = vec4(wambient,1.0);
	vec4 txcol = texture2D(map_diffuse, txco);
	
	float ndl = max( dot(fnormal, lightdir), 0.0);
	if (ndl > 0.0){
		txcol += vec4(wdiffuse * ndl, 0.0);
	}
		
	gl_FragColor = txcol * color;
}
