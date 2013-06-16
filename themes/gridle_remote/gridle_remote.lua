settings = {
	repeatrate = 200,
	connected = false,
	iodispatch = {},
	dispatch_stack = {},

-- persistent settings
	connect_host  = "Local Discovery",
	autoconnect   = "Off"
};

imagery = {};
soundmap = {};

local network_keymap = {
	"Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P", "7", "8", "9", "\n",
	"A", "S", "D", "F", "G", "H", "J", "K", "L", ":", "4", "5", "6", "\n",
	"Z", "X", "C", "V", "B", "N", "M", ".", "_", "0", "1", "2", "3", "\n"};

function gridle_remote()
	system_load("scripts/resourcefinder.lua")();
	system_load("scripts/keyconf.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/listview.lua")();
	system_load("scripts/osdkbd.lua")();
	system_load("gridle_shared.lua")();
	system_load("scripts/layout_editor.lua")();

	load_keys();

-- will either spawn the setup layout first or, if there already is one, spawn menu 
-- (which may or may not just autoconnect depending on settings)
	default_dispatch = {};

	default_dispatch["MENU_TOGGLE"] = function()
		reset_connection();
		spawn_mainmenu();
	end
	
	default_dispatch["MENU_ESCAPE"] = function()
		shutdown();
	end

	dispatch_push(default_dispatch, "default", gridleremote_netinput);
	setup_keys(function()
		if (settings.autoconnect == "On") then
			open_connection();
		else
			spawn_mainmenu();
		end
	end);
end

function open_connection()
	if (current_menu) then
		while (current_menu ~= nil) do 
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
		dispatch_pop();
	end
	
	if (settings.infowin) then
		settings.infowin:destroy();
		settings.infowin = nil;
	end
	
	if (valid_vid(settings.connection)) then
		delete_image(settings.connection);
	end

	local dst = nil;
	if (settings.connect_host == "Local Discovery") then
		settings.warningwin = spawn_warning("Looking for hosts on the local network", 1);
		dst = nil;
	else
		settings.warningwin = spawn_warning("Trying to connect to: " .. settings.connect_host, 1);
		dst = settings.connect_host;
	end
	
	settings.connection = net_open(dst, net_event);
end

function draw_infowin()
	if (settings.infowin ~= nil) then
		settings.infowin:destroy();
	end

	if (settings.menu_layout and not resource("layouts/" .. settings.menu_layout)) then
		settings.menu_layout = nil;
	end
	
	if (settings.ingame_layout and not resource("layouts/" .. settings.ingame_layout)) then
		settings.ingame_layout = nil;
	end
	
	local status = {};
	local undefline = "\\#ff0000Undefined\\#ffffff";
	
	table.insert(status, "Menu Layout:\\t ( " .. (settings.menu_layout ~= nil and settings.menu_layout or undefline) .. " )");
	table.insert(status, "Ingame Layout:\\t ( " .. (settings.ingame_layout ~= nil and settings.ingame_layout or undefline) .. " )");	
	table.insert(status, "Connection Method:\\t ( " .. (settings.connect_host ~= nil and settings.connect_host or undefline) .. " )");

	settings.infowin = listview_create( status, VRESW * 0.5, VRESH * 0.5, {} );
	settings.infowin.gsub_ignore = true;

	settings.infowin:show();
	hide_image(settings.infowin.cursorvid);
	move_image(settings.infowin.anchor, math.floor(VRESW * 0.2), math.floor(VRESH * 0.5));
end

function set_layout(layname, target, save)
	if (target == "menu" and resource("layouts/" .. layname)) then
		settings.menu_layout = layname;
		store_key("menu_layout", layname);

	elseif (target == "ingame" and resource("layouts/" .. layname)) then
		settings.ingame_layout = layname;
		store_key("ingame_layout", layname);
	end
	
	draw_infowin();
	settings.iodispatch["MENU_ESCAPE"]();
end

function spawn_mainmenu()
	while current_menu do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end

	draw_infowin();
	
-- Default Global Menus (and their triggers)
	local mainlbls     = {};
	local settingslbls = {"Reset Keyconfig"}; 
	local connectlbls  = {"Local Discovery", "Specify Server"};
	
	local connectptrs  = {};
	local mainptrs     = {};
	local settingsptrs = {};
	local settingsfmts = {};
	local laylbls      = {"New Layout"};
	local layptrs      = {};
	local layfmts      = {};

	layptrs["New Layout"] = define_layout;
	layfmts["New Layout"] = "\\b" .. settings.colourtable.notice_fontstr;
	
	add_submenu(mainlbls, mainptrs, "Layouts...", "_nokey", laylbls, layptrs, layfmts);
	add_submenu(mainlbls, mainptrs, "Connection Method...", "_nokey", connectlbls, connectptrs);
	add_submenu(mainlbls, mainptrs, "Settings...", "_nokey", settingslbls, settingsptrs, settingsfmts);
	
	local globlbl, globptrs = build_globmenu("layouts/*.lay", nil, THEME_RESOURCE);
	local globfmt = {};
	
	if (#globlbl > 0) then
		local ptrsa = {};
		local ptrsb = {};

		table.insert(laylbls, "------");
		for ind, val in ipairs(globlbl) do
			ptrsa[val] = function(lbl, save) set_layout(val, "menu");   end
			ptrsb[val] = function(lbl, save) set_layout(val, "ingame"); end
		end
	
		table.insert(laylbls, "Menu Layout...");
		table.insert(laylbls, "Ingame Layout...");

		layptrs["Menu Layout..."]   = function() menu_spawnmenu(globlbl, ptrsa, {}); end 
		layptrs["Ingame Layout..."] = function() menu_spawnmenu(globlbl, ptrsb, {}); end
	end
	
	add_submenu(settingslbls, settingsptrs, "Autoconnect...", "autoconnect", gen_tbl_menu("autoconnect", {"On", "Off"}, function(lbl)
		store_key("autoconnect", lbl); end, true));

	table.insert(mainlbls, "-------");
	table.insert(mainlbls, "Connect");
	mainptrs["Connect"] = open_connection;
	
	table.insert(mainlbls, "Shutdown");

	mainptrs["Shutdown"] = function()
		shutdown(); 
	end

	settingsptrs["Reset Keyconfig"] = function()
		keyconfig:destroy();
		zap_resource("keysym.lua");
		setup_keys(spawn_mainmenu);
	end
	settingsfmts["Reset Keyconfig"] = "\\b" .. settings.colourtable.alert_fontstr;
	
	connectptrs["Local Discovery"] = function()
		settings.connect_host = "Local Discovery";
		store_key("connect_host", settings.connect_host); 
		settings.iodispatch["MENU_ESCAPE"]();
		draw_infowin();
	end

	connectptrs["Specify Server"] = function()
-- spawn OSD and upon completion, explicit connection
		local osdconnkbd = osdkbd_create( osdkbd_extended_table(), opts );
		osdconnkbd:show();

-- do this here so we have access to the namespace where osdsavekbd exists
		dispatch_push({}, "osd keyboard", function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdconnkbd);
			
			if (complete) then
				osdconnkbd:destroy();
				dispatch_pop();
				
				if (resstr) then
					settings.connect_host = resstr;
					store_key("connect_host", settings.connect_host); 
					settings.iodispatch["MENU_ESCAPE"]();
					draw_infowin();
				end
			end
		end);
	end

	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;
	root_menu = current_menu;

	current_menu:show();
	move_image(current_menu.anchor, 10, VRESH * 0.1, 10);

	local imenu = {};
	menu_defaultdispatch(imenu);
	local def_esc = imenu["MENU_ESCAPE"];
	imenu["MENU_ESCAPE"] = function() if (not current_menu or current_menu.parent == nil) then return; else def_esc(); end end
	imenu["MENU_LEFT"] = imenu["MENU_ESCAPE"];
	dispatch_push( imenu, "connection menu" );
end

function load_cb(restype, lay, laytbl)
	if (restype == LAYRES_STATIC) then
		if (lay.idtag == "background") then
			return "backgrounds/" .. lay.res, (function(newvid) settings.background = newvid; end);
			
		elseif (lay.idtag == "image") then
			return "images/" .. lay.res;
		end
	end

-- don't progress until we have a data-source set
	if (laytbl == nil) then
		return nil;
	end

	if (restype == LAYRES_IMAGE or restype == LAYRES_FRAMESERVER) then
		local locfun = laytbl.restbl["find_" .. lay.idtag];
		if (locfun ~= nil) then
			return locfun(laytbl.restbl);
		end

	elseif (restype == LAYRES_TEXT) then
		return laytbl[lay.idtag];
	end

end

function activate_layout(laytgt, cur_item)
	if (laytgt == nil or cur_item == nil) then
		return;
	end
	
	local restbl = resourcefinder_search(cur_item, true);
	cur_item.restbl = restbl;

-- load a new layout if we have to
	if (settings.layout ~= nil and laytgt ~= settings.lastlayout) then
		settings.layout:destroy();
		settings.layout = nil;
	end

-- need to create from scratch
	if (settings.layout == nil) then
		settings.lastlayout = "layouts/" .. laytgt;	
		settings.layout = layout_load(settings.lastlayout, function(restype, lay)
			return load_cb(restype, lay, cur_item); 
			end);
	end

-- :show takes care of updating what is necessary
	if (settings.layout) then
		settings.layout:show();
		if (settings.layout["bgeffect"]) then 
			update_shader(settings.layout["bgeffect"][1] and settings.layout["bgeffect"][1].res);
		end
	end
end

function decode_message(msg)
-- format matches broadcast_game in gridle.lua
	nitem = string.split(msg, ":")
	
	if (nitem[1] == "playing" or nitem[1] == "selected") then
		dstlay = nitem[1] == "playing" and settings.ingame_layout or settings.menu_layout;
		
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
				activate_layout(dstlay, settings.cur_item);
			end
		end
	end

end

function net_event(source, tbl)
	if (tbl.kind == "connected") then
		if (settings.warningwin) then
			settings.warningwin:destroy();
			settings.warningwin = nil;
		end
	
		settings.connected = true;
		dispatch_push(default_dispatch, "network input", gridleremote_netinput);

		net_push(source, "players:", keyconfig.player_count);
		spawn_warning("Connected");

	elseif (tbl.kind == "message") then
		decode_message(tbl.message);

	elseif (tbl.kind == "frameserver_terminated") then
		reset_connection();
	else
		print(tbl.kind);
	end
	
end

function reset_connection()
	if (valid_vid(settings.connection)) then
		delete_image(settings.connection);
	end

	if (settings.warningwin) then
		settings.warningwin:destroy();
		settings.warningwin = nil;
	end
	
	if (settings.infowin) then
		settings.infowin:destroy();
		settings.infowin = nil;
	end

	if (settings.layout) then
		settings.layout:destroy();
		settings.layout = nil;
	end
	
	settings.connection = nil;
	settings.connected = false;
	
	spawn_mainmenu();
	spawn_warning("Networking session terminated");
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

function setup_keys( trigger )
-- rREMOTE_ESCAPE gets remapped to MENU_ESCAPE
	local keylabels = { "", "rMENU_UP", "rMENU_DOWN", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_SELECT", "rMENU_TOGGLE", 
		"rREMOTE_MENU", "rREMOTE_ESCAPE", "aMOUSE_X", "aMOUSE_Y", " CONTEXT", " FLAG_FAVORITE", " OSD_KEYBOARD", " QUICKSAVE", " QUICKLOAD"};

-- prepare a keyconfig that support the specified set of labels (could be nil and get a default one)
	keyconfig = keyconf_create(keylabels);

	if (keyconfig.active) then
		trigger();
	else
		keyconfig:to_front();
		dispatch_push({}, "key config", function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				dispatch_pop();
				trigger();
			end
		end);
	end

end

-- the load_key_* functions doesn't store immediately, but cache whatever is not "found" etc.
-- in a key_cache which is pushed simulatenously, since the database function syncs(!)
function load_keys()
	key_queue = {};

	load_key_str("menu_layout",   "menu_layout",   settings.menu_layout);
	load_key_str("ingame_layout", "ingame_layout", settings.ingame_layout);
	load_key_str("autoconnect",  "autoconnect",   settings.autoconnect);
	load_key_str("connect_host",  "connect_host",  settings.connect_host);
		
	if #key_queue > 0 then
		store_key(key_queue);
	end
end

function gridleremote_netinput(iotbl)
	local restbl = keyconfig:match(iotbl);

-- since "local" menu and "remote" menu are mutually exclusive, we can re-use the bindings for those,
-- thus then "netinput" is pushed unto the dispatch stack, all the regular "local menu" keys are dropped from their
-- dispatch table
	if (restbl) then
		for ind, val in pairs(restbl) do
			if (settings.iodispatch[val]) then
				settings.iodispatch[val]();

			elseif valid_vid(settings.connection) then
				if (val == "REMOTE_MENU")   then val = "MENU_TOGGLE"; end
				if (val == "REMOTE_ESCAPE") then val = "MENU_ESCAPE"; end
				
				if (iotbl.kind == "analog") then
					net_push(settings.connection, "move:" .. val .. ":" .. tostring(iotbl.samples[1]));
				else
					net_push(settings.connection, iotbl.active and ("press:" .. val) or ("release:" .. val));
				end

			end
		end
	end

end

function define_layout()
	local osdsavekbd = osdkbd_create( osdkbd_alphanum_table(), opts );
	osdsavekbd:show();

-- do this here so we have access to the namespace where osdsavekbd exists
	dispatch_push({}, "osdkbd (layout)", function(iotbl)
		complete, resstr = osdkbd_inputfun(iotbl, osdsavekbd);
	
		if (complete) then
			osdsavekbd:destroy();
			osdsavekbd = nil;

			dispatch_pop();
			if (resstr ~= nil and string.len(resstr) > 0) then
				if (string.sub(resstr, -4, -1) ~= ".lay") then
					resstr = resstr .. ".lay";
				end
				lay_setup("layouts/" .. resstr);
			end

		end

	end, -1);
end

function lay_setup(layname)
	while current_menu ~= nil do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end
	
	if settings.infowin then
		settings.infowin:destroy();
		settings.infowin = nil;
	end

	local identtext = function(key)
		vid = render_text(settings.colourtable.label_fontstr .. key);
		return vid;
	end

	local identphold = function(key)
		vid = load_image("images/placeholders/" .. string.lower(key) .. ".png");
		if (not valid_vid(vid)) then
			vid = fill_surface(64, 64, math.random(128), math.random(128), math.random(128));
			image_tracetag(vid, "placeholder" .. key);
		end
		return vid;
	end
	
	layout = layout_new(layname);
	layout:add_resource("background", "Background...", function() return glob_resource("backgrounds/*.png"); end, nil, LAYRES_STATIC, true, function(key) return load_image("backgrounds/" .. key); end);
	layout:add_resource("bgeffect", "Background Effect...", function() return glob_resource("shaders/bgeffects/*.fShader"); end, nil, LAYRES_SPECIAL, true, nil);
	layout:add_resource("movie", "Movie", "Movie", "Dynamic Media...", LAYRES_FRAMESERVER, false, identphold);
	layout:add_resource("image", "Image...", function() return glob_resource("images/*.png"); end, nil, LAYRES_STATIC, false, function(key) return load_image("images/" .. key); end);
	for ind, val in ipairs( {"Screenshot", "Boxart", "Boxart (Back)", "Fanart", "Bezel", "Marquee"} ) do
		layout:add_resource(string.lower(val), val, val, "Dynamic Media...", LAYRES_IMAGE, false, identphold);
	end

--	layout:add_resource("model", "Model", "Model", "Dynamic Media...", LAYRES_MODEL, false, function(key) return load_model("placeholder"); end );

	for ind, val in ipairs( {"Title", "Genre", "Subgenre", "Setname", "Manufacturer", "Buttons", "Players", "Year", "Target", "System"} ) do
		layout:add_resource(string.lower(val), val, val, "Dynamic Text...", LAYRES_TEXT, false, nil);
	end
	
	layout.post_save_hook = hookfun;

	layout.finalizer = function(state)
		spawn_mainmenu();
	end

	layout.validation_hook = function() return true; end

	layout:show();
end

function hookfun(newitem)
-- autotile!
	if (newitem.idtag == "background") then
		local props = image_surface_initial_properties(newitem.vid);
		if (props.width / VRESW < 0.3 and newitem.tile_h == 1) then
			newitem.tile_h = math.ceil(VRESW / props.width);
		end

		if (props.height / VRESH < 0.3 and newitem.tile_v == 1) then
			newitem.tile_v = math.ceil(VRESH / props.height);
		end

		newitem.zv = 1;
		newitem.x  = 0;
		newitem.y  = 0;
		newitem.width  = VRESW;
		newitem.height = VRESH;

		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, newitem.vid);
		settings.background = newitem.vid;
		newitem:update();

	elseif (newitem.idtag == "bgeffect") then
		update_shader(newitem.res);
	end
end

function update_shader(resname)
	if (not resname) then
		return;
	end

	settings.shader = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. resname, "bgeffect", {});
	image_shader(settings.background, settings.shader);
	shader_uniform(settings.shader, "display", "ff", PERSIST, VRESW, VRESH);
	
	if (valid_vid(settings.background)) then
		image_shader(settings.background, settings.shader);
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
