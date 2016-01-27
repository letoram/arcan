local statetbl = {
	DISPLAY_OFF,
	DISPLAY_SUSPEND,
	DISPLAY_ON,
	DISPLAY_STANDBY
};

local stateind = 1;

function dpmstest()
	video_displaymodes();
end

function dpmstest_display_state(action, id)
-- some platforms may yield added on already known displays
	if (action == "added") then
		for k,v in ipairs(displays) do
			if (v == id) then
				return;
			end
		end
		table.insert(displays, id);
	elseif (action == "removed") then
		for k,v in ipairs(displays) do
			if (v == id) then
				table.remove(displays, k);
				return;
			end
		end
	end
end

function dpmstest_clock_cycle()
	ticks = ticks - 1;
	if (ticks == 0) then
		ticks = 1000;
		print(#displays, "displays, states (pre):");
		for i=1,#displays do
			print(i, video_display_state(displays[i]));
		end

		for i=1,#displays do
			video_display_state(displays[i], statetbl[stateind]);
		end
		stateind = stateind + 1 > #statetbl and 1 or stateind + 1;
	end
end
