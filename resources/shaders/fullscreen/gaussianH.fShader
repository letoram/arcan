uniform sampler2D map_diffuse;
uniform float obj_opacity;
uniform float blur;
uniform float ampl;

varying vec2 texco;

void main()
{
	vec4 sum = vec4(0.0);

	sum += texture2D(map_diffuse, vec2(texco.x - 4.0 * blur, texco.y)) * 0.05;
	sum += texture2D(map_diffuse, vec2(texco.x - 3.0 * blur, texco.y)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x - 2.0 * blur, texco.y)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x - 1.0 * blur, texco.y)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x - 0.0 * blur, texco.y)) * 0.16;
	sum += texture2D(map_diffuse, vec2(texco.x + 1.0 * blur, texco.y)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x + 2.0 * blur, texco.y)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x + 3.0 * blur, texco.y)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x + 4.0 * blur, texco.y)) * 0.05;

	gl_FragColor = vec4(sum.r * ampl, sum.g * ampl, sum.b* ampl, obj_opacity);
}
