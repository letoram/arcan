--
-- Simple texture sampling test,
-- primarily GPU- related memory reads / writes
-- for the same screen-sized random texture
--

function textswitch(arguments)
	system_load("scripts/benchmark.lua")();

	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(40, 5, 1, fill_step);
end

function fill_step()
	local img = fill_surface(VRESW, VRESH, math.random(255),
		math.random(255), math.random(255), 512, 512);

	show_image(img);
	return img;
end

_G[ _G["APPLID"] .. "_clock_pulse"] = function()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
