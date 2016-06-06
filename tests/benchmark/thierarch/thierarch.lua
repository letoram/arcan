--
-- Hierarchical depth test
-- Should draw a line of random corners going from top diagonal
-- line and down. Moving around to prevent caching.
--
--

function thierarch(arguments)
	system_load("scripts/benchmark.lua")();

	xpos = 0;
	ypos = 0;

	benchmark_setup( arguments[1] );
	root = color_surface(1,1, 255, 0, 0);
	show_image(root);
	move_image(root, 200, 200, 100);
	move_image(root, 0, 0, 100);
	image_transform_cycle(root, 1);
	prev = root;

	benchmark = benchmark_create(200, 5, 1, fill_step, true);
end

function fill_step()
	new = color_surface(1, 1, math.random(255),
		math.random(255), math.random(255));
	show_image(new);
	link_image(new, prev);
	move_image(new, 1, 1);
	prev = new;
end

_G[ _G["APPLID"] .. "_clock_pulse"] = function()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
