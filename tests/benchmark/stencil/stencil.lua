--
-- Hierarchical stencil (depth)
--

function stencil(arguments)
	system_load("scripts/benchmark.lua")();
	benchmark_setup( arguments[1] );

	local root = fill_surface(VRESW * 0.5, VRESH * 0.5, 255, 0, 0);
	move_image(root, VRESW * 0.25, VRESH * 0.25);
	show_image(root);

	last = fill_surface(VRESW * 0.5, VRESH * 0.5, 0, 255, 0);
	move_image(last, math.random(10), math.random(10));
	link_image(last, root);
	image_clip_on(last, CLIP_ON);
	show_image(last);

	benchmark = benchmark_create(40, 5, 10, fill_step);
end

function fill_step()
	local new = fill_surface(VRESW * 0.5, VRESH * 0.5, math.random(255),
		math.random(255), math.random(255));
	rotate_image(new, math.random(359));
	show_image(new);
	link_image(new, last);
	image_clip_on(new);
	last = new;
end

function stencil_clock_pulse()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
