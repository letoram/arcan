--
-- Configurable view- mode for the Gridle theme
-- 
-- Based around the user setting up a mode of navigation and a set of 
-- assets to show (based on what the resource- finder can dig up) 
-- and then positioning these accordingly. 
--
-- The configuration step is stored as a script that's loaded if found,
-- else goes into configuration mode just display listviews of options
-- and where to place them.
--
local grid_stepx = 2;
local grid_stepy = 2;

customview = {};

local function customview_internal(source, datatbl)
	internallaunch_event(source, datatbl);
end

--
-- called whenever an internal launch 
-- has terminated: update caches, reset timers, restore context.
--
local function cleanup()
	resourcefinder_cache.invalidate = true;
		local gameno = current_game_cellid();
		resourcefinder_search(customview.gametbl, true);
	resourcefinder_cache.invalidate = false;

	store_coreoptions(customview.gametbl);

	if ( (settings.autosave == "On" or 
		(settings.autosave == "On (No Warning)")) and valid_vid(internal_vid)) then
		local counter = 25;
		local old_clock = gridle_clock_pulse;
		blend_image(internal_vid, 0.0, 20);
		audio_gain(internal_aid, 0.0, 20);

-- should be removed when save-state cleanup 
-- in libretro frameserver is less .. "dumb" 
		gridle_clock_pulse = function()
			if counter > 0 then
				counter = counter - 1;
			else
				cleanup_trigger();
				gridle_clock_pulse = old_clock;
			end
		end
	else
		cleanup_trigger();
	end
end

local function launch(tbl)
	if (tbl.capabilities == nil) then
		return;
	end
	
	local launch_internal = (settings.default_launchmode == 
		"Internal" or tbl.capabilities.external_launch == false) 
		and tbl.capabilities.internal_launch;

-- can also be invoked from the context menus
	if (launch_internal) then
		local dstreg = (layout["internal"] and 
			#layout["internal"] > 0) and layout["internal"][1] or nil;

		if (not dstreg) then
			push_video_context();
			cleanup_trigger = pop_video_context;
			INTERX = nil;
		else
			INTERW = dstreg.size[1];
			INTERH = dstreg.size[2];
			INTERX = dstreg.pos[1];
			INTERY = dstreg.pos[2];
			INTERANG = dstreg.ang;
			cleanup_trigger = function() end
		end

		order_image(imagery.loading, INGAMELAYER_OVERLAY);		

		play_audio(soundmap["LAUNCH_INTERNAL"]);
		settings.capabilities = tbl.capabilities;
		settings.cleanup_toggle = customview.cleanup;

		local tmptbl = {};
		tmptbl["MENU_ESCAPE"] = function()
			cleanup_trigger();
			dispatch_pop();
		end

		settings.internal_ident = "";
		dispatch_push(tmptbl, "internal loading", nil, 0);

		local coreopts = load_coreoptions( tbl );
		internal_vid = launch_target( tbl.gameid, LAUNCH_INTERNAL, 
			customview_internal );
	else
		settings.in_internal = false;
		play_audio(soundmap["LAUNCH_EXTERNAL"]);
		launch_target( tbl.gameid, LAUNCH_EXTERNAL);
	end
end

local function navi_change(navi, navitbl)
	settings.gametbl = navi:current_item();
	settings.restbl  = resourcefinder_search(settings.gametbl, true);
	send_gamedata(settings.gametbl, false);
	
	layout.default_gain = settings.movie_gain;
	layout:show();

-- we override some of the navigator settings
	order_image( navi:drawable(), navitbl.zv    );
	blend_image( navi:drawable(), navitbl.opa   );
	 move_image( navi.clipregion, navitbl.pos[1], navitbl.pos[2] );
end

--
-- Load and configure navigator,
-- Generate functions for mapping input to navigator
--
local function setup_customview()
	local imenu = {};
	
	if (layout["navigator"]) then
		local navitbl = layout["navigator"][1];
		navitbl.width = navitbl.size[1];
		navitbl.height = navitbl.size[2];

--
-- Current layout editor do not allow navigator to set font / fontsize
		if (not navitbl.font) then
			navitbl.font_size = 12;
			navitbl.font = "\\ffonts/multilang.ttf,";
		end

		customview.navigator = system_load("customview/" .. navitbl.res)();
		local navi = customview.navigator;
	
		navi:create(navitbl);
		navi:update_list(settings.games);
		
		imenu["MENU_UP"]   = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:up(1);
			navi_change(navi, navitbl);
		end

		imenu["MENU_DOWN"] = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:down(1); 
			navi_change(navi, navitbl);
		end

		imenu["MENU_LEFT"] = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:left(1);
			navi_change(navi, navitbl);
		end

		imenu["MENU_TOGGLE"]  = function(iotbl)
			play_audio(soundmap["MENU_TOGGLE"]);
			video_3dorder(ORDER_NONE);
			gridlemenu_settings(
				function() navi:update_list(settings.games);
				video_3dorder(ORDER_LAST);
			end, function() end);
		end
		
		imenu["MENU_RIGHT"] = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:right(1);
			navi_change(navi, navitbl);
		end

		imenu["CONTEXT"] = function()
			local res = navi:trigger_selected();
			if (res ~= nil) then
				current_game = res;
				current_game.capabilities = launch_target_capabilities( res.target );
				play_audio(soundmap["MENU_TOGGLE"]);
				video_3dorder(ORDER_NONE);

				gridle_launchexternal = function()
					play_audio(soundmap["LAUNCH_EXTERNAL"]);
					launch_target( current_game.gameid, LAUNCH_EXTERNAL);
				end

				gridle_launchinternal = function()
					local old_mode = settings.default_launchmode;
					settings.default_launchmode = "Internal";
					launch(current_game);
					settings.default_launchmode = old_mode;
				end
	 
				gridlemenu_context(function(upd)
					if (upd) then navi:update_list(settings.games); end
					video_3dorder(ORDER_LAST);
				end);
			end
		end
		
		imenu["MENU_SELECT"] = function()
			local res = navi:trigger_selected();
			if (res ~= nil) then
				current_game = res;
				res.capabilities = launch_target_capabilities( res.target );
				launch(res);
			else
				navi_change(navi, navitbl);
			end
		end
	
		imenu["MENU_ESCAPE"] = function()
				confirm_shutdown();
		end

		navi_change(navi, navitbl);
	end

	dispatch_push(imenu, "default handler", nil, -1);
end

local function customview_3dbase()
	local lshdr = load_shader("shaders/dir_light.vShader", 
		"shaders/dir_light.fShader", "cvdef3d");
	shader_uniform(lshdr, "map_diffuse", "i"  , PERSIST, 0);
	customview.light_shader = lshdr;
end

customview.cleanup = function()
		gridle_internal_cleanup(cleanup, false);
		store_coreoptions();
end

function update_shader(resname)
	if (not resname) then
		return;
	end
	
	settings.shader = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/bgeffects/" .. resname, "bgeffect", {});
	shader_uniform(settings.shader, "display", "ff", PERSIST, VRESW, VRESH);

	if (valid_vid(settings.background)) then
		image_shader(settings.background, settings.shader);
	end
end

local function load_cb(restype, lay)
	if (restype == LAYRES_STATIC) then
		if (lay.idtag == "background") then
			return "backgrounds/" .. lay.res, (function(newvid) 
				settings.background = newvid; end);
			
		elseif (lay.idtag == "image") then
			return "images/" .. lay.res;
		end
	elseif (restype == LAYRES_MODEL and lay.idtag == "static_model") then
		return lay.res;
	end
		
-- don't progress until we have a data-source set
	if (settings.gametbl == nil) then
		return nil;
	end

	if (restype == LAYRES_IMAGE or restype == LAYRES_FRAMESERVER) then

		local locfun = settings.restbl["find_" .. lay.idtag];
		if (locfun ~= nil) then
			return locfun(settings.restbl);
		end

	elseif (restype == LAYRES_MODEL) then
		local model = find_cabinet_model(settings.gametbl);
		model = model and setup_cabinet_model(model, settings.restbl, {}) or nil;
		if (model) then
			shader_uniform(customview.light_shader, "wlightdir", "fff", 
				PERSIST, lay.dirlight[1], lay.dirlight[2], lay.dirlight[3]);
			shader_uniform(customview.light_shader, "wambient",  "fff", 
				PERSIST, lay.ambient[1], lay.ambient[2], lay.ambient[3]);
			shader_uniform(customview.light_shader, "wdiffuse",  "fff", 
				PERSIST, lay.diffuse[1], lay.diffuse[2], lay.diffuse[3]);
			image_shader(model.vid, customview.light_shader);
		end
		return model;
	elseif (restype == LAYRES_TEXT) then
		return settings.gametbl[lay.idtag];
	end
end

--
-- special treatment for background / shadereffects when added to the layout
-- 
local function hookfun(newitem)
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
	
		if (settings.shader) then
			image_shader(settings.background, settings.shader);
		end
	
		newitem:update();

	elseif (newitem.idtag == "bgeffect") then
		for ind, val in ipairs(layout.items) do
			if (val.idtag == "bgeffect") then
				table.remove(layout.items, ind);
			end
		end

		update_shader(newitem.res);
	end
end

function gridle_customview()
-- try to load a preexisting configuration file, if no one is found
-- launch in configuration mode -- to reset this procedure, delete any 
-- customview_cfg.lua and reset customview.in_config
	pop_video_context();
	push_video_context();
	
	setup_3dsupport();
	customview_3dbase();

	INTERW = VRESW;
	INTERH = VRESH;

	imagery.crashimage = load_image("images/icons/terminated.png");
	resize_image(imagery.crashimage, VRESW * 0.5, VRESH * 0.5);
	move_image(imagery.crashimage, 
		0.5 * (VRESW - (VRESW * 0.5)), 
		0.5 * (VRESH - (VRESH * 0.5)));
	image_tracetag(imagery.crashimage, "terminated");
	persist_image(imagery.crashimage);

-- load the standard icons needed to show internal launch info
	imagery.loading = load_image("images/icons/colourwheel.png");
	resize_image(imagery.loading, VRESW * 0.05, VRESW * 0.05);
	move_image(imagery.loading, 
		0.5 * (VRESW - VRESW * 0.1), 0.5 * (VRESH - VRESW * 0.1) - 30);
	image_tracetag(imagery.loading, "loading");
	persist_image(imagery.loading);

	imagery.nosave  = load_image("images/icons/brokensave.png");
	image_tracetag(imagery.nosave, "nosave");
	persist_image(imagery.nosave);

	layout = layout_load("customview.lay", load_cb);
	if (layout) then
		setup_customview();
		layout.default_gain = settings.movie_gain;
		layout:show();
    if (layout["bgeffect"]) then
  		update_shader(layout["bgeffect"][1] and layout["bgeffect"][1].res);
    end

		music_start_bgmusic(settings.bgmusic_playlist);
		return true;
	end
	
-- 
-- If the default layout cannot be found (menu/config 
-- will simply zap the customview_cfg and call _customview() gain)
-- Setup an edit session, this is a slightly different version of 
-- what's present in "streamer" (no internal launch, no vidcap, ...)
-- Instead, a "navigator" group is added (se navigators/*.lua) 
-- that determines what is currently "selected"
--
	layout = layout_new("customview.lay");
		
	local identtext  = function(key) 
		return render_text(settings.colourtable.label_fontstr .. key); 
	end

	local identphold = function(key) 
		return load_image("images/placeholders/" .. 
		string.lower(key) .. ".png"); 
	end
	
	layout:add_resource("background", "Background...", 
		function() 
			return glob_resource("backgrounds/*.png"); 
		end, 
		nil, LAYRES_STATIC, true, 
		function(key)
			return load_image("backgrounds/" .. key); 
		end
	);

	layout:add_resource("bgeffect", "Background Effect...", 
		function() 
			return glob_resource("shaders/bgeffects/*.fShader"); 
		end, nil, LAYRES_SPECIAL, true, nil);

	layout:add_resource("movie", "Movie", "Movie", "Dynamic Media...", 
		LAYRES_FRAMESERVER, false, identphold);

	layout:add_resource("image", "Image...", 
		function() 
			return glob_resource("images/*.png"); 
		end, nil, LAYRES_STATIC, false, 
		function(key) 
			return load_image("images/" .. key); 
		end
	);

	layout:add_resource("navigator", "Navigators...", 
		function()
			return glob_resource("customview/*.lua"); 
		end, nil, LAYRES_SPECIAL, true, 
		function(key) 
			return load_image("images/placeholders/" .. key .. ".png"); 
		end
	);
		
	for ind, val in ipairs( {"Screenshot", "Boxart", 
		"Boxart (Back)", "Fanart", "Bezel", "Marquee"} ) do
		layout:add_resource(string.lower(val), val, val, 
			"Dynamic Media...", LAYRES_IMAGE, false, identphold);
	end

	layout:add_resource("model", "Model", "Model", 
		"Dynamic Media...", LAYRES_MODEL, false, 
		function(key) 
			return load_model("placeholder"); 
		end 
	);

	layout:add_resource("internal", "internal", "Internal Launch", 
		"Input Feeds...", LAYRES_FRAMESERVER, true, 
		load_image("images/placeholders/internal.png"));
	
	for ind, val in ipairs( {"Title", "Genre", "Subgenre", 
		"Setname", "Manufacturer", "Buttons", "Players", 
		"Year", "Target", "System"} ) do
		layout:add_resource(string.lower(val), val, val, 
			"Dynamic Text...", LAYRES_TEXT, false, nil);
	end

--
-- post_save is triggered whenever an item is added
--
	layout.post_save_hook = hookfun;
	layout.finalizer = gridle_customview;
	
--
-- until this function evaulates true, the user is not allowed to save
--
	layout.validation_hook = function()
		for ind, val in ipairs(layout.items) do
			if (val.idtag == "navigator") then
				return true;
			end
		end
		return false;
	end

	layout.default_gain = settings.movie_gain;
	layout:show();
end
