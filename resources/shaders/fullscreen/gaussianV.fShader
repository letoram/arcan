uniform sampler2D map_diffuse;
uniform float obj_opacity;
uniform float blur;
uniform float ampl;

varying vec2 texco;

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

	gl_FragColor = vec4(sum.r * ampl, sum.g * ampl, sum.b * ampl, obj_opacity);
}
