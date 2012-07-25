uniform sampler2D map_diffuse;

varyign vec2 texco;

const float blur = 1.0 / 512.0; /* this should really be set to the size of the blurtexture */

void main()
{
	vec4 sum = vec4(0.0);

	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - 4.0 * blur)) * 0.05;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - 3.0 * blur)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - 2.0 * blur)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - 1.0 * blur)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - 0.0 * blur)) * 0.16;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + 1.0 * blur)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + 2.0 * blur)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + 3.0 * blur)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + 4.0 * blur)) * 0.05;

	gl_FragColor = sum;	
}
