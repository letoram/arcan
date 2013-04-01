--
-- Development test-script for the layout config tool
--
settings = {
	stream_url  = "rtmp://",
	record_fps  = 30,
	record_qual = 6,
	record_res  = 480,
	record_vpts = 0
};

soundmap = {};

function get_recstr()
	local recstr    = "libvorbis:vcodec=H264:container=stream:acodec=MP3:fps=%d:apreset=%d:vpreset=%d:streamdst=";
	local streamdst = string.gsub(settings.stream_url and settings.stream_url or "", ":", "\t");
	
	return string.format(recstr, settings.fps, settings.record_qual, settings.record_qual, streamdst);
end

function streamer()
--listview.lua, osdkbd.lua, dialog.lua, colourtable.lu	
	system_load("scripts/listview.lua")();       -- used by menus (_menus, _intmenus) and key/ledconf
	system_load("scripts/keyconf.lua")();        -- input configuration dialogs
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/layout_editor.lua")();  -- used to define layouts
	system_load("scripts/osdkbd.lua")();         -- for defining stream destination
	system_load("scripts/calltrace.lua")();
	system_load("scripts/resourcefinder.lua")(); 

	system_load("shared.lua")();

	dispatch_push({}, "default", nil, 200);
	setup_3dsupport();

-- regular setup patterns for the necessary inputs
	keyconfig = keyconf_create({"rMENU_ESCAPE", "rMENU_UP", "rMENU_DOWN", "rMENU_LEFT", "rMENU_RIGHT", "rMENU_SELECT", "rCONTEXT", "aMOUSE_X", "aMOUSE_Y"});
	if (keyconfig.active == false) then
		keyconfig:to_front();
		dispatch_push({}, "keyconfig (full)", function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				dispatch_pop();
				toggle_main_menu(false, 0);
			end
		end, 0);

	else
		toggle_main_menu(false, 0);
	end
end

-- copied from gridle
function osdkbd_inputfun(iotbl, dstkbd)
	local restbl = keyconfig:match(iotbl);
	local done   = false;
	local resstr = nil;
	
	if (restbl) then
		for ind,val in pairs(restbl) do
			if (val == "MENU_ESCAPE" and iotbl.active) then
				play_audio(soundmap["OSDKBD_HIDE"]);
				return true, nil

			elseif (val == "MENU_SELECT" or val == "MENU_UP" or val == "MENU_LEFT" or
				val == "MENU_RIGHT" or val == "MENU_DOWN" or val == "CONTEXT") then
				resstr = dstkbd:input(val, iotbl.active);

				if (iotbl.active) then
					play_audio(val == "MENU_SELECT" and soundmap["OSDKBD_SELECT"] or soundmap["OSDKBD_MOVE"]);
				end
				
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
	
	return false, nil;
end

--
-- show helper icons
-- (a) is there a layout?
-- (b) are there any input sources?
-- (c) have a stream been set up?
--
function show_helper()
	print(settings.gametbl);
end

--
-- this parses the currently active layout (if any) and generates the appropriate menu entries
-- depends on current layout (if any), target in layout, vidcap feeds in layout
--
function toggle_main_menu(target, nvc)
	while current_menu ~= nil do
		current_menu:destroy();
		dispatch_pop();
		current_menu = current_menu.parent;
	end
	
	local menulbls = {"Layouts...", };
	local menuptrs = {};
	local menufmts = {};

	menuptrs["Layouts..."] = gen_layout_menu;

	local streammenu = {};
	local streamptrs = {};
	local streamfmts = {};

	add_submenu(streammenu, streamptrs, "Framerate...", "record_fps", gen_tbl_menu("record_fps", {12, 24, 25, 30, 50, 60}, function() end));
	add_submenu(streammenu, streamptrs, "Max Vertical Resolution...", "record_res", gen_tbl_menu("record_res", {720, 576, 480, 360, 288, 240}, function() end));
	add_submenu(streammenu, streamptrs, "Quality...", "record_qual", gen_tbl_menu("record_qual", {2, 4, 6, 8, 10}, function() end));
	add_submenu(streammenu, streamptrs, "VPTS offset...", "record_vpts", gen_num_menu("record_vpts", 0, 4, 12, function() end));
	table.insert(streammenu, "Define Stream...");

	if (settings.layout ~= nil) then
		add_submenu(menulbls, menuptrs, "Streaming Settings...", nil, streammenu, streamptrs, {});
	end

-- copied from gridle internal
	streamptrs["Define Stream..."] = function(label, store)
		local resstr = nil;
		local opts = {};

		opts.case_insensitive = false;
		opts.prefix = "rtmp://";
		opts.startstr = settings.stream_url;

-- quick hack to make it slightly easier to enter "big and nasty justin.tv kind" keys
		if (settings.stream_url == "rtmp://" and resource("stream.key")) then
			if (open_rawresource("stream.key")) then
				local line = read_rawresource();
				if (line ~= nil and string.len(line) > 0) then
					opts.startstr = line;
				end
				close_rawresource();
			end
		end

		local osdsavekbd = osdkbd_create( osdkbd_extended_table(), opts );
		osdsavekbd:show();

-- do this here so we have access to the namespace where osdsavekbd exists
		dispatch_push({}, "osdkbd (streaming)", function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdsavekbd);
	
			if (complete) then
				osdsavekbd:destroy();
				osdsavekbd = nil;
				dispatch_pop();
				if (resstr ~= nil and string.len(resstr) > 0) then
					settings.stream_url = resstr;
					store_key("stream_url", resstr);
				end
			end
		end
		, -1);
	end
	
	add_submenu(menulbls, menuptrs, "Streaming...", streammenu, streamptrs, {});

-- need a layout set in order to know what to define the different slots as
	if (target) then
		add_submenu(menulbls, menuptrs, "Setup Game...", nil, gen_tbl_menu(nil, list_targets(), list_targetgames, true));
	end

	if (nvc > 0) then
		local ptrs = {};
		local lbls = {};
		settings.vidcap = {};

		for num=1, nvc do
			add_submenu(lbls, ptrs, "Slot " .. tostring(num) .. "...", nil, gen_num_menu(nil, 1, 1, 10, function(lbl) settings.vidcap[nvc] = tonumber(bl); end ));
		end
		
		add_submenu(menulbls, menuptrs, "Video Feeds...", nil, lbls, ptrs, {});
	end

-- if everything is set up correctly, let the user start 
	if (settings.ready) then 
		table.insert(menulbls, "Start Streaming");
		menufmts["Start Streaming"] = [[\b\#00ff00]];
	end

	table.insert(menulbls, "--------");
	table.insert(menulbls, "Quit");
	menuptrs["Quit"] = shutdown;
	menufmts["Quit"] = [[\#ff0000]];
	
-- finally, activate (but don't allow escape to terminate)
	local imenu = {};
	local escape_menu = function(label, save, sound)
		if (current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
			if (sound == nil or sound == false) then 
				play_audio(soundmap["MENU_FADE"]); 
			end
		end
	end
	
	imenu["MENU_LEFT"]   = escape_menu;
	imenu["MENU_ESCAPE"] = escape_menu;
	
	current_menu = listview_create(menulbls, VRESH * 0.9, VRESW / 3, fmts);
	current_menu.ptrs = menuptrs;
	current_menu.parent = nil;
	menu_defaultdispatch(imenu);
	dispatch_push(imenu, "streamer_main", nil, -1);

	current_menu:show();
	show_helper();
end

--
-- Will be triggered everytime the layout editor rebuilds its view
-- Mostly expect the script to resolve a full resource description based on type and idtag
-- Although some properties could be altered "in flight" and LAYRES_SPECIAL are even expected to be
--
function load_cb(restype, lay)
	if (restype == LAYRES_STATIC) then
		if (lay.idtag == "background") then
			return "backgrounds/" .. lay.res, (function(newvid) settings.background = newvid; end);
			
		elseif (lay.idtag == "image") then
			return "images/" .. lay.res;
		end
	end

-- don't progress until we have a data-source set
	if (settings.restbl == nil) then
		return nil;
	end

	if (restype == LAYRES_IMAGE or restype == LAYRES_FRAMESERVER) then

		local locfun = settings.restbl["find_" .. lay.idtag];
		if (locfun ~= nil) then
			return locfun(settings.restbl);
		end

	elseif (restype == LAYRES_TEXT) then
		return settings.gametbl[lay.idtag];
	end

end

function run_view()
	settings.layout:show();

-- NOTE:For creating the record-set, the temporary and temporary_static tables are swept
-- and just re-added. When (if?) MRT or WORLDID recordsets are working, we'll switch to that
--
	if (settings.layout["internal"] and #settings.layout["internal"] > 0) then
		local internal_vid = launch_target(settings.gametbl.gameid, LAUNCH_INTERNAL, function(source, status) end);
		settings.layout:add_imagevid(internal_vid, settings.layout["internal"][1]);

-- reuse the VID if we have clones, same with models and "display" ID
		if (#settings.layout["internal"] > 1) then
			for i=2, #settings.layout["internal"] do
				local newvid = instance_image(internal_vid);
				image_mask_clearall(newvid);
				settings.layout:add_imagevid(newvid, settings.layout["internal"][i]);
			end
		end

	end

	if (settings.layout["bgeffect"]) then
		update_shader(settings.layout["bgeffect"][1].res);
	end
end

function setup_game(label)
	local game = list_games({target = settings.current_target, game = label});

	if (game and game[1]) then
		settings.gametbl = game[1];
		local restbl = resourcefinder_search(settings.gametbl, true );
		settings.restbl = restbl;
		run_view();
	end
end

function list_targetgames(label)
	gamelist = {};
	games = list_games({target = label});

	if not games or #games == 0 then return; end
	for ind, tbl in ipairs(games) do table.insert(gamelist, tbl.title); end
	
	settings.current_target = label;
	lbls, ptrs = gen_tbl_menu(nil, gamelist, setup_game, true);
	menu_spawnmenu(lbls, ptrs, {});
end

function load_layout(lay)
	if (settings.layout) then
		settings.layout:destroy();
		settings.layout = nil;
	end

	settings.layout = layout_load("layouts/" .. lay, load_cb);
	if (settings.layout ~= nil) then
		toggle_main_menu(settings.layout["internal"] ~= nil and (#settings.layout["internal"] > 0), settings.layout["vidcap"] and #settings.layout["vidcap"] or 0);
	else
		spawn_warning("Couldn't load layout: " .. lay);
		toggle_main_menu(false, 0);
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

function gen_layout_menu()
	local laymenu, layptrs = build_globmenu("layouts/*.lay", load_layout, THEME_RESOURCE);
	local layfmt = {};

	table.insert(laymenu, 1, "New Layout");
	table.insert(laymenu, 2, "----------");
	layptrs["New Layout"] = define_layout;
	layfmt["New Layout"]  = [[\b\#00ff00]];
	menu_spawnmenu(laymenu, layptrs, layfmt);
end

function update_shader(resname)
-- (when here, something goes bad?!)	settings.shader = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. resname, "bgeffect", {});
	if (valid_vid(settings.background)) then
		settings.shader = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. resname, "bgeffect", {});
		image_shader(settings.background, settings.shader);
		shader_uniform(settings.shader, "display", "ff", PERSIST, VRESW, VRESH);
	end
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
		settings.background = newitem.vid;
		newitem:update();

	elseif (newitem.idtag == "bgeffect") then
		update_shader(newitem.res);
	end

end

function lay_setup(layname)
	while current_menu ~= nil do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end

	local identtext = function(key)
		vid = render_text(settings.colourtable.label_fontstr .. key);
		return vid;
	end

	local identphold = function(key)
		vid = load_image("images/placeholders/" .. string.lower(key) .. ".png");
		if (not valid_vid(vid)) then
			vid = fill_surface(64, 64, math.random(128), math.random(128), math.random(128));
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

	layout:add_resource("model", "Model", "Model", "Dynamic Media...", LAYRES_MODEL, false, function(key) return load_model("placeholder"); end );

	for ind, val in ipairs( {"Title", "Genre", "Subgenre", "Setname", "Manufacturer", "Buttons", "Players", "Year", "Target", "System"} ) do
		layout:add_resource(string.lower(val), val, val, "Dynamic Text...", LAYRES_TEXT, false, nil);
	end
	
	layout:add_resource("internal", "internal", "Internal Launch", "Input Feeds...", LAYRES_FRAMESERVER, false, load_image("images/placeholders/internal.png"));
	layout:add_resource("vidcap", "vidcap", "Video Capture", "Input Feeds...", LAYRES_FRAMESERVER, false, load_image("images/placeholders/vidcap.png"));
	layout.post_save_hook = hookfun;

	layout.finalizer = function(state)
		if (state) then
			load_layout(string.sub(layname, 9));
		else
			toggle_main_menu(false, 0);
		end
	end

	layout.validation_hook = function()
		for ind, val in ipairs(layout.items) do
			if (val.idtag == "internal" or val.idtag == "vidcap") then
				return true;
			end
		end

		return false;
	end

	layout:show();
end

-- the shared code partially uses this, since the soundmap is empty, just stop sources that are null.
local oldplay = play_audio;
function play_audio(source)
	if (source) then
		oldplay(source);
	end
end