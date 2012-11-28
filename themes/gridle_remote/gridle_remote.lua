settings = {};

function net_event(source, tbl)
	if (tbl.kind == "message") then
	else
		print("unhandled message:", tbl.kind);
	end
end

function gridle_remote()
	system_load("scripts/resourcefinder.lua")();
	system_load("scripts/keyconf.lua")();

	local keylabels = { "rMENU_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT", "rLAUNCH", "aMOUSE_X", "aMOUSE_Y", " CONTEXT", "rMENU_TOGGLE", " DETAIL_VIEW", " SWITCH_VIEW", " FLAG_FAVORITE", " RANDOM_GAME", " OSD_KEYBOARD", " QUICKSAVE", " QUICKLOAD", "rLOCAL_MENU" };

-- prepare a keyconfig that support the specified set of labels (could be nil and get a default one)
	keyconfig = keyconf_create(labels);

-- if active, then there's nothing needed to be done, else we need a UI to help.
	if (keyconfig.active == false) then
	    keyconfig:to_front();

	    oldinput = gridle_remote_input;
	    gridle_remote_input = function(iotbl)

		if (keyconfig:input(iotbl) == true) then
			gridle_remote_input = oldinput;
		end
		end;
	end

	settings.server = net_open(net_event);
end


function gridle_remote_input(iotbl)
	local restbl = keyconfig:match(iotbl);
	if (iotbl.kind == "analog") then return; end

	if (restbl) then
		for ind, val in pairs(restbl) do
			msgstr = iotbl.active and "press:" or "release:";
			msgstr = msgstr .. val;
			net_push(settings.server, msgstr);
		end
	end
end

