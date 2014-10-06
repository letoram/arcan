--
-- instance- image test, 10+1 parent nodes per spawn
--

function spart()
	system_load("scripts/benchmark.lua")();

	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(20, 5, 1, fill_step, true);
end

function fill_step()
	local new_node = color_surface(64, 64, 200 - math.random(100),
		200 - math.random(100), 0);
	show_image(new_node);

	for i=1,10 do
		move_image(new_node, math.random(VRESW),
			math.random(VRESH), math.random(100));
	end

	image_transform_cycle(new_node, 1);

	for i=1,10 do
		local child = instance_image(new_node);
		resize_image(child, 32, 32);
		blend_image(child, (math.random(180) + 75) / 255.0);
		move_image(child, math.random(128)-64, math.random(128)-64);
	end

end

_G[ _G["APPLID"] .. "_clock_pulse"] = function()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
