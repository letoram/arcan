--
-- Simple Fillrate test,
-- primarily GPU- related memory writes
--

function fillrate(arguments)
	system_load("scripts/benchmark.lua")();

	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(40, 5, 10, fill_step);
end

function fill_step()
	local col = math.random(255)
	a = color_surface(VRESW, VRESH,
		math.random(255), math.random(255), math.random(255));
	show_image(a);
	return a;
end

function fillrate_clock_pulse()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
