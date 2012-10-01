detailview = {
	modeldisplay = BADID,
	modeldisplay_aid = BADID, 
};
local gridledetail_loaded = false;

local function gridledetail_load()
	switch_default_texmode( TEX_REPEAT, TEX_REPEAT );
	noise_image      = random_surface(256, 256);
	switch_default_texmode( TEX_CLAMP, TEX_CLAMP );

-- non-visible 3d object as camtag
	camera = fill_surface(4, 4, 0, 0, 0);
	camtag_model(camera, 0);
	
	backlit_shader3d = load_shader("shaders/diffuse_only.vShader", "shaders/flicker_diffuse.fShader", "backlit");
	default_shader3d = load_shader("shaders/dir_light.vShader", "shaders/dir_light.fShader", "default3d");
	texco_shader     = load_shader("shaders/anim_txco.vShader", "shaders/diffuse_only.fShader", "noise");
	display_shader   = load_shader("shaders/diffuse_only.vShader", "shaders/diffuse_only.fShader", "display");
	
	shader_uniform(default_shader3d, "wlightdir", "fff", PERSIST, 1.0, 0.0, 0.0);
	shader_uniform(default_shader3d, "wambient", "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(default_shader3d, "wdiffuse", "fff", PERSIST, 0.6, 0.6, 0.6);
	shader_uniform(default_shader3d, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(texco_shader, "speedfact", "ff", PERSIST, 12.0, 12.0);
	shader_uniform(display_shader, "flip_t", "b", PERSIST, 1);
	
-- make sure this is only done once
	gridledetail_loaded = true;
end

local function gridledetail_setnoisedisplay()
	if (valid_vid( detailview.modeldisplay ) ) then
		delete_image(detailview.modeldisplay);
		detailview.modeldisplay_aid = BADID;
		detailview.modeldisplay = BADID;
	end
	
	if (detailview.model.labels["display"] == nil) then 
		return; 
	end

	local noise = instance_image(noise_image);
	local rvid = set_image_as_frame(detailview.model.vid, noise, detailview.model.labels["display"], FRAMESET_DETACH);
	mesh_shader(detailview.model.vid, texco_shader, detailview.model.labels["display"]);

	if (valid_vid( rvid )) then
		expire_image(rvid, rvid == internal_vid and 20 or 0);
	end
end

local function gridledetail_imagestatus(source, status)
-- all asynchronous operations can fail or the resource may not be interesting anymore
	if (status.kind =="load_failed") then
		warning("Couldn't load source (" .. tostring(status.resource) .. ")\n");
		return false;
	end
	
	if (valid_vid(source) == false) then
		warning("gridledetail_imagestatus() -- invalid ID received.\n");
		return false;
	end
	
	if (source ~= detailview.modeldisplay) then 
		delete_image(source);
	else
	-- the last flag, detaches the vid from the default render-list, however it will still be an addressable vid,
-- we can't do this for movie, as we need 'tick' operations for it to properly poll the frameserver
		mesh_shader(detailview.model.vid, display_shader, detailview.model.labels["display"]);
		rvid = set_image_as_frame(detailview.model.vid, source, detailview.model.labels["display"], FRAMESET_NODETACH);
		if (rvid ~= BADID) then delete_image(rvid); end
		
		return true;
	end
	
	return false;
end

local function gridledetail_moviestatus(source, status)
-- same procedure in loading / mapping, with the added playback / gain calls
	if (status.kind == "frameserver_terminated") then
		gridledetail_setnoisedisplay();
	elseif (status.kind == "resized") and gridledetail_imagestatus(source, status) then
		local aid = status.source_audio;
		play_movie(source);

		audio_gain(aid, 0.0);
		if (zoomed) then
			audio_gain(aid, settings.movieagain, 0);
		else
			audio_gain(aid, settings.movieagain * 0.5, 0);
		end
		detailview.modeldisplay_aid = status.source_audio;
	end
end

local function asynch_snapvid(source, statustbl)
	if (statustbl.kind == "load_failed") then
		gridledetail_setnoisedisplay();
	end
end

-- figure out what to show based on a "source data string" (detailres, dependency to havedetails) and a gametable
local function gridledetail_buildview(detailres, gametbl )

-- "game- specific load script" instead of generic / 3d.
	if (".lua" == string.sub(detailres, -1, -1)) then
		gamescript = system_load(detailres)();
		return (type(gamescript.status) == "function") and gamescript:status() or nil;
	else
		
-- otherwise, use the generic model loader
		detailview.game = gametbl;
		detailview.model = load_model(detailres);

-- this can fail (no model found) 
		if (detailview.model) then
			image_shader(detailview.model.vid, default_shader3d);
			scale_3dvertices(detailview.model.vid);

-- we can hardcode these values because the "scale vertices" part forces the actual value range of any model hierarchy to -1..1
			detailview.startpos = {x = -1.0, y = 0.0, z = -4.0};
			detailview.startang = {roll = 0, pitch = 0, yaw = 0};
			
-- if the model specifies a default view pos (position + roll/pitch/yaw), set that one as the target)
			detailview.zoompos = detailview.model.screenview.position;
			detailview.zoompos.x = detailview.zoompos.x * -1;
			detailview.zoompos.y = detailview.zoompos.y * -1;	
			detailview.zoompos.z = detailview.zoompos.z * -1;
			detailview.zoomang = detailview.model.screenview.orientation;

-- set specific shaders for marquee (fullbright, blink every now and then 
			if (detailview.model.labels["marquee"]) then 
				mesh_shader(detailview.model.vid, backlit_shader3d, detailview.model.labels["marquee"]); 
			end
			
			if (detailview.model.labels["coinlights"]) then
				mesh_shader(detailview.model.vid, display_shader, detailview.model.labels["coinlights"]);
			end
		
			if (detailview.model.labels["snapshot"] and detailview.game.resources:find_screenshot() ) then
				mesh_shader(detailview.model.vid, display_shader, detailview.model.labels["snapshot"]);
				set_image_as_frame(detailview.model.vid, load_image_asynch( detailview.game.resources:find_screenshot(), asynch_snapvid ), detailview.model.labels["snapshot"], FRAMESET_DETACH);
			end
			
-- if we find a "display" (somewhere we can map internal launch, movie etc.) try to replace the texture used.
			if (detailview.model.labels["display"]) then
				if (detailview.game.resources:find_movie()) then
					detailview.modeldisplay = load_movie(detailview.game.resources:find_movie(), FRAMESERVER_NOLOOP, gridledetail_moviestatus);
				elseif (detailview.game.resources:find_screenshot()) then
					detailview.modeldisplay = load_image_asynch( detailview.game.resources:find_screenshot(), gridledetail_imagestatus);
				end

				return true;
			else
				return nil;
			end
		end
	end
end

-- deallocate a model and all associated resources (movie / screenshot),
-- axis (x:0, y:1, z:2), mag (value to add to the axis) 
local function gridledetail_freeview(axis, mag)

-- replace any video with static
	if (detailview.model) then
		gridledetail_setnoisedisplay();

		local dx = 0;
		local dy = 0;
		local dz = 0;
		
		if (axis == 0) then dx = mag;
	elseif (axis == 1) then dy = mag;
	elseif (axis == 2) then dz = mag; end

		move3d_model(detailview.model.vid, detailview.startpos.x + dx, detailview.startpos.y + dy, detailview.startpos.z + dz, 20 + settings.transitiondelay);
		expire_image(detailview.model.vid, 20 + settings.transitiondelay);
		detailview.fullscreen = false;
		detailview.model = nil;
	end
end

function gridledetail_internal_status(source, datatbl)
	if (datatbl.kind == "resized") then
		internal_vid, internal_aid = play_movie(source);
		resize_image(source, datatbl.width, datatbl.height, 0);
		audio_gain(internal_aid, settings.internal_again, NOW);

		local rvid = set_image_as_frame(detailview.model.vid, source, detailview.model.labels["display"], FRAMESET_NODETACH);
		if (rvid ~= source and rvid ~= BADID) then 
			delete_image(rvid); 
		end 

		print(datatbl.mirrored);
		if (datatbl.mirrored == 0) then
			shader_uniform(display_shader, "flip_t", "b", PERSIST, 1)	
		else
			shader_uniform(display_shader, "flip_t", "b", PERSIST, 0)	
		end
	
		move3d_model(detailview.model.vid, detailview.zoompos.x, detailview.zoompos.y, detailview.zoompos.z, 20);
		orient3d_model(detailview.model.vid, detailview.zoomang.roll, detailview.zoomang.pitch, detailview.zoomang.yaw, 20);
		mesh_shader(detailview.model.vid, display_shader, detailview.model.labels["display"]);
	end
end

function gridledetail_clock_pulse(tick)
	timestamp = tick;
	if (detailview.cooldown > 0) then 
		detailview.cooldown = detailview.cooldown - 1; 
	end
end

local function gridledetail_switchfs()
-- switch between running with fullscreen and running with cabinet zoomed in
	if (detailview.fullscreen) then
		detail_toggles = settings.internal_toggles;
		settings.internal_toggles = settings.internal_notoggles;
		gridlemenu_rebuilddisplay(); -- this will undo the vectordisplay, cocktail, ... 
		
		hide_image(internal_vid);
		delete_image(internal_vidborder); 

-- return to cabinet view, partial cleanup
		show_image(detailview.model.vid);
		
		if (valid_vid(imagery.bezel)) then 
			hide_image(imagery.bezel); 
		end
		
		detailview.fullscreen = false;
	else
		hide_image(detailview.model.vid);
		settings.internal_toggles = detail_toggles;

-- setup black frame around output
		internal_vidborder = instance_image( imagery.black );
		image_mask_clearall(internal_vidborder);
		order_image(internal_vidborder, max_current_image_order());
		resize_image(internal_vidborder, VRESW, VRESH);
		show_image(internal_vidborder);

		gridlemenu_rebuilddisplay();

		detailview.fullscreen = true;
	end
	
end

function gridledetail_stopinternal()
-- stop the internal launch, zoom out the model and replace display with static
	if (valid_vid( internal_vidborder )) then 
		delete_image(internal_vidborder);
		internal_vidborder = nil;
	end

	undo_vectormode();
	
	if (settings.autosave == "On") then
		internal_statectl("auto", true);
-- definitely on the "to fix" for 0.2.1
		expire_image(internal_vid, 20);
		blend_image(internal_vid, 0.0, 20);
	else
		delete_image(internal_vid);
	end

	detailview.fullscreen = false;
	
	show_image(detailview.model.vid);
	gridle_delete_internal_extras();
	gridledetail_setnoisedisplay();
	internal_vid = BADID;

	local o = detailview.model.default_orientation;
	orient3d_model(detailview.model.vid, o.roll, o.pitch, o.yaw, 20);
	move3d_model(detailview.model.vid, detailview.startpos.x, detailview.startpos.y, detailview.startpos.z, 20);
end

function gridledetail_internalinput(iotbl)
	local restbl = keyconfig:match(iotbl);
	local addlbl = "";
	
	if (restbl) then
		for ind,val in pairs(restbl) do
			local forward = false;
			addlbl = val;
			
			if (iotbl.active) then
				if (val == "MENU_TOGGLE" and detailview.fullscreen) then
					gridlemenu_internal(internal_vid, true, true);
	
-- iotbl.active filter here is just to make sure we don't save twice (press and release) 
				elseif (val == "QUICKSAVE" or val == "QUICKLOAD") then
					internal_statectl("quicksave", val == "QUICKSAVE");

				elseif (val == "MENU_ESCAPE") then
					gridledetail_stopinternal();
				
				elseif (val == "CONTEXT") then
					gridledetail_switchfs();
				
				else
					forward = true;
				end
			else 
				forward = true;
			end

			if (forward) then
				if (iotbl.kind == "analog") then 
					gridle_internaltgt_analoginput(val, iotbl);
				else
					gridle_internaltgt_input(val, iotbl);
				end
			end
		end

	else
		target_input(iotbl, internal_vid);
	end
	
end

local function gridledetail_contextinput()

	if (detailview.zoomed) then
		detailview.zoomed = false;
		if (detailview.modeldisplay_aid ~= BADID) then
			audio_gain(detailview.modeldisplay_aid, settings.movieagain * 0.5, 20);
		end

		local o = detailview.model.default_orientation;
		move3d_model(detailview.model.vid, detailview.startpos.x, detailview.startpos.y, detailview.startpos.z, 20);
		orient3d_model(detailview.model.vid, o.roll, o.pitch, o.yaw, 20);
	else
		move3d_model(detailview.model.vid, detailview.zoompos.x, detailview.zoompos.y, detailview.zoompos.z, 20);
		orient3d_model(detailview.model.vid, detailview.zoomang.roll, detailview.zoomang.pitch, detailview.zoomang.yaw, 20);
		if (detailview.modeldisplay_aid ~= BADID) then
			audio_gain(detailview.modeldisplay_aid, settings.movieagain, 20);
		end
		detailview.zoomed = true;
	end
	
end

function gridledetail_input(iotbl)
	if (valid_vid(internal_vid)) then
		return gridledetail_internalinput(iotbl);
	end

-- just ignore analog events for now
	if (iotbl.kind == "digital") then
		local restbl = keyconfig:match(iotbl);
		if (restbl == nil or iotbl.active == false) then return; end

-- just override "CONTEXT" from the dispatchtbl currently
		for ind,val in pairs(restbl) do
			if (val == "CONTEXT") then
				gridledetail_contextinput();
			else
				if (detailview.iodispatch[val]) then 
					detailview.iodispatch[val](restbl); 
				end
			end

		end
	end
		
end

local function gridledetail_checkmodel(setname)
	if (gridledetail_modellut == nil) then
		-- since resource() doesn't yield anything for directory entries, and no model is expected to
-- provide a .lua script for loading, we glob and cache 
		local tmptbl = glob_resource("models/*");
		gridledetail_modellut = {};
		gridledetail_neogeosets = {};

-- special treatment of neo-geo games (and possibly later on, naomi), instancing etc. isn't really
-- implemented for 3D yet, so need to reload even the generic models. 
		if (resource("neogeo_sets") and open_rawresource("neogeo_sets")) then
			local setname = read_rawresource();
			
			while (setname ~= nil) do
				gridledetail_neogeosets[setname] = true;
				setname = read_rawresource();
			end
			
			close_rawresource();
		end

		for a,b in pairs(tmptbl) do
			gridledetail_modellut[b] = true;
		end
	end

-- we might not have a model, but do we have a gamescript?
	if (gridledetail_modellut[setname] == nil) then
		if (resource("gamescripts/" .. setname .. ".lua")) then
			return "gamescripts/" .. setname .. ".lua";

-- should split this to treat more "generic" models (e.g. nintendo, ...) 
		elseif (gridledetail_neogeosets[setname] == true and
				gridledetail_modellut["neogeo"]) then
			return "neogeo";
		end
	else
		return setname;
	end

	return nil;
end

function gridledetail_havedetails(gametbl)
	local res = gridledetail_checkmodel(gametbl.setname);

-- quickhack for ex. fba importer that has mame shortnames but uses the fileextension in the setname
	if (not res) then
		res = gridledetail_checkmodel( string.sub(gametbl.setname, 1, -5) );
	end

	return res;
end

local function find_detail(step, zout)
	local nextind = detailview.curind + step;

-- scan and look for next
	while nextind ~= detailview.curind do
		if (nextind == 0) then nextind = #settings.games
		elseif (nextind > #settings.games) then nextind = 1; end

		if (settings.games[nextind].resources == nil) then
			settings.games[nextind].resources = resourcefinder_search( settings.games[nextind], true); 
		end

		detailres = gridledetail_havedetails(settings.games[nextind]);
		if (detailres) then break; end

		nextind = nextind + step;
	end
	
-- at the very worst, we'll loop (and it takes a bit of time .. )
	if (detailview.curind ~= nextind) then
		gridledetail_freeview(2, 6.0);
		gridledetail_buildview(detailres, settings.games[ nextind ])

-- start "far away" and quickly zoom in, while that happens, prevent some keys from being used ("cooldown") 
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, 0.0, zout);
		move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
		detailview.zoomed = false;
		detailview.zoompress = nil;
		detailview.cooldown = settings.transitiondelay;
		detailview.curind = nextind;
		play_audio(soundmap["DETAILVIEW_SWITCH"]);
	end	
end

function gridledetail_show(detailres, gametbl, ind)
	if (gridledetail_loaded == false) then
		gridledetail_load();
	end

	-- override I/O table
	if (detailres == nil or 
			gametbl == nil or 
			gridledetail_buildview(detailres, gametbl) == nil) then return;
	else
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, -6.0, -4.0);
		move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
	end

-- repeat-rate is ignored here
	kbd_repeat(0);
	
	detailview.fullscreen = false;
	detail_toggles = settings.internal_toggles;
	
	gridvideo = gridle_video_event;
	gridclock = gridle_clock_pulse;
	
	gridle_video_event = gridledetail_video_event;
	gridle_input = gridledetail_input;
	gridle_clock_pulse = gridledetail_clock_pulse;

	detailview.curind = ind;
	detailview.curgame = gametbl;
	detailview.cooldown = 0;
	
	detailview.iodispatch = {};
	detailview.iodispatch["MENU_UP"] = function(iotbl)
		if (detailview.cooldown == 0) then find_detail(-1, -80.0); end
	end
	detailview.iodispatch["MENU_DOWN"] = function(iotbl)
		if (detailview.cooldown == 0) then find_detail(1, -80.0); end
	end
	detailview.iodispatch["MENU_LEFT"] = function(iotbl)
		if (detailview.model) then
			if (detailview.cooldown == 0) then
				instant_image_transform(detailview.model.vid);
			end

			rotate3d_model(detailview.model.vid, 45, 0, 0, 10);
		end
	end
	
	detailview.iodispatch["MENU_RIGHT"] = function(iotbl)
		if (detailview.model) then
			if (detailview.cooldown == 0) then
				instant_image_transform(detailview.model.vid);
			end
			
			rotate3d_model(detailview.model.vid, -45, 0, 0, 10);
		end
	end

	detailview.iodispatch["LAUNCH"] = function(iotbl)
		local captbl = launch_target_capabilities( detailview.game.target )

		local launch_internal = (settings.default_launchmode == "Internal" or captbl.external_launch == false) and captbl.internal_launch;

			if (launch_internal) then
				gridledetail_setnoisedisplay();
				gridle_load_internal_extras();
	
				internal_vid = launch_target( detailview.game.gameid, LAUNCH_INTERNAL, gridledetail_internal_status );
				if (internal_vid and settings.autosave == "On") then
					internal_statectl("auto", false);
				end
			else
				erase_grid(true);
				launch_target( detailview.game.gameid, LAUNCH_EXTERNAL);
				move_cursor(0);
				build_grid(settings.cell_width, settings.cell_height);
			end
		
	end

	detailview.iodispatch["MENU_ESCAPE"] = function(iotbl)
		play_audio(soundmap["DETAILVIEW_FADE"]);
		gridledetail_freeview(1, -6.0);

		gridle_clock_pulse = gridclock;
		gridle_input = gridle_dispatchinput;
		gridle_video_event = gridvideo;
		
		detailview.iodispatch = griddispatch;
		kbd_repeat(settings.repeatrate);
		move_cursor(0);
	end
end
