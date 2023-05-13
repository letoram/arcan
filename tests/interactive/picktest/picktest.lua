--
-- Triest to cover the possible [nasty] combinations of picking, i.e.
-- 1. normal, static quad.
-- 2. normal, moving quad.
-- 3. normal, rotating quad.
-- 4. normal, moving + scaling + rotating.
--
-- 4. 1D- rotated, static quad.
-- 4. 1D- rotating quad.
-- 5.
--

function picktest()
	symtable = system_load("builtin/keyboard.lua")();

	local b1 = fill_surface(64, 64, 255, 0, 0);
	show_image(b1);
	move_image(b1, 10, 10);
	image_tracetag(b1, "normal, static.");

	local b2 = fill_surface(64, 64, 0, 255, 0);
	show_image(b2);
	move_image(b2, 10, 84);
	move_image(b2, 64, 84, 100);
	move_image(b2, 10, 84, 100);
	image_transform_cycle(b2, 1);
	image_tracetag(b2, "normal, moving.");

	local b3 = fill_surface(64, 64, 0, 255, 255);
	show_image(b3);
	rotate_image(b3, 300, 100);
	rotate_image(b3, 0, 100);
	image_transform_cycle(b3, 1);
	image_tracetag(b3, "normal, rotating");

	local b4 = color_surface(64, 64, 255, 255, 0);
	show_image(b4);
	move_image(b4, 364, 10);
	rotate_image(b4, 300, 100);
	rotate_image(b4, 0, 100);
	resize_image(b4, 128, 128, 100);
	resize_image(b4, 32, 32, 100);
	move_image(b4, 364, 10, 100);
	move_image(b4, 300, 10, 100);
	image_transform_cycle(b4, 1);
	image_tracetag(b4, "normal, scale+rotate+move");

	cursor = color_surface(8, 8, 255, 255, 255);
	show_image(cursor);
	image_mask_set(cursor, MASK_UNPICKABLE);
	mx = 0;
	my = 0;

	camera = null_surface(1, 1);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33, 1, 1);
	image_tracetag(camera, "camera");
	forward3d_model(camera, -10.0);

	local cube_1 = build_3dbox(1, 1, 1);
	show_image(cube_1);
	move3d_model(cube_1, 1, -1, 0, 100);
	rotate3d_model(cube_1, 320, 320, 320, 100);
	rotate3d_model(cube_1, -100, -100, -100, 100);
	image_transform_cycle(cube_1, 1);
	image_tracetag(cube_1, "cube_1");

	local cube_2 = build_3dbox(1, 1, 1);
	show_image(cube_2);
	move3d_model(cube_2, -1, -1, 0, 100);
	rotate3d_model(cube_2, 0, 320, 0, 100);
	rotate3d_model(cube_2, 0, 300, 0, 100);
	image_transform_cycle(cube_2, 1);
	image_tracetag(cube_2, "cube_2");
	image_sharestorage(b1, cube_1);
	image_sharestorage(b2, cube_2);
end

function picktest_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		if (iotbl.relative) then
			if (iotbl.subid == 1) then
				my = my + iotbl.samples[1];
			else
				mx = mx + iotbl.samples[1];
			end
		else
			if (iotbl.subid == 1) then
				my = iotbl.samples[1];
			else
				mx = iotbl.samples[1];
			end
		end

		move_image(cursor, mx, my);

		res = pick_items(mx, my);
		print("forward:")
		for i = 1, #res do
			print(image_tracetag(res[i]));
		end

		res = pick_items(mx, my, 8, 1);
		print("reverse:")
		for i=1, #res do
			print(image_tracetag(res[i]));
		end

		print("done\n");
	elseif (iotbl.kind == "digital") then
		if (iotbl.translated) then
			local sym = symtable.tolabel(iotbl.keysym);

				if (iotbl.active) then
					if (sym == "UP") then
						forward3d_model(camera, 0.1);
					elseif (sym == "DOWN") then
						forward3d_model(camera, -0.1);
					elseif (sym == "LEFT") then
						strafe3d_model(camera, -0.1);
					elseif (sym == "RIGHT") then
						strafe3d_model(camera, 0.1);
					end
				end

				shift_held = iotbl.active;
			end
		end
end
