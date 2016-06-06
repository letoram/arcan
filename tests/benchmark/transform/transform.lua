--
-- Simple Fillrate test,
-- primarily GPU- related memory writes
--

function transform(arguments)
	system_load("scripts/benchmark.lua")();

	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(20, 5, 10, fill_step);
end

function fill_step()
	local surf = color_surface(1, 1, math.random(255),
		math.random(255), math.random(255));

	for i=1,10 do
		move_image(surf, math.random(VRESW),
			math.random(VRESH), math.random(100));
		rotate_image(surf, math.random(360), math.random(100));
		blend_image(surf, math.random(255) / 255.0, math.random(100));
		resize_image(surf, math.random(20), math.random(20), math.random(100));
	end

	image_transform_cycle(surf, 1);

	return surf;
end

function transform_clock_pulse()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
