--
-- This example shows how to generate and show
-- a histogram on data that is dynamically generated
-- on the GPU.
--

histo_plot = [[
uniform sampler2D map_diffuse;
varying vec2 texco;

void main()
{
	vec2 uv = vec2(texco.s, 1.0 - texco.t);
	vec4 col = texture2D(map_diffuse, uv);

	float rv = float(col.r > uv.y);
	float gv = float(col.g > uv.y);
	float bv = float(col.b > uv.y);

	gl_FragColor = vec4(rv, gv, bv, 1.0);
}
]];

animate = [[
varying vec2 texco;
uniform int timestamp;

void main()
{
	float fact = 0.3 * float(timestamp) / 25.0;
	gl_FragColor = vec4(cos(fact) * texco.s, sin(fact) * texco.t, sin(fact), 1.0);
}
]];

function histoview()
-- create buffer image that will receive histogram data
	histogram = fill_surface(256, 1, 0, 0, 0, 256, 1);
	show_image(histogram);
	resize_image(histogram, 256, VRESH);
	order_image(histogram, 2);
	move_image(histogram, VRESW - 256, 0);
	local hsh = build_shader(nil, histo_plot, "histogram shader");
	image_shader(histogram, hsh);

-- create data source, experiment with replacing this
-- with other sources (e.g. external connections,
-- streaming sources etc).
	local shview = alloc_surface(256, 256);
	show_image(shview);
	image_shader(shview, build_shader(nil, animate, "data source"));

-- create the composition buffer that will be read back
	local dst = alloc_surface(256, 256);
	define_calctarget(dst, {shview}, RENDERTARGET_NODETACH,
		RENDERTARGET_NOSCALE, -1, readback);
end

function readback(tbl, w, h)
	tbl:histogram_impose(histogram, HISTOGRAM_SPLIT, false);
end
