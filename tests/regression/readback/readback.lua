local fshader_1 = [[
	varying vec2 texco;
	uniform int timestamp;

	void main()
	{
		int split = int( mod( float(timestamp + 2), 2.0) );
		if (split == 0)
			gl_FragColor = vec4(texco.s, texco.s, texco.s, 1.0);
		else
			gl_FragColor = vec4(texco.t, texco.t, texco.t, 1.0);
	}
]];


local fshader_2 = [[
	varying vec2 texco;
	uniform int timestamp;

	void main()
	{
		int split = int( mod( float(timestamp + 1), 2.0) );
		if (split == 0)
			gl_FragColor = vec4(texco.s, texco.s, texco.s, 1.0);
		else
			gl_FragColor = vec4(texco.t, texco.t, texco.t, 1.0);
	}
]];

function readback(args)
	arguments = args
	local img = fill_surface(128, 256, 0, 0, 0);
	local img2 = fill_surface(128, 256, 0, 0, 0);
	move_image(img2, 128, 0);
	local shid = build_shader(nil, fshader_1, "generator");
	local shid2 = build_shader(nil, fshader_2, "generator2");
	image_shader(img, shid);
	image_shader(img2, shid2);

	interim = alloc_surface(256, 256);
	show_image({interim, img, img2});
	define_rendertarget(interim, {img, img2}, RENDERTARGET_NODETACH,
		RENDERTARGET_NOSCALE, 1)
end

local counter = 0;
function readback_clock_pulse()
	counter = counter + 1;
	if (counter == 20) then
		save_screenshot(arguments[1], 0, interim);
		return shutdown();
	end
end
