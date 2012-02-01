function modeltest()
	symtable = system_load("scripts/symtable.lua")();
	sens = 0.1;
	yaw = 0.0;
	pitch = 0.0;
	roll = 0.0;
	sidestepsize = 0.0;
	fwdstepsize = 0.0;
	
	games = list_games( {} );
	gvid, gaid = launch_target(games[2].title, LAUNCH_INTERNAL);

	vid = system_load("models/apb/apb.lua")();	
	print("loaded model to: " .. vid);
	mousex = VRESW * 0.5;
	mousey = VRESH * 0.5;
	
	plane = build_3dplane(-5.0, -5.0, 5.0, 5.0, -1.0, 0.1, 0.1);

	toggle_mouse_grab();

	show_image(plane);
	show_image(vid);
end

function modeltest_clock_pulse()
	strafe3d_camera(sidestepsize);
	forward3d_camera(fwdstepsize);
	orient3d_camera(roll, pitch, yaw);
end

function modeltest_input(iotable)
	if (iotable.kind == "digital") then
		key = symtable[iotable.keysym];
		if key == "w" then
			fwdstepsize = iotable.active and -0.5 or 0.0;
		elseif key == "s" then
			fwdstepsize = iotable.active and 0.5 or 0.0;
		elseif key == "a" then
			sidestepsize = iotable.active and 0.5 or 0.0;
		elseif key == "d" then
			sidestepsize = iotable.active and -0.5 or 0.0;
		elseif key == "ESCAPE" then
			shutdown();
		end	
	else
		if iotable.subid == 1 then
			pitch = (pitch + iotable.samples[2] * sens) % 360;
		else
			yaw = (yaw + iotable.samples[2] * sens) % 360;
		end	
	end	
end
