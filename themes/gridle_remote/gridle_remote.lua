settings = {
	repeatrate = 200,
	connected = false,
	iodispatch = {},
};

imagery = {};
	
function spawn_mainmenu()
-- Default Global Menus (and their triggers)
	local mainlbls     = {};
	local settingslbls = {"Reset Keyconfig", "Reset Layout"};
	local connectlbls  = {"Local Discovery", "Specify Server"};
	
	local connectptrs  = {};
	local mainptrs     = {};
	local settingsptrs = {};

	add_submenu(mainlbls, mainptrs, "Settings...", "_nokey", settingslbls, settingsptrs);
	add_submenu(mainlbls, mainptrs, "Connection...", "_nokey", connectlbls, connectptrs);
	
	table.insert(mainlbls, "----");
	table.insert(mainlbls, "Quit");

	mainptrs["Quit"] = function() 
		shutdown(); 
	end

	settingsptrs["Reset Layout"] = function()
		zap_resource("layout_cfg.lua");

		while current_menu ~= nil do
			current_menu:destroy();
			current_menu = current_menu.parent;
		end

		pop_video_context();
		settings.server = nil;
		gridleremote_customview( setup_complete );
	end

	settingsptrs["Reset Keyconfig"] = function()
		zap_resource("keysym.lua");
		setup_keys( setup_complete );
	end

	connectptrs["Local Discovery"] = function()
		settings.connect_method = "local discovery";

		if (valid_vid(settings.server)) then
			delete_image(settings.server);
		end

		spawn_warning("Looking for local server...");
		settings.iodispatch = {};
		settings.iodispatch["MENU_ESCAPE"] = reset_connection;
		settings.server = net_open(net_event);
		
		while current_menu ~= nil do
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
	end

	connectptrs["Specify Server"] = function()
-- spawn OSD and upon completion, explicit connection
		osdkbd:show();
-- do this here so we have access to the namespace where osdsavekbd exists
		gridle_remote_input = function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdkbd);
			
			if (complete) then
				osdkbd:hide();
				gridle_remote_input = gridle_remote_dispatchinput;

				if (resstr ~= nil and string.len(resstr) > 0) then
					while current_menu ~= nil do
						current_menu:destroy();
						current_menu = current_menu.parent;
					end

					settings.iodispatch = {};
					settings.iodispatch["MENU_ESCAPE"] = reset_connection;
					settings.server = net_open(resstr, net_event);
					spawn_warning("Connecting to " .. resstr);
				end
			end
		end
	end

	if (valid_vid(settings.server)) then
		table.insert(connectlbls, "Autoconnect (On)");
		table.insert(connectlbls, "Autoconnect (Off)");
		connectptrs["Autoconnect (On)"] = function() store_key("autoconnect", settings.connect_method); end
		connectptrs["Autoconnect (Off)"] = function() delete_key("autoconnect"); end
	end
	
-- when we have a valid connection, this entry is visible
-- and can be used to set an autoconnect on launch rather than spawning the menu
	connectptrs["Autoconnect"] = function()
	end
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;
	root_menu = current_menu;

	current_menu:show();
	move_image(current_menu.anchor, 10, VRESH * 0.1, 10);
end

function string.split(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
	
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end
	
	table.insert(res, string.sub(instr, strt));
	return res;
end

function net_event(source, tbl)
	if (tbl.kind == "connected") then
		settings.iodispatch = {};
		settings.connected = true;
		spawn_warning("Connected", 125);
		gridle_remote_input = gridle_remote_dispatchinput;
		
	elseif (tbl.kind == "message") then
-- format matches broadcast_game in gridle.lua
		nitem = string.split(tbl.message, ":")

		if (nitem[1] == "begin_item") then
			settings.cur_item = {};
			settings.item_count = tonumber(nitem[2]);
			last_key = nil;

		elseif (settings.item_count) then
			if (last_key == nil) then
				last_key = tbl.message;
			else
				settings.cur_item[last_key] = tbl.message;
				last_key = nil;
				settings.item_count = settings.item_count - 1;
				if (settings.item_count <= 0) then
					settings.item_count = nil;
					gridleremote_updatedynamic(settings.cur_item);
				end
			end
		end

	elseif (tbl.kind == "frameserver_terminated") then
		settings.connected = false;
		show_image(imagery.disconnected);
		blend_image(imagery.disconnected, 0, 40);
		gridleremote_customview( setup_complete );
		settings.server = nil;
	else
	end
	
end

function reset_connection()
	if (valid_vid(settings.server)) then
		delete_image(settings.server);
		settings.server = nil;
	end
	
	if (settings.infowin) then
		delete_image(settings.infowin.anchor);
		settings.infowin = nil;
	end

	reset_iodispatch();
	spawn_mainmenu();
	spawn_warning("Networking session terminated", 50);
end

function spawn_warning( message, expiration )
-- render message and make sure it is on top
	if (settings.infowin) then
		delete_image(settings.infowin.anchor);
		settings.infowin = nil;
	end
	
	local msg         = string.gsub(message, "\\", "\\\\"); 
	local infowin     = listview_create( {msg}, VRESW / 2, VRESH / 2 );
	infowin:show();

	if (expiration == nil) then
		settings.infowin = infowin;
	else
		expire_image(infowin.anchor, 125);
		blend_image(infowin.window, 0.0, 125);
		blend_image(infowin.border, 0.0, 125);
	end

	local x = math.floor( 0.5 * (VRESW - image_surface_properties(infowin.border, 100).width)  );
	local y = math.floor( 0.5 * (VRESH - image_surface_properties(infowin.border, 100).height) );
	
	move_image(infowin.anchor, x, y);
	hide_image(infowin.cursorvid);
end

-- plucked from gridle, removing the soundmap calls
function osdkbd_inputfun(iotbl, dstkbd)
	local restbl = keyconfig:match(iotbl);
	local done   = false;
	local resstr = nil;

	if (restbl) then
		for ind,val in pairs(restbl) do
			if (val == "MENU_ESCAPE" and iotbl.active) then
				return true, nil
			elseif (val == "MENU_SELECT" or val == "MENU_UP" or val == "MENU_LEFT" or
				val == "MENU_RIGHT" or val == "MENU_DOWN" or val == "CONTEXT") then
				resstr = dstkbd:input(val, iotbl.active);
-- also allow direct keyboard input
			elseif (iotbl.translated) then
				resstr = dstkbd:input_key(iotbl, iotbl.active);
			end
-- stop processing labels immediately after we get a valid filterstring
		end
	else -- still need to try and input even if we didn't find a matching value
		if (iotbl.translated) then
			resstr = dstkbd:input_key(iotbl, iotbl.active);
		end
	end

	if (resstr) then
		return true, resstr;
	end
	
	return false, nil
end

--
-- Callback that shows the main connect menu etc.
-- Used as "safe-state" so also triggered if the network connection dies
-- 
function reset_iodispatch()
	settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		if (current_menu and current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
		else -- top level
		end
	end
		
	menu_defaultdispatch();
end

function setup_complete()
	reset_iodispatch();
	spawn_mainmenu();
	imagery.disconnected = load_image("images/disconnected.png");
	local props = image_surface_properties(imagery.disconnected);
	if (props.width > VRESW) then props.width = VRESW; end
	if (props.height > VRESH) then props.height = VRESH; end
	
	local keymap = {
		"7", "8", "9", "a", "b", "\n",
		"4", "5", "6", "c", "d", "\n",
		"1", "2", "3", "e", "f", "\n",
		".", "0", ":", "\n" };

	osdkbd = osdkbd_create(keymap);
end

function gridle_remote()
	system_load("scripts/resourcefinder.lua")();
	system_load("scripts/keyconf.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/listview.lua")();
	system_load("scripts/osdkbd.lua")();
	system_load("remote_config.lua")();

-- rREMOTE_ESCAPE gets remapped to MENU_ESCAPE
	local keylabels = { "rLOCAL_MENU", "rMENU_TOGGLE", "rREMOTE_ESCAPE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT", "rSWITCH_VIEW", "rLAUNCH",
		"aMOUSE_X", "aMOUSE_Y", " CONTEXT", " FLAG_FAVORITE", " RANDOM_GAME", " OSD_KEYBOARD", " QUICKSAVE", " QUICKLOAD"};

-- prepare a keyconfig that support the specified set of labels (could be nil and get a default one)
	keyconfig = keyconf_create(keylabels);
	
-- will either spawn the setup layout first or, if there already is one, spawn menu (which may or may not just autoconnect
-- depending on settings) 
	setup_keys( function() gridleremote_customview( setup_complete ) end );
end

function setup_keys( trigger )
-- if active, then there's nothing needed to be done, else we need a UI to help.
	if (keyconfig.active == false) then
		keyconfig:to_front();
		oldinput = gridle_remote_input;
		gridle_remote_input = function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				gridle_remote_input = oldinput;
				trigger();
			end
			end;
	else
		trigger();
	end

end

function gridle_remote_dispatchinput(iotbl, override)
	local restbl = override and override or keyconfig:match(iotbl);
	
	if (restbl) then
		for ind,val in pairs(restbl) do
			print(val);
			if (settings.iodispatch[val] and iotbl.active) then
				settings.iodispatch[val](restbl, iotbl);
			elseif settings.connected then
				local msgstr = iotbl.active and "press:" or "release:";
				msgstr = msgstr .. val;
				net_push(settings.server, msgstr);
			end
		end
	end
	
end

gridle_remote_input = gridle_remote_dispatchinput;
