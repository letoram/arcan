local step = {WORLDID, BADID};
local ofs = 1;

function scan()
	symtable = system_load("builtin/keyboard.lua")();
	a = load_image("images/icons/arcanicon.png");
	table.insert(step, a);

	c = color_surface(64, 64, 255, 0, 0);
	d = color_surface(32, 32, 0, 255, 0);
	e = color_surface(128, 128, 0, 0, 255);
	blend_image(c, 1.0, 100);
	blend_image(c, 0.0, 100);
	rotate_image(c, 100, 100);
	rotate_image(c, 0, 100);
	image_transform_cycle(c, 1);

	show_image({d, e});

	move_image(d, 300, 0, 100);
	move_image(e, 0, 300, 100);
	move_image(d, 300, 300, 100);
	move_image(e, 300, 400, 100);

	image_transform_cycle(d, 1);
	image_transform_cycle(e, 1);

	b = alloc_surface(800, 500)
	define_rendertarget(b, {c,d,e}, RENDERTARGET_DETACH,
		RENDERTARGET_NOSCALE);
	table.insert(step, b);

	show_image(a);
	move_image(a, 100, 100, 100);
	move_image(a, 0, 0, 100);
	image_transform_cycle(a, 1);
end

function scan_input(iotbl)
	if (iotbl.translated and iotbl.active) then
		local sym = symtable.tolabel(iotbl.keysym);
		if (sym == "F1") then
			local modes = video_displaymodes(0);
			mode = modes[math.random(1, #modes)];
			video_displaymodes(0, mode.modeid);

		elseif (sym == "q") then
			ofs = (ofs + 1 > #step and 1 or ofs + 1);
			map_video_display(step[ofs], 1);

		elseif (sym == "w") then
			ofs = (ofs + 1 > #step and 1 or ofs + 1);
			map_video_display(step[ofs], 1);

		elseif (sym == "F2") then
			a = benchmark_timestamp();
			print("force rescan");
			video_displaymodes();
			print("done", benchmark_timestamp() - a);

		elseif (sym == "F3") then
			resize_video_canvas(100 + math.random(1000),
				100 + math.random(1000));

		elseif (sym == "ESCAPE") then
			return shutdown("done")
		end
	end
end

function scan_display_state(event, displayid)
	if (event == "added") then
		video_displaymodes(displayid);
		map_video_display(WORLDID, displayid);
	end
end
