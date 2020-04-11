--
-- Simple texture sampling test,
-- primarily GPU- related memory reads / writes
-- for the same screen-sized random texture
--

function videospawn(arguments)
	system_load("scripts/benchmark.lua")();

	xpos = 0;
	ypos = 0;

	benchmark_setup( arguments[1] );
	benchmark = benchmark_create(200, 5, 1, fill_step, true);
end

function fill_step()
	local video = launch_decode("videospawn.mkv",
		function(source, status)
			if (status.kind == "resized") then
				resize_image(source, 64, 64);
				show_image(source);
			end
		end
	);
	move_image(video, xpos, ypos);

	xpos = xpos + 64;
	if (xpos > VRESW - 64) then
		xpos = 0;
		ypos = ypos + 64;
		if (ypos > VRESH - 64) then
			ypos = 0;
		end
	end
	return img;
end

_G[ _G["APPLID"] .. "_clock_pulse"] = function()
	if (not benchmark:tick()) then
		return shutdown();
	end
end
