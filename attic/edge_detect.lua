--
-- Simple edge detection example
-- Best result is probably combining
-- with a gaussian smoothing in beforehand
-- to cut down on noise.
--
-- String.format in width, height, magnitude, lowerb, upperb
--
local edt = [[
uniform sampler2D map_diffuse;
varying vec2 texco;

void main()
{
	float dx = 1.0 / %f; /* populate with width */
  float dy = 1.0 / %f; /* populate with height */
	float s = texco.s;
	float t = texco.t;

	float p[9];
  float delta;

/* populate buffer with neighbour samples,
 * assuming 8bit packed in RGBA texture */

	p[0] = texture2D(map_diffuse, vec2(s - dx, t - dy)).r;
	p[1] = texture2D(map_diffuse, vec2(s     , t - dy)).r;
	p[2] = texture2D(map_diffuse, vec2(s + dx, t - dy)).r;
	p[3] = texture2D(map_diffuse, vec2(s - dx, t     )).r;
	p[4] = texture2D(map_diffuse, vec2(s     , t     )).r;
	p[5] = texture2D(map_diffuse, vec2(s + dx, t     )).r;
	p[6] = texture2D(map_diffuse, vec2(s - dx, t + dy)).r;
	p[7] = texture2D(map_diffuse, vec2(s     , t + dy)).r;
	p[8] = texture2D(map_diffuse, vec2(s + dx, t + dy)).r;

	delta = (abs(p[1]-p[7])+
           abs(p[5]-p[3])+
           abs(p[0]-p[8])+
           abs(p[2]-p[6]))/ 4.0;

	delta = clamp(%f * delta, 0.0, 1.0);

	if (delta < %f)
		delta = 0.0;

	if (delta > %f)
		delta = 1.0;

	gl_FragColor = vec4( delta, delta, delta, 1.0 );
}
]];

local gauss_h = [[
uniform sampler2D map_diffuse;
varying vec2 texco;

void main()
{
	vec4 sum = vec4(0.0);
	float ampl = %f;
	float dx = 1.0 / %f; /* populate with width */

	sum += texture2D(map_diffuse, vec2(texco.x - (4.0 * dx), texco.y)) * 0.05;
	sum += texture2D(map_diffuse, vec2(texco.x - (3.0 * dx), texco.y)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x - (2.0 * dx), texco.y)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x - (1.0 * dx), texco.y)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x - (0.0     ), texco.y)) * 0.16;
	sum += texture2D(map_diffuse, vec2(texco.x + (1.0 * dx), texco.y)) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x + (2.0 * dx), texco.y)) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x + (3.0 * dx), texco.y)) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x + (4.0 * dx), texco.y)) * 0.05;

	gl_FragColor = vec4(sum.r * ampl, sum.g * ampl, sum.b * ampl, 1.0);
}
]];

local gauss_v = [[
uniform sampler2D map_diffuse;
varying vec2 texco;

void main()
{
	vec4 sum = vec4(0.0);
	float ampl = %f;
	float dy = 1.0 / %f;

	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - (4.0 * dy))) * 0.05;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - (3.0 * dy))) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - (2.0 * dy))) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - (1.0 * dy))) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y - (0.0     ))) * 0.16;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + (1.0 * dy))) * 0.15;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + (2.0 * dy))) * 0.12;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + (3.0 * dy))) * 0.09;
	sum += texture2D(map_diffuse, vec2(texco.x, texco.y + (4.0 * dy))) * 0.05;

	gl_FragColor = vec4(sum.r * ampl, sum.g * ampl, sum.b * ampl, 1.0);
}
]];

function edge()
	local dw = 320;
	local dh = 320;
	local vid = load_image("images/icons/arcanicon.png");
	resize_image(vid, 320, 320);

	local edge = build_shader(
		nil, string.format(edt, dw, dh, 1.8, 0.1, 0.4), "edge");

	local gauss_h = build_shader(nil, string.format(gauss_h, 1.0, dw), "gauss_h");
	local gauss_v = build_shader(nil, string.format(gauss_v, 1.0, dh), "gauss_v");

	local ghi = fill_surface(dw, dh, 0, 0, 0, dw, dh);
	local ghj = fill_surface(dw, dh, 0, 0, 0, dw, dh);

	define_rendertarget(ghi, {vid}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(ghj, {ghi}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	image_shader(vid, gauss_h);
	image_shader(ghi, gauss_v);
--	image_shader(ghj, edge);
	show_image({vid, ghi, ghj});
end
