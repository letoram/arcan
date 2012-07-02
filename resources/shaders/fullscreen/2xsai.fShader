uniform sampler2D map_diffuse;
uniform vec2 rubyTextureSize;

varying vec2 texco;

void main()
{
	vec2 ul, ur, dl, dr;
	float dx = pow(rubyTextureSize.x, -1.0) * 0.25;
	float dy = pow(rubyTextureSize.y, -1.0) * 0.25;
	vec3 dt = vec3(1.0, 1.0, 1.0);

	ul = texco + vec2(-dx, -dy);
	ur = texco + vec2(dx, -dy);
	dl = texco + vec2(-dx, dy);
	dr = texco + vec2(dx, dy);

	vec3 c00 = texture2D(map_diffuse, ul).xyz;
	vec3 c20 = texture2D(map_diffuse, ur).xyz;
	vec3 c02 = texture2D(map_diffuse, dl).xyz;
	vec3 c22 = texture2D(map_diffuse, dr).xyz;

	float m1 = dot( abs( c00-c22 ), dt) + 0.001;
	float m2 = dot( abs( c02-c20 ), dt) + 0.001;

	gl_FragColor = vec4((m1 * (c02 + c20) + m2 * (c22 + c00)) / (2.0 * (m1 + m2)), 1.0);
}

