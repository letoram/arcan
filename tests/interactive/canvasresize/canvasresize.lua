function canvasresize()
	keysym = system_load("builtin/keyboard.lua")();
	a = fill_surface(VRESW, VRESH, 255, 0, 0);
	resize_video_canvas(VRESW, VRESH);
	show_image(a);
	cursor = fill_surface(32, 32, 0, 0, 255);
	cursor_setstorage(cursor);
	move_cursor(VRESW * 0.5, VRESH * 0.5);

	print("canvas_resize, press F1 to double canvas size, F2 for screenshot\n");
end

function canvasresize_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then
		local label = keysym.tolabel(iotbl.keysym)
		if (label == "F1") then
			resize_video_canvas(VRESW * 2, VRESH * 2);
			b = fill_surface(200, 200, 0, 255, 0);
			show_image(b);
			move_image(b, VRESW, VRESH, 200);
		elseif (label == "F2") then
			zap_resource("test.png");
			save_screenshot("test.png", 1, WORLDID);
		end
	elseif (iotbl.kind == "analog" and iotbl.source == "mouse") then
		print(iotbl.samples[2], iotbl.subid);
		nudge_cursor(iotbl.subid == 0 and (2 * iotbl.samples[2]) or 0,
			iotbl.subid == 1 and (2 * iotbl.samples[2]) or 0);
		print(cursor_position());
	end
end
