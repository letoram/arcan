local fshader = [[
	uniform sampler2D map_diffuse;
	varying vec2 texco;

	void main()
	{
		gl_FragColor = vec4(texco.s, texco.t, 0.0, 1.0);
	}
]];

function calctarget()
	local img = fill_surface(256, 256, 0, 0, 0);
	local shid = build_shader(nil, fshader, "generator");
	image_shader(img, shid);

	interim = alloc_surface(256, 256);
	show_image(interim);
	show_image(img);
	define_calctarget(interim, {img}, RENDERTARGET_NODETACH,
		RENDERTARGET_NOSCALE, 0, function(src)
			local hsum = 0;
			for i=0,255 do
				hsum = hsum + src:get(i, 0, 1);
			end

			local vsum = 0;
			for i=0,255 do
				vsum = vsum + src:get(0, i, 1);
			end

			local dsum = 0;
			for i=0,255 do
				dsum = dsum + src:get(i, i, 1);
			end

			delete_image(interim);
			rc = 0;
			if (hsum ~= 10880 or vsum ~= 10880 or dsum ~= 21760) then
			    rc = 1;
			end
			return shutdown(string.format("%d, %d, %d", hsum, vsum, dsum), rc);
		end);
		rendertarget_forceupdate(interim);
		stepframe_target(interim);
end
