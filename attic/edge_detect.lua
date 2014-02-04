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

function calc()
	local edge = build_shader(nil, string.format(edt, 320.0, 320, 1.8, 0.1, 0.4), "edge");
	local vid = load_image("mmm.png");
	resize_image(vid, 320, 320);
	image_shader(vid, edge);
	show_image(vid);
end
