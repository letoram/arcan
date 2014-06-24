--
-- Development test-script for the layout config tool
--
settings = {
	out_url     = "rtmp://",
	record_fps  = 30,
	record_vqual= 6,
	record_aqual= 4,
	record_res  = 480,
	record_vpts = 12,
	record_apts = 0
};

soundmap = {};

function get_recstr()
	local recstr = "vcodec=H264:container=%s:acodec=MP3:fps=%d:" ..
		"apreset=%d:vpreset=%d:vptsofs=%d:aptsofs=%d%s";
	local fname  = "";
	local args   = "";

	if (string.sub(settings.out_url, 1, 7) == "rtmp://") then
		fname = "stream";
		args  = string.format(recstr, "stream", settings.record_fps,
			settings.record_aqual, settings.record_vqual,
			settings.record_vpts, settings.record_apts,
				":streamdst=" .. string.gsub(settings.out_url, ":", "\t"));

	elseif (string.sub(settings.out_url, 1, 7) == "file://") then
		fname = string.sub(settings.out_url, 8);
		args  = string.format(recstr, "MKV", settings.record_fps,
			settings.record_aqual, settings.record_vqual,
			settings.record_vpts, settings.record_apts, "");
	end

	return fname, args;
end

function streamer()
	system_load("scripts/listview.lua")();
	system_load("scripts/keyconf.lua")();       -- input configuration dialogs
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/layout_editor.lua")(); -- used to define layouts
	system_load("scripts/osdkbd.lua")();        -- for defining stream destination
	system_load("scripts/calltrace.lua")();
	system_load("scripts/resourcefinder.lua")();
	system_load("scripts/calltrace.lua")();
	system_load("shared.lua")();

	dispatch_push({}, "default", nil, 200);
	setup_3dsupport();

	settings.adevs = list_audio_inputs();

-- regular setup patterns for the necessary inputs
	keyconfig = keyconf_create({"rMENU_ESCAPE",
		"rMENU_UP", "rMENU_DOWN", "rMENU_LEFT",
		"rMENU_RIGHT", "rMENU_SELECT", "rCONTEXT", "aMOUSE_X", "aMOUSE_Y"});

	if (keyconfig.active == false) then
		keyconfig:to_front();
		dispatch_push({}, "keyconfig (full)", function(iotbl)
			if (keyconfig:input(iotbl) == true) then
				dispatch_pop();
				toggle_main_menu(false, 0);
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
					play_audio(val == "MENU_SELECT" and
						soundmap["OSDKBD_SELECT"] or soundmap["OSDKBD_MOVE"]);
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

function show_helper()
	if (settings.infowin) then
		settings.infowin:destroy();
		settings.infowin = nil;
	end

	local status = {};
	local statusfmt = {};

	if (settings.layout) then
		table.insert(status, string.format("Layout (%s) Loaded", settings.layout_name));

		if (settings.layout["internal"] ~= nil) then
			if (settings.gametbl) then
				table.insert(status, "Game:" .. settings.gametbl.title);
			else
				table.insert(status, "No Game Defined");
				statusfmt["No Game Defined"] = "\\b\\#ff9999";
			end
		else
			table.insert(status, "No Internal Slot");
		end

		if (settings.layout["vidcap"] ~= nil) then
			table.insert(status, tostring(#settings.layout["vidcap"])
				.. " Video Feed Slots");
			local str = "Feeds: ";

			for ind, val in ipairs(settings.layout["vidcap"]) do
				str = str .. string.format("(%d) => (%d)", ind,
					settings.vidcap[ind] ~= nil and settings.vidcap[ind] or 0);
			end

			table.insert(status, str);
		end

		if (settings.out_url ~= "rtmp://") then
			local streamlbl = "Stream to:" .. settings.out_url;
			table.insert(status, streamlbl);
			statusfmt[streamlbl] = "\\b\\#99ff99";
		else
			table.insert(status, "No Stream Defined");
			statusfmt["No Stream Defined"] = "\\b\\#ff9999";
		end

	else
		table.insert(status, "No Layout");
	end

	settings.infowin = listview_create( status, VRESW / 2, VRESH / 2, statusfmt );
	settings.infowin:show();
	hide_image(settings.infowin.cursorvid);
	move_image(settings.infowin.anchor, VRESW * 0.5, 0);
end

--
-- game should already be running,
-- load and add video capture devices based on the mapping in settings
-- populate static / dynamic images into a shared recordtarget
--
function start_streaming()
	if (not run_view(false)) then
		toggle_main_menu();
		return;
	end

-- allocate intermediate storage
	local dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
	image_tracetag(dstvid, "[streaming source]");

	local recordset = {};
	for ind,val in ipairs(settings.layout.temporary) do
		table.insert(recordset, val);
	end

	for ind, val in ipairs(settings.layout.temporary_static) do
		table.insert(recordset, val);
	end

	local audset = {};

	for ind, val in pairs(settings.atoggles) do
		local cap = capture_audio(ind);
		if (cap ~= nil and cap ~= BADID) then
			table.insert(audset, cap);
		end
	end

	if (internal_aid) then
		table.insert(audset, internal_aid);
	end

	local outfn, outurl = get_recstr();
	if (#audset == 0) then
		outurl = outurl .. ":noaudio";
	end

	define_recordtarget(dstvid, outfn, outurl, recordset,
		audset, RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -1,
		function(source, status)
			print("recordtarget status", status.kind);
		end);

	while (current_menu ~= nil) do
		current_menu:destroy();
		current_menu = current_menu.parent;
	end

	if (settings.infowin) then
		settings.infowin:destroy();
		settings.infowin = nil;
	end

	local resetfun = function()
		settings.layout:destroy();
		settings.layout = nil;
	end

--
-- hide menu, cascade, go!
--
	dispatch_push({MENU_ESCAPE = resetfun}, "runtime_input", function(iotbl)
		local restbl = keyconfig:match(iotbl);

		if (restbl) then
			for ind, val in pairs(restbl) do
				if (val and valid_vid(settings.target)) then
					res = keyconfig:buildtbl(val, iotbl);

					if (res) then
						res.label = val;
						target_input(res, settings.target);
					else
						iotbl.label = val;
						target_input(iotbl, settings.target);
					end
				end
			end
		end

	end);

	video_3dorder(ORDER_LAST);
end

function get_audio_toggles()
	local lbls = {};
	local ptrs = {};
	local fmts = {};

	local function toggle_audio(label)
		if (settings.atoggles[label] == nil) then
			settings.atoggles[label] = true;
		else
			settings.atoggles[label] = not settings.atoggles[label];
		end

		current_menu.formats[label] =
			settings.atoggles[label] and settings.colourtable.notice_fontstr or nil;
		current_menu:invalidate();
		current_menu:redraw();
	end

	if (#settings.adevs > 0) then
		for ind, val in ipairs(settings.adevs) do
			table.insert(lbls, val);
			ptrs[val] = toggle_audio;

			if (settings.atoggles[val]) then
				fmts[ val] = settings.colourtable.notice_fontstr;
			end
		end
	end

	return lbls, ptrs, fmts;
end

function query_destination(file)
		local resstr = nil;
		local opts = {};

		if (file) then
			opts.case_insensitive = false;
			opts.prefix = "file://";
			opts.startstr = "";
		else
			opts.case_insensitive = false;
			opts.prefix = "rtmp://";
			opts.startstr = settings.out_url;

-- quick hack to make it slightly easier '
-- to enter "big and nasty justin.tv kind" keys
			if (settings.out_url == "rtmp://" and resource("stream.key")) then
				if (open_rawresource("stream.key")) then
					local line = read_rawresource();
					if (line ~= nil and string.len(line) > 0) then
						opts.startstr = line;
					end
					close_rawresource();
				end
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
					settings.out_url = resstr;
					store_key("out_url", resstr);
				end
				toggle_main_menu();
			end
		end
		, -1);
	end


--
-- this parses the currently active layout (if any)
-- and generates the appropriate menu entries
-- depends on current layout (if any), target in layout, vidcap feeds in layout
--
function toggle_main_menu()
	ready = settings.out_url ~= "rtmp://";

	target = (settings.layout and settings.layout["internal"] ~= nil)
		and (#settings.layout["internal"] > 0) or nil;
	nvc = (settings.layout and settings.layout["vidcap"])
		and #settings.layout["vidcap"] or 0;

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

	add_submenu(streammenu, streamptrs, "Framerate...", "record_fps",
		gen_tbl_menu("record_fps", {12, 24, 25, 30, 50, 60}, function() end));
	add_submenu(streammenu, streamptrs, "Max Vertical Resolution...",
		"record_res", gen_tbl_menu("record_res", {720, 576, 480, 360, 288, 240},
		function() end));
	add_submenu(streammenu, streamptrs, "Video Quality...", "record_vqual",
		gen_tbl_menu("record_vqual", {2, 4, 6, 8, 10}, function() end));
	add_submenu(streammenu, streamptrs, "Audio Quality...", "record_aqual",
		gen_tbl_menu("record_aqual", {2, 4, 6, 8, 10}, function() end));
	add_submenu(streammenu, streamptrs, "VPTS offset...", "record_vpts",
		gen_num_menu("record_vpts", 0, 4, 12, function() end));
	add_submenu(streammenu, streamptrs, "APTS offset...", "record_apts",
		gen_num_menu("record_apts", 0, 4, 12, function() end));
	table.insert(streammenu, "Define Stream...");
	table.insert(streammenu, "Define File...");

	if (settings.layout ~= nil) then
		add_submenu(menulbls, menuptrs,
			"Streaming Settings...", nil, streammenu, streamptrs, {});

		table.insert(menulbls, "Audio Sources...");
		menuptrs["Audio Sources..."] = function()
			menu_spawnmenu(get_audio_toggles());
		end
	end

-- copied from gridle internal
	streamptrs["Define Stream..."] = function(label, store)
		query_destination(false);
	end

	streamptrs["Define File..."] = function(label, store)
		query_destination(true);
	end

	add_submenu(menulbls, menuptrs, "Destination...", streammenu, streamptrs, {});

-- need a layout set in order to know what to define the different slots as
	if (target) then
		add_submenu(menulbls, menuptrs, "Setup Game...", nil,
			gen_tbl_menu(nil, list_targets(), list_targetgames, true));
	end

	if (nvc > 0) then
		local ptrs = {};
		local lbls = {};

		for num=1, nvc do
			add_submenu(lbls, ptrs, "Slot " .. tostring(num) .. "...", nil,
				gen_num_menu(nil, 1, 1, 10, function(lbl)
				settings.vidcap[num] = tonumber(lbl);
				toggle_main_menu();
			end ));
		end

		add_submenu(menulbls, menuptrs, "Video Feeds...", nil, lbls, ptrs, {});
	end

-- if everything is set up correctly, let the user start
	if (ready) then
		table.insert(menulbls, "Start Streaming");
		menufmts["Start Streaming"] = [[\b\#00ff00]];
		menuptrs["Start Streaming"] = start_streaming;
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
-- Mostly expect the script to resolve a full resource description
-- based on type and idtag Although some properties could be altered
-- "in flight" and LAYRES_SPECIAL are even expected to be
--
function load_cb(restype, lay)
	print("lay.idtag:", lay.idtag);

	if (restype == LAYRES_STATIC or restype == LAYRES_MODEL) then
		if (lay.idtag == "background") then
			return "backgrounds/" .. lay.res, (function(newvid)
				settings.background = newvid; end);

		elseif (lay.idtag == "image") then
			return "images/" .. lay.res;

		elseif (lay.idtag == "static_model") then
			return load_model(lay.res);
		else
			warning("load_cb(), unknown idtag: " .. tostring(lay.idtag));
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

function run_view(dry_run)
	settings.layout:show();
--
-- NOTE: missing: with a dry_run, just use placeholders
-- for all "dynamic" sources
--
-- NOTE:For creating the record-set, the temporary and
-- temporary_static tables are swept
-- and just re-added. When (if?) MRT or WORLDID
-- recordsets are working, we'll switch to that
--
	if (settings.layout["internal"] and
		#settings.layout["internal"] > 0 and settings.gametbl) then
		local internal_vid, internal_aid = launch_target(settings.gametbl.gameid,
			LAUNCH_INTERNAL, function(source, status)
				if (status == "resized") then
					play_audio(status.source_audio);
				end
			end);

		if (not valid_vid(internal_vid)) then
			spawn_warning("Couldn't launch game, giving up.");
			return false;
		end

		show_image(internal_vid);
		settings.layout:add_imagevid(internal_vid, settings.layout["internal"][1]);
		settings.target = internal_vid;

-- reuse the VID if we have clones, same with models and "display" ID
		if (#settings.layout["internal"] > 1) then
			for i=2, #settings.layout["internal"] do
				local newvid = instance_image(internal_vid);
				image_mask_clearall(newvid);
				settings.layout:add_imagevid(newvid, settings.layout["internal"][i]);
			end
		end

	end

--
-- for each vidcap, check if the user has specified a mapping,
-- if he has, check if there's already a session running
-- (most capture devices don't permit sharing)
-- and if so, instance, otherwise spawn a new one
--
	if (settings.layout["vidcap"] and #settings.layout["vidcap"] > 0) then
		for i=1,#settings.layout["vidcap"] do
			if (settings.vidcap[i] ~= nil) then
				if (settings.vidcaps[ settings.vidcap[i] ] ~= nil) then
					local newvid = instance_image(settings.vidcaps[ settings.vidcap[i] ]);
					image_mask_clearall(newvid);
					settings.layout:add_imagevid(newvid, settings.layout["vidcap"][i]);
				else
					local elem = settings.layout["vidcap"][i];
					local reqstr = string.format("capture:device=%d:width=%d:height=%d",
						1, elem.size[1], elem.size[2]);
					settings.vidcaps[ settings.vidcap[i] ] =
						load_movie(reqstr, FRAMESERVER_NOLOOP,
							function(source, status)
								if (status.kind == "resized") then
									resize_image(source, elem.size[1], elem.size[2]);
								end
							end
						);
					settings.layout:add_imagevid(settings.vidcaps[
						settings.vidcap[i] ], settings.layout["vidcap"][i]);
				end
			end
		end

	end

	if (settings.layout["bgeffect"]) then
		update_shader(settings.layout["bgeffect"][1].res);
	end

	return true;
end

function setup_game(label)
	local game = list_games({target = settings.current_target, game = label});

	if (game and game[1]) then
		settings.gametbl = game[1];
		local restbl = resourcefinder_search(settings.gametbl, true );
		settings.restbl = restbl;
		toggle_main_menu();
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
	settings.layout_name = lay;
	settings.vidcap = {};
	settings.restbl = nil;
	settings.gametbl = nil;
	settings.atoggles = {};
	settings.vidcaps = {};

	if (settings.layout ~= nil) then
		toggle_main_menu(settings.layout["internal"] ~= nil and
			(#settings.layout["internal"] > 0),
			settings.layout["vidcap"] and #settings.layout["vidcap"] or 0);
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
	local laymenu, layptrs = build_globmenu("layouts/*.lay",
		load_layout, THEME_RESOURCE);
	local layfmt = {};

	table.insert(laymenu, 1, "New Layout");
	table.insert(laymenu, 2, "----------");
	layptrs["New Layout"] = define_layout;
	layfmt["New Layout"]  = [[\b\#00ff00]];
	menu_spawnmenu(laymenu, layptrs, layfmt);
end

function update_shader(resname)
	if (valid_vid(settings.background)) then
		settings.shader = load_shader("shaders/fullscreen/default.vShader",
			"shaders/bgeffects/" .. resname, "bgeffect", {});
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

		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, newitem.vid);

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

	if (settings.infowin) then
		settings.infowin:destroy();
		settings.infowin = nil;
	end

	if (settings.layout) then
		settings.layout:destroy();
		settings.layout = nil;
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
	layout:add_resource("background", "Background...", function()
		return glob_resource("backgrounds/*.png");
		end, nil, LAYRES_STATIC, true,
		function(key) return load_image("backgrounds/" .. key); end);

	layout:add_resource("bgeffect", "Background Effect...", function()
			return glob_resource("shaders/bgeffects/*.fShader"); end, nil,
			LAYRES_SPECIAL, true, nil);
	layout:add_resource("movie", "Movie", "Movie", "Dynamic Media...",
	LAYRES_FRAMESERVER, false, identphold);

	layout:add_resource("image", "Image...",
		function() return glob_resource("images/*.png"); end, nil,
			LAYRES_STATIC, false,
		function(key) return load_image("images/" .. key); end);

	for ind, val in ipairs( {"Screenshot", "Boxart", "Boxart (Back)",
		"Fanart", "Bezel", "Marquee"} ) do
		layout:add_resource(string.lower(val), val, val,
			"Dynamic Media...", LAYRES_IMAGE, false, identphold);
	end

	for ind, val in ipairs( {"Title", "Genre", "Subgenre", "Setname",
		"Manufacturer", "Buttons", "Players", "Year", "Target", "System"} ) do
		layout:add_resource(string.lower(val), val, val,
			"Dynamic Text...", LAYRES_TEXT, false, nil);
	end

	layout:add_resource("internal", "internal", "Internal Launch",
		"Input Feeds...", LAYRES_FRAMESERVER, false,
		load_image("images/placeholders/internal.png"));
	layout:add_resource("vidcap", "vidcap", "Video Capture",
		"Input Feeds...", LAYRES_FRAMESERVER, false,
		load_image("images/placeholders/vidcap.png"));
	layout.post_save_hook = hookfun;

	layout.finalizer = function(state)
		if (state) then
			load_layout(string.sub(layname, 9));
		else
			toggle_main_menu();
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

-- the shared code partially uses this,
-- since the soundmap is empty, just stop sources that are null.
local oldplay = play_audio;
function play_audio(source)
	if (source) then
		oldplay(source);
	end
end
