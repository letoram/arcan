function scan()
	symtable = system_load("scripts/symtable.lua")();
	a = load_image("images/icons/arcanicon.png");
	show_image(a);
	move_image(a, 100, 100, 100);
	move_image(a, 0, 0, 100);
	image_transform_cycle(a, 1);
end

function scan_input(iotbl)
	if (iotbl.translated and iotbl.active) then
		local sym = symtable[iotbl.keysym];
		if (sym == "F1") then
			local modes = video_displaymodes(0);
			mode = modes[math.random(1, #modes)];
			video_displaymodes(0, mode.modeid);

		elseif (sym == "F2") then
			a = benchmark_timestamp();
			print("force rescan");
			video_displaymodes();
			print("done", benchmark_timestamp() - a);

		elseif (sym == "ESCAPE") then
			return shutdown("done")
		end

	end
end

function scan_display_state(a, b)
	if (a == "added") then
		video_displaymodes(b[1].displayid, b[1].modeid);
		map_video_display(WORLDID, b[1].displayid);
	end
end
