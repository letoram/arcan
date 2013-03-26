--
-- Development test-script for the layout config tool
--
settings = {
	stream_url  = "rtmp://",
	record_fps  = 30,
	record_qual = 8,
	record_res  = 480
};

soundmap = {};

local recstr = "libvorbis:vcodec=H264:container=stream:acodec=MP3:streamdst=" .. string.gsub(settings.stream_url and settings.stream_url or "", ":", "\t");

function streamer()
--listview.lua, osdkbd.lua, dialog.lua, colourtable.lu	
	system_load("scripts/listview.lua")();       -- used by menus (_menus, _intmenus) and key/ledconf
	system_load("scripts/keyconf.lua")();        -- input configuration dialogs
	system_load("scripts/3dsupport.lua")();     
	system_load("scripts/layout_editor.lua")();  -- used to define layouts
	system_load("scripts/osdkbd.lua")();         -- for defining stream destination
	system_load("scripts/calltrace.lua")();

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
				toggle_main_menu();
			end
		end, 0);

	else
		toggle_main_menu();
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

-- this parses the currently active layout (if any) and generates the appropriate menu entries 
function toggle_main_menu()
	if (current_menu) then
		current_menu:destroy();
		current_menu = nil;
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
	table.insert(streammenu, "Define Stream...");
	
	add_submenu(menulbls, menuptrs, "Settings...", nil, streammenu, streamptrs, {});
	
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
	if (settings.layout) then
	end

-- without stream
	if (settings.stream_dst) then
	end

	table.insert(menulbls, "--------");
	table.insert(menulbls, "Quit");
	menuptrs["Quit"] = shutdown;
	
-- if everything is set up correctly, let the user start 
	if (settings.layout and settings.stream_url ~= "rtmp://") then
		table.insert(menulbls, "Start Streaming");
		streamfmts["Start Streaming"] = [[\b\#00ff00]];
	end
	
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
end

function load_layout(lay)
	print("switch to: ", lay);
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
			lay_setup(resstr);
			end
		end

	end, -1);
end

function gen_layout_menu()
	local laymenu, layptrs = build_globmenu("layouts/*.lay", load_layout, THEME_RESOURCE);
	local layfmt = {};

	table.insert(laymenu, 1, "New Layout");
	layptrs["New Layout"] = define_layout;
	layfmt["New Layout"]  = [[\b]];

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
	layout.finalizer = toggle_main_menu; 
	layout:show();
end

-- the shared code partially uses this, since the soundmap is empty, just stop sources that are null.
local oldplay = play_audio;
function play_audio(source)
	if (source) then
		oldplay(source);
	end
end