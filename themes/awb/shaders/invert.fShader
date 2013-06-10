uniform texture2D map_diffuse;
varying vec2 texco;

int main()
{
	vec4 col = texture2D(map_diffuse, texco);
	gl_FragColor(1.0 - col.r, 1.0 - col.g, 1.0 - col.b, col.a);
}
