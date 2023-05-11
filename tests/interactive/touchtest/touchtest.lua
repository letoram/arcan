local devices = {};
local TOUCH_W = 100;
local TOUCH_H = 100;

function touchtest()
	image_color(WORLDID, 127, 127, 127);
end

function touchtest_input(iotbl)
	if (iotbl.kind ~= "touch") then
		return;
	end

	local device = devices[iotbl.devid];
	if (not device) then
		local x_axis = inputanalog_query(iotbl.devid, 0);
		local y_axis = inputanalog_query(iotbl.devid, 1);

		if (not x_axis or not y_axis) then
			error("Failed to query for one of input device axis metadata");
		end

		device = {
			x_min = x_axis.lower_bound,
			x_max = x_axis.upper_bound,
			y_min = y_axis.lower_bound,
			y_max = y_axis.upper_bound,
			touches = {},
		};
		devices[iotbl.devid] = device;
	end

	if (iotbl.active) then
		local surface = device.touches[iotbl.subid];
		if (not surface) then
			surface = color_surface(TOUCH_W, TOUCH_H, 255, 0, 0);
			show_image(surface);
			device.touches[iotbl.subid] = surface;
		end

		local x = (iotbl.x - device.x_min) /
		          (device.x_max - device.x_min) *
		          VRESW - TOUCH_W / 2;
		local y = (iotbl.y - device.y_min) /
		          (device.y_max - device.y_min) *
		          VRESH - TOUCH_H / 2;

		move_image(surface, x, y)
	elseif (device.touches[iotbl.subid]) then
		delete_image(device.touches[iotbl.subid]);
		device.touches[iotbl.subid] = nil;
	end
end
