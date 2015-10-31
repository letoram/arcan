local rshader = [[
	uniform sampler2D map_diffuse;
	varying vec2 texco;

	void main()
	{
		vec3 col = texture2D(map_diffuse, texco).rgb;
		gl_FragColor = vec4(col.r, 0.5 * col.g, 0.5 * col.b, 1.0);
	}
]];

function resample(arguments)
	local img = fill_surface(256, 256, 0, 0, 0);
	local resamp = build_shader(nil, rshader, "scaler");

	local image = load_image("data.png");
	resample_image(image, resamp, 512, 512);

	save_screenshot(arguments[1], 0, image);
	return shutdown();
end
