local dv = {0, 0};
local btns = {
	UP = true,
	DOWN = true,
	LEFT = true,
	RIGHT = true
};

function set3_4()
	symtable = system_load("builtin/keyboard.lua")();
	cursor_setstorage(fill_surface(8, 8, 0, 255, 0));
	resize_cursor(8, 8);
end

function set3_4_clock_pulse()
	nudge_cursor(dv[1] * 5, dv[2] * 5);
end

function release_btn(sym)
	if ( (sym == "UP" and dv[2] == -1) or
	     (sym == "DOWN" and dv[2] == 1) ) then
		dv[2] = 0;

	elseif( (sym == "LEFT" and dv[1] == -1) or
	        (sym == "RIGHT" and dv[1] == 1) ) then
		dv[1] = 0;
	end
end

function press_btn(sym)
	if (sym == "UP") then
		dv[2] = -1;
	elseif (sym == "DOWN") then
		dv[2] = 1;
	elseif (sym == "LEFT") then
		dv[1] = -1;
	elseif (sym == "RIGHT") then
		dv[1] = 1;
	end
end

function set3_4_input(iotbl)
	if (iotbl.translated) then
		local sym = symtable[iotbl.keysym];
		if (sym ~= nil and btns[sym]) then
			if (iotbl.active) then
				return press_btn(sym);
			else
				return release_btn(sym);
			end
		end
	elseif (iotbl.source == "mouse" and iotbl.kind == "analog") then

		if (iotbl.subid == 0) then
			last_x = iotbl.samples[1];
		end

		if (iotbl.subid == 1) then
			last_y = iotbl.samples[1];
		end

		if (last_x ~= nil and last_y ~= nil) then
			move_cursor(last_x, last_y);
			last_x = nil;
			last_y = nil;
		end
	end
end
