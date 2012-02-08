function modeltest()
	symtable = system_load("scripts/symtable.lua")();
	local confun = system_load("scripts/console.lua")();

	sens = 0.1;
	yaw = 0.0;
	pitch = 0.0;
	roll = 0.0;
	ystepsize = 0.0;
	sidestepsize = 0.0;
	fwdstepsize = 0.0;
	
--	games = list_games( {} );
--	gvid, gaid = launch_target(games[2].title, LAUNCH_INTERNAL);

	model = system_load("models/" .. arguments[1] .. "/" .. arguments[1] .. ".lua")();
	print("loaded model to: " .. model.vid);
	mousex = VRESW * 0.5;
	mousey = VRESH * 0.5;

--	plane = build_3dplane(-5.0, -5.0, 5.0, 5.0, -1.0, 0.1, 0.1);

	toggle_mouse_grab();
	kbd_repeat(100);
--	show_image(plane);
	
	rotate3d_model(model.vid, 0, 270,0, 100);
	show_image(model.vid);
	contbl = create_console(VRESW , VRESH / 4, "fonts/default.ttf", 18);
	console_enabled = false;
	contbl:hide();
	
end

function modeltest_clock_pulse()
	strafe3d_camera(sidestepsize);
	forward3d_camera(fwdstepsize);
	orient3d_camera(roll, pitch, yaw);
end

function modeltest_input(iotable)
	if (iotable.kind == "digital") then
		if (console_enabled and iotable.active) then
			key = symtable[iotable.keysym];
			if (key == "F12") then
				console_enabled = false;
				contbl:hide();
			else
				local cmd = contbl:input(iotable);
				if (cmd ~= "") then
					print(" exec: " .. cmd);
					assert(loadstring(cmd))();
				end
			end
		else
			key = symtable[iotable.keysym];
			if key == "w" then
			  forward3d_camera(0.5);
			elseif key == "s" then
			  forward3d_camera(-0.5);
			elseif key == "a" then
			  strafe3d_camera(0.5);
			elseif key == "d" then
			  strafe3d_camera(-0.5);
			elseif key == "q" then
				ystepsize = iotable.active and 0.5 or 0.0;
			elseif key == "e" then
				ystepsize = iotable.active and -0.5 or 0.0;
			elseif key == "ESCAPE" then
				shutdown();
			elseif iotable.active and key == "F12" then
				contbl:show();
				console_enabled = true;
			end
		end
	else
		if iotable.subid == 1 then
			pitch = (pitch + iotable.samples[2] * sens) % 360;
		else
			yaw = (yaw + iotable.samples[2] * sens) % 360;
		end	
	end	
end
