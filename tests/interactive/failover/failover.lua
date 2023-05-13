function failover()
	symtbl = system_load("builtin/keyboard.lua")();

	a = list_targets();

	if (#a == 0) then
		return shutdown("no targets found, can not run the test");
	end

	system_context_size(10);
	pop_video_context();

	fsrvs = {};

	for i=1,2 do
		local vid = launch_target(
			a[math.random(#a)], LAUNCH_INTERNAL, cb);
		table.insert(fsrvs, vid);
		print(#fsrvs);
	end

	print("failover test, serious frameserver state-changes and migration")
	print("keys:")
	print("1 - spawn random color image")
	print("2 - system collapse with local transfer")
	print("3 - system collapse with transfer to failadopt")
	print("4 - lua dynamic error leading to fallback script (engine arg)")
	print("5 - pacify frameservers")

	x_p = 0
	y_p = 0
end

function cb(source, status)
	if (status.kind == "resized") then
		move_image(source, x_p, y_p);
		x_p = x_p + status.width;
		if (x_p > VRESW - status.width) then
			x_p = 0;
			y_p = y_p + status.height;
		end
		show_image(source);
		resize_image(source, status.width, status.height);
		play_audio(status.source_audio);
		print(source, x_p, y_p, status.width, status.height);
	end
end

function failover_adopt(id)
	print("adopted a new frameserver", id);
	table.insert(fsrvs, id);
	local props = image_surface_initial_properties(id);
	show_image(id);
	resize_image(id, props.width, props.height);
	move_image(id, x_p, y_p);

	x_p = x_p + props.width;
	if (x_p > VRESW - props.width) then
		x_p = 0;
		y_p = y_p + props.height;
	end

-- need a way to set a new callback
end

function failover_input(iotbl)
	local label = symtbl.tolabel(iotbl.keysym)
	if (iotbl.kind == "digital" and iotbl.translated and iotbl.active) then
		if (label == "1") then
			local img = color_surface(32, 32,
				math.random(127) + 127, math.random(127) + 127, 0);
			show_image(img);
			move_image(img, math.random(VRESW), math.random(VRESH));

		elseif (label == "2") then
			print("request collapse");
			x_p = 0;
			y_p = 0;
			fsrvs = {};
			system_collapse();
		elseif (label == "3") then
			system_collapse("failadopt");
		elseif (label == "4") then
			this_should_trigger_perror();
		elseif (label == "5") then
			print("pacify", #fsrvs);
			for i=1,#fsrvs do
				target_pacify(fsrvs[i]);
			end
			fsrvs = {};
		end
	end
end

