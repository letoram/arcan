function set3_5()
	system_load("scripts/mouse.lua")();
	mouse_setup_native(fill_surface(8, 8, 0, 255, 0));
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
	if (iotbl.source == "mouse") then
		if (iotbl.kind == "digital") then
			mouse_button_input(iotbl.subid, iotbl.active);
		else
			if (iotbl.subid == 0) then
				mouse_x = iotbl.samples[1];
			elseif (iotbl.subid == 1) then
				mouse_y = iotbl.samples[1];
			end
			if (mouse_x ~= nil and mouse_y ~= nil) then
				mouse_absinput(mouse_x, mouse_y);
				mouse_x = nil;
				mouse_y = nil;
			end
		end
	end
end
