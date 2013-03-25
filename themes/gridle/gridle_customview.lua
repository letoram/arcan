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

local stepleft, stepup, stepdown, stepright, show_config, setup_customview;

customview = {};

layout = layout_load(name);
if (layout) then
	layout.resources["Navigator"].instance = system_load( layout.resources["Navigator"].resource )();
	
else
	layout = layout_new(name);
	layout:add_resource("Bezel", "bezel.png",           LAYRES_IMAGE, false);
	layout:add_resource("Screenshot", "screenshot.png", LAYRES_IMAGE, false);
	layout:add_resource("Marquee", "marquee.png",       LAYRES_IMAGE, false);
	layout:add_resource("Overlay", "overlay.png",       LAYRES_IMAGE, false);
	layout:add_resource("Backdrop", "backdrop.png",     LAYRES_IMAGE, false);
	layout:add_resource("Snapshot", "snapshot.png",     LAYRES_FRAMESERVER, false);
	layout:add_resource("Vidcap", "vidcap.png",         LAYRES_FRAMESERVER, false);
	layout:add_resource("Model", "placeholder",         LAYRES_MODEL, false);
	layout:add_resource("Background", "background.png", LAYRES_STATIC, true, function() return glob("backgrounds/*"); end
	layout:add_resource("Navigator", "navigator.png",   LAYRES_NAVIGATOR, true, function() return glob("navigators/*.lua"); end
	layout:add_resource("Background Shader", nil, LAYRES_
end

local function customview_internal(source, datatbl)
	if (datatbl.kind == "frameserver_terminated") then
		pop_video_context();
		imagery.crashimage = load_image("images/terminated.png");
		image_tracetag(imagery.crashimage, "terminated");
		dispatch_pop();
	end

	internallaunch_event(source, datatbl);
end

local function cleanup()
-- since new screenshots /etc. might have appeared, update cache 
	resourcefinder_cache.invalidate = true;
		local gameno = current_game_cellid();
		resourcefinder_search(customview.gametbl, true);
	resourcefinder_cache.invalidate = false;

	if ( (settings.autosave == "On" or (settings.autosave == "On (No Warning)")) and valid_vid(internal_vid)) then
		local counter = 20;
		local old_clock = gridle_clock_pulse;
		blend_image(internal_vid, 0.0, 20);
		audio_gain(internal_aid, 0.0, 20);
		
		gridle_clock_pulse = function()
			if counter > 0 then
				counter = counter - 1;
			else
				pop_video_context();
				gridle_clock_pulse = old_clock;
			end
		end
	else
		pop_video_context();
	end
end

local function launch(tbl)
	if (tbl.capabilities == nil) then
		return;
	end
	
	local launch_internal = (settings.default_launchmode == "Internal" or tbl.capabilities.external_launch == false) and tbl.capabilities.internal_launch;

-- can also be invoked from the context menus
	if (launch_internal) then
		push_video_context();

-- load the standard icons needed to show internal launch info
		imagery.loading = load_image("images/colourwheel.png");
		image_tracetag(imagery.loading, "loading");
	
		imagery.nosave  = load_image("images/brokensave.png");
		image_tracetag(imagery.nosave, "nosave");

		play_audio(soundmap["LAUNCH_INTERNAL"]);
		customview.gametbl = tbl;
		settings.capabilities = tbl.capabilities;
		settings.cleanup_toggle = customview.cleanup;

		local tmptbl = {};
		tmptbl["MENU_ESCAPE"] = function()
			pop_video_context();
			dispatch_pop();
		end

		settings.internal_ident = "";
		dispatch_push(tmptbl, "internal loading", nil, 0);
		internal_vid = launch_target( tbl.gameid, LAUNCH_INTERNAL, customview_internal );
	else
		settings.in_internal = false;
		play_audio(soundmap["LAUNCH_EXTERNAL"]);
		launch_target( tbl.gameid, LAUNCH_EXTERNAL);
	end
end

local function reset_customview()
	if ( navi:escape() ) then
		play_audio(soundmap["MENU_FADE"])
-- delete all "new" resources
		pop_video_context();
-- then copy the server vid again
		push_video_context();
		dispatch_pop();
	else
		navi_change(navi, navitbl);
	end
end

local function place_model(modelid, pos, ang)
	move3d_model(modelid, pos[1], pos[2], pos[3]);
	rotate3d_model(modelid, ang[1], ang[2], ang[3]);
	show_image(modelid);
end

local function update_dynamic(newtbl)
	if (newtbl == nil or newtbl == customview.lasttbl) then
		return;
	end

	customview.lasttbl = newtbl;
	toggle_led(newtbl.players, newtbl.buttons, "")	;

-- this table is maintained for every newly selected item, and just tracks everything to delete.
	for ind, val in ipairs(customview.temporary) do
		if (valid_vid(val)) then delete_image(val); end 
	end

	for ind, val in ipairs(customview.temporary_models) do
		if (valid_vid(val.vid)) then delete_image(val.vid); end
	end
	
	customview.temporary = {};
	customview.temporary_models = {};

	local restbl = resourcefinder_search( newtbl, true );

	if (restbl) then
		if (customview.current.models and #customview.current.models > 0) then
			local modelstr = find_cabinet_model(newtbl);
			local model  = modelstr and setup_cabinet_model(modelstr, restbl, {}) or nil;

			if (model) then
				local shdr = customview.light_shader;
	
				table.insert(customview.temporary_models, model);
				table.insert(customview.temporary, model.vid);

				local cm = customview.current.models[1];
				
				image_shader(model.vid, customview.light_shader);
				place_model(model.vid, cm.pos, cm.ang);

				local ld = cm.dir_light and cm.dir_light or {1.0, 0.0, 0.0};
				shader_uniform(shdr, "wlightdir", "fff", PERSIST, ld[1], ld[2], ld[3]);

				local la = cm.ambient and cm.ambient or {0.3, 0.3, 0.3};
				shader_uniform(shdr, "wambient",  "fff", PERSIST, la[1], la[2], la[3]);
				
				ld = cm.diffuse and cm.diffuse or {0.6, 0.6, 0.6};
				shader_uniform(shdr, "wdiffuse",  "fff", PERSIST, 0.6, 0.6, 0.6);

-- reuse the model for multiple instances
				for i=2,#customview.current.models do
					local nid = instance_image(model.vid);
					image_mask_clear(nid, MASK_POSITION);
					image_mask_clear(nid, MASK_ORIENTATION);
					place_model(nid, customview.current.models[i].pos, customview.current.models[i].ang);
				end
			end
		end

		for ind, val in ipairs(customview.current.dynamic) do
			local vid = nil;
			reskey = remaptbl[val.res];
			
			if (reskey == "movies") then
				local res = restbl:find_movie();
				if (res) then
					vid, aid = load_movie(restbl[reskey][1], FRAMESERVER_LOOP, 
						function(source, status) place_item(source, val);
						play_movie(source);
						end)
				end
			elseif (reskey == "boxart" or reskey == "boxart (back)") then
				local res = restbl:find_boxart(reskey == "boxart", val.width < 512 or val.height < 512);
				if (res) then
					vid = load_image_asynch(res, function(source, status) place_item(source, val); end);
				end

			elseif (restbl[reskey] and #restbl[reskey] > 0) then
				vid = load_image_asynch(restbl[reskey][1], function(source, status) place_item(source, val); end);
			end

			if (vid and vid ~= BADID) then
				table.insert(customview.temporary, vid);
			end
		end

		for ind, val in ipairs(customview.current.dynamic_labels) do
			local dststr = newtbl[val.res];
			
			if (type(dststr) == "number") then dststr = tostring(dststr); end
			
			if (dststr and string.len( dststr ) > 0) then
				local capvid = fill_surface(math.floor( VRESW * val.width), math.floor( VRESH * val.height ), 0, 0, 0);
				vid = render_text(val.font .. math.floor( VRESH * val.height ) .. " " .. dststr);
				link_image(vid, capvid);
				image_mask_clear(vid, MASK_OPACITY);
				place_item(capvid, val);

				hide_image(capvid);
				show_image(vid);
				resize_image(vid, 0, VRESH * val.height);
				order_image(vid, val.order);
				table.insert(customview.temporary, capvid);
				table.insert(customview.temporary, vid);
			end
			
		end
		
	end
end

local function navi_change(navi, navitbl)
		update_dynamic( navi:current_item() );

		order_image( navi:drawable(), navitbl.order );
		blend_image( navi:drawable(), navitbl.opa   );
end

local function setup_customview()
	local background = nil;
	for ind, val in ipairs( customview.current.static ) do
		local vid = load_image( val.res );
		image_tracetag(vid, "static(" .. val.res ..")");
		place_item( vid, val );
	end

-- video capture devices, can either be instances of the same vidcap OR multiple devices based on index 
	customview.current.vidcap_instances = {};
	for ind, val in ipairs( customview.current.vidcap ) do
		inst = customview.current.vidcap_instances[val.index];
		
		if (valid_vid(inst)) then
			inst = instance_image(inst);
			image_mask_clearall(inst);
			place_item( inst, val );
		else
			local vid = load_movie("capture:device=" .. tostring(val.index), FRAMESERVER_LOOP, function(source, status)
				place_item(source, val);
				play_movie(source);
			end);
		
			customview.current.vidcap_instances[val.index] = vid;
		end
	end

-- load background effect 
	if (customview.current.background) then
		vid = load_image( customview.current.background.res );
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT, vid);

		customview.background = vid;

		place_item(vid, customview.current.background);
		customview.bgshader_label = customview.current.background.shader;

		local props  = image_surface_properties(vid);
		local iprops = image_surface_initial_properties(vid);


		if (customview.current.background.tiled) then
			image_scale_txcos(vid, props.width / iprops.width, props.height / iprops.height);
		end
		
		if (customview.bgshader_label) then
			customview.bgshader = load_shader("shaders/fullscreen/default.vShader", "shaders/bgeffects/" .. customview.bgshader_label, "bgeffect", {});
			update_bgshdr();
		end
	end

	local imenu = {};
	if (customview.current.navigator) then
		customview.navigator = system_load("customview/" .. customview.current.navigator.res .. ".lua")();
		local navi = customview.navigator;
		local navitbl = customview.current.navigator;
		
		navitbl.width  = math.floor(navitbl.width  * VRESW);
		navitbl.height = math.floor(navitbl.height * VRESH);
		navitbl.x      = math.floor(navitbl.x * VRESW);
		navitbl.y      = math.floor(navitbl.y * VRESH);
		
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
	local lshdr = load_shader("shaders/dir_light.vShader", "shaders/dir_light.fShader", "cvdef3d");
	shader_uniform(lshdr, "map_diffuse", "i"  , PERSIST, 0);
	customview.light_shader = lshdr;
end

customview.cleanup = function()
		gridle_internal_cleanup(cleanup, false);
end

function gridle_customview()
	local disptbl;
	
-- try to load a preexisting configuration file, if no one is found
-- launch in configuration mode -- to reset this procedure, delete any 
-- customview_cfg.lua and reset customview.in_config
	pop_video_context();
	push_video_context();

	setup_3dsupport();
	customview_3dbase();

	music_start_bgmusic();

	if (resource("customview_cfg.lua")) then
		customview.background    = nil;
		customview.bgshader      = nil;
		customview.current       = system_load("customview_cfg.lua")();
		
		if (customview.current) then
			customview.in_customview = true;
			customview.in_config = false;
			setup_customview();
		end

	else
		customview.in_config = true;
		video_3dorder(ORDER_LAST);
		disptbl = show_config();
	end
	
end