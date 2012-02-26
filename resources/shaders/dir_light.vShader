uniform mat4 modelview;
uniform mat4 projection;
uniform vec3 wlightdir;
	
attribute vec4 vertex;
attribute vec3 normal;
attribute vec2 texcoord;

varying vec3 lightdir;
varying vec2 txco;
varying vec3 fnormal;
	
void main(){
	fnormal = vec3(modelview * vec4(normal, 0.0));
	lightdir = normalize(wlightdir);

	txco = texcoord;
	gl_Position = (projection * modelview) * vertex;
}
