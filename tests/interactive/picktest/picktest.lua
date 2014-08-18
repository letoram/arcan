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
	symtable = system_load("scripts/symtable.lua")();

	local b1 = color_surface(64, 64, 255, 0, 0);
	show_image(b1);
	move_image(b1, 10, 10);
	image_tracetag(b1, "normal, static.");

	local b2 = color_surface(64, 64, 0, 255, 0);
	show_image(b2);
	move_image(b2, 10, 84);
	move_image(b2, 64, 84, 100);
	move_image(b2, 10, 84, 100);
	image_transform_cycle(b2, 1);
	image_tracetag(b2, "normal, moving.");

	local b3 = color_surface(64, 64, 0, 255, 255);
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

	system_load("scripts/3dsupport.lua")();
	camera = setup_3dsupport();

	forward3d_model(camera, -10.0);

	local cube_1 = build_3dbox(1, 1, 1);
	show_image(cube_1);
	move3d_model(cube_1, 1, -1, 0, 100);
	rotate3d_model(cube_1, 320, 320, 320, 100);
	rotate3d_model(cube_1, -100, -100, -100, 100);
	image_transform_cycle(cube_1, 1);
	image_tracetag(cube_1, "cube_1");

	local shid = load_shader("shaders/dir_light.vShader", "shaders/dir_light.fShader", "light", {});

	local cube_2 = build_3dbox(1, 1);
	show_image(cube_2);
	move3d_model(cube_2, -1, -1, 0, 100);
	rotate3d_model(cube_2, 0, 320, 0, 100);
	rotate3d_model(cube_2, 0, 300, 0, 100);
	image_transform_cycle(cube_2, 1);
	image_tracetag(cube_2, "cube_2");

	local col  = fill_surface(32, 32, 255, 128, 0);

	set_image_as_frame(cube_1, col, 0, FRAMESET_NODETACH);
	set_image_as_frame(cube_2, col, 0, FRAMESET_NODETACH);

	shader_uniform(shid, "wdiffuse", "fff", PERSIST, 0.0, 1.0, 0.0);
	shader_uniform(shid, "wambient", "fff", PERSIST, 0.3, 0.3, 0.1);
	shader_uniform(shid, "wlightdir", "fff", PERSIST, 0.0, 1.0, 0.0);

	image_shader(cube_1, shid);
	image_shader(cube_2, shid);
end

function picktest_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		if (iotbl.subid == 1) then
			my = iotbl.samples[1];
		else
			mx = iotbl.samples[1];
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
			local sym = symtable[iotbl.keysym];

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
