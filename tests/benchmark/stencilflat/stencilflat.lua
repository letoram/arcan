--
-- Horizontal stencil (individual pairs)
--
function stencilflat(arguments)
	system_load("scripts/benchmark.lua")();
	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(40, 5, 10, fill_step);
end

function fill_step()
	local parent = fill_surface(VRESW * 0.5, VRESH * 0.5,
		math.random(255), math.random(255), math.random(255));

	local child = fill_surface(VRESW * 0.5, VRESH * 0.5,
		math.random(255), math.random(255), math.random(255));

	move_image(child, math.random(64), math.random(64));
	rotate_image(child, 64);
	link_image(child, parent);
	image_clip_on(child, CLIP_ON);

	show_image({parent, child});
	return parent;
end

function stencilflat_clock_pulse()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
