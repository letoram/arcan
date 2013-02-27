settings = {
	repeatrate = 200,
	connected = false,
	iodispatch = {},
	dispatch_stack = {}
};

imagery = {};

function gridle_remote()
	system_load("scripts/resourcefinder.lua")();
	system_load("scripts/keyconf.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/listview.lua")();
	system_load("scripts/osdkbd.lua")();
	system_load("remote_config.lua")();

-- rREMOTE_ESCAPE gets remapped to MENU_ESCAPE
	local keylabels = { "", "rMENU_TOGGLE", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_UP", "rMENU_DOWN", "rMENU_SELECT", 
		"rREMOTE_MENU", "rREMOTE_ESCAPE", "aMOUSE_X", "aMOUSE_Y", " CONTEXT", " FLAG_FAVORITE", " OSD_KEYBOARD", " QUICKSAVE", " QUICKLOAD"};

-- prepare a keyconfig that support the specified set of labels (could be nil and get a default one)
	keyconfig = keyconf_create(keylabels);
	
-- will either spawn the setup layout first or, if there already is one, spawn menu (which may or may not just autoconnect
-- depending on settings) 
	default_dispatch = {};
	default_dispatch["MENU_TOGGLE"] = function()
		spawn_mainmenu();
	end
	
	default_dispatch["MENU_ESCAPE"] = function()
		shutdown();
	end

	dispatch_push(default_dispatch, "default", gridleremote_netinput);
	
	setup_keys( function() gridleremote_layouted( setup_complete ) end );
end

function open_connection(dst)
	if (valid_vid(settings.connection)) then
		delete_image(settings.connection);
	end
	
	spawn_warning("Connecting To: " .. ( (dst == nil) and "local discovery" or dst), 70, math.floor(VRESH * 0.3));
	settings.connection = net_open(dst, net_event);
end

function dispatch_push(tbl, name, triggerfun)
	local newtbl = {};
	newtbl.table = tbl;
	newtbl.name = name;
	newtbl.dispfun = triggerfun and triggerfun or gridle_remote_dispatchinput;
	
	table.insert(settings.dispatch_stack, newtbl);
	settings.iodispatch = tbl;
	gridle_remote_input = newtbl.dispfun;
end

function dispatch_pop()
	if (#settings.dispatch_stack <= 1) then
		settings.dispatch = {};
		gridle_remote_input = gridle_dispatchinput;
	else
		table.remove(settings.dispatch_stack, #settings.dispatch_stack);
		local last = settings.dispatch_stack[#settings.dispatch_stack];

		settings.iodispatch = last.table;
		gridle_remote_input = last.dispfun;
	end

end

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
	
	table.insert(mainlbls, "---");
	table.insert(mainlbls, "Shutdown");

	mainptrs["Shutdown"] = function()
		shutdown(); 
	end

	settingsptrs["Reset Layout"] = function()
		zap_resource(layouted.layoutfile);

		while current_menu ~= nil do
			current_menu:destroy();
			current_menu = current_menu.parent;
		end

		pop_video_context();

		settings.server = nil;
		gridleremote_layouted( setup_complete );
	end

	settingsptrs["Reset Keyconfig"] = function()
		zap_resource("keysym.lua");
		setup_keys( setup_complete );
	end

	connectptrs["Local Discovery"] = function()
		settings.connect_method = "local discovery";
		open_connection();
		settings.iodispatch["MENU_ESCAPE"]();
	end

	connectptrs["Specify Server"] = function()
-- spawn OSD and upon completion, explicit connection
		osdkbd:show();
-- do this here so we have access to the namespace where osdsavekbd exists
		dispatch_push({}, "osd keyboard", function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdkbd);

			if (complete) then
				osdkbd:hide();
				dispatch_pop();
				open_connection(resstr);
			end
		end);
	end

	if (valid_vid(settings.server)) then
		table.insert(connectlbls, "Autoconnect (On)");
		table.insert(connectlbls, "Autoconnect (Off)");
		connectptrs["Autoconnect (On)"] = function() store_key("autoconnect", settings.connect_method); end
		connectptrs["Autoconnect (Off)"] = function() delete_key("autoconnect"); end
	end
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;
	root_menu = current_menu;

	current_menu:show();
	move_image(current_menu.anchor, 10, VRESH * 0.1, 10);

	local imenu = {};
	menu_defaultdispatch(imenu);
	dispatch_push( imenu, "connection menu" );
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

function decode_message(msg)
-- format matches broadcast_game in gridle.lua
	nitem = string.split(msg, ":")

	if (nitem[1] == "begin_item") then
		settings.cur_item = {};
		settings.item_count = tonumber(nitem[2]);
		last_key = nil;

	elseif (settings.item_count) then
		if (last_key == nil) then
			last_key = msg;
		else
			settings.cur_item[last_key] = msg;
			last_key = nil;
			settings.item_count = settings.item_count - 1;
			if (settings.item_count <= 0) then
				settings.item_count = nil;
				gridleremote_updatedynamic(settings.cur_item);
			end
		end
	end

end

function drop_menu()
	dispatch_pop();

	while current_menu ~= nil do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end
end

function net_event(source, tbl)
	if (tbl.kind == "connected") then
		settings.connected = true;
		drop_menu();
		dispatch_push(default_dispatch, "network input", gridleremote_netinput);

		net_push(source, "players:", keyconfig.player_count);
		spawn_warning("Connected", 125);

	elseif (tbl.kind == "message") then
		decode_message(tbl.message);

	elseif (tbl.kind == "frameserver_terminated") then
		settings.connected = false;
		delete_image(settings.connection);
		settings.connection = nil;

		show_image(imagery.disconnected);
		blend_image(imagery.disconnected, 1.0, 30);
		blend_image(imagery.disconnected, 0.0, 10);

		spawn_mainmenu();
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

function spawn_warning( message, expiration, yv )
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
		expire_image(infowin.anchor, expiration);
		blend_image(infowin.window, 1.0, expiration * 0.8);
		blend_image(infowin.window, 0.0, expiration * 0.2);
	end

	local x = math.floor( 0.5 * (VRESW - image_surface_properties(infowin.border, 100).width)  );
	local y = (yv ~= nil) and yv or math.floor( 0.5 * (VRESH - image_surface_properties(infowin.border, 100).height) );
	
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

function setup_complete()
	spawn_mainmenu();

	imagery.disconnected = load_image("images/disconnected.png");
	local props = image_surface_properties(imagery.disconnected);
	if (props.width > VRESW)  then props.width = VRESW;  end
	if (props.height > VRESH) then props.height = VRESH; end
	
	local keymap = {
		"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "7", "8", "9", "\n",
		"A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "4", "5", "6", "\n",
		"Z", "X", "C", "V", "B", "N", "M", ".", "_", "0", "1", "2", "3", "\n"};

	osdkbd = osdkbd_create( keymap, {case_insensitive = false} ); --keymap);
end

function setup_keys( trigger )
-- if active, then there's nothing needed to be done, else we need a UI to help.
	if (keyconfig.active == false) then
		keyconfig:to_front();
		dispatch_push({}, "key config", function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				dispatch_pop();
				trigger();
			end
		end);

	else
		trigger();
	end

end

function gridleremote_netinput(iotbl)
	local restbl = keyconfig:match(iotbl);

	if (restbl) then
		for ind, val in pairs(restbl) do
			if (settings.iodispatch[val]) then
				settings.iodispatch[val]();

			elseif valid_vid(settings.connection) then

				if (iotbl.kind == "analog") then
					net_push(settings.connection, "move:" .. val .. ":" .. tostring(iotbl.samples[1]));
				else
					net_push(settings.connection, iotbl.active and ("press:" .. val) or ("release:" .. val));
				end

			end
		end
	end

end

function gridle_remote_dispatchinput(iotbl)
	local restbl = keyconfig:match(iotbl);
	
	if (restbl) then
		for ind,val in pairs(restbl) do
			if (settings.iodispatch[val] and iotbl.active) then
				settings.iodispatch[val](restbl, iotbl);
			end
		end
	end
	
end