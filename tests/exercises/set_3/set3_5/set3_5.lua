function set3_5()
	system_load("builtin/mouse.lua")();
	mouse_setup(fill_surface(8, 8, 0, 255, 0), 65535, 1, true, false);

	box = fill_surface(32, 32, 255, 0, 0);
	show_image(box);
	move_image(box, math.random(VRESW - 32), math.random(VRESH - 32));

	local mev = {
		name = "drag box handler",
		own = function(mev, vid)
			return vid == box;
		end,
		drag = function(mev, vid, dx, dy)
			nudge_image(vid, dx, dy);
		end
	};
	mouse_addlistener(mev, {"drag"});
end

function set3_5_clock_pulse()
	mouse_tick(1);
end

function set3_5_input(iotbl)
	if iotbl.mouse then
		mouse_iotbl_input(iotbl)
	end
end
