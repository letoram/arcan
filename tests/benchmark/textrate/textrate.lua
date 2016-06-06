--
-- Simple texture sampling test,
-- primarily GPU- related memory reads / writes
-- for the same screen-sized random texture
--

function textrate(arguments)
	system_load("scripts/benchmark.lua")();

	benchmark_setup( arguments[1] );
	noiseimg = random_surface(512, 512);
	benchmark = benchmark_create(40, 5, 10, fill_step);
end

function fill_step()
	local img = null_surface(VRESW, VRESH);
	image_sharestorage(noiseimg, img);
	show_image(img);
	return img;
end

_G[ _G["APPLID"] .. "_clock_pulse"] = function()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
