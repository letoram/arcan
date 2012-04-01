-- Implement "detail view" in Gridle, albeit easily adapted to other themes.
--
-- gridledetail_show();
--  replaces the current "grid" with a single- game view,
--  trying to squeeze in as much extra information as possible (3d model,
--  flyer, history)
--
-- first determines layout by looking for specific resources;
-- 1. game- specific script (gamescripts/setname.lua)
-- 2. 3d- view (models/setname)
-- 3. (fallback) flow layout of whatever other (marquee, cpo, flyer, etc.) that was found.
--
-- Also allows for single (menu- up / down) navigation between games
-- MENU_ESCAPE returns to game
--
local detailview = {
	movie_vid = BADID,
	internal_vid = BADID
};
local loaded = false;

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
	diffusef_shader  = load_shader("shaders/flipy.vShader", "shaders/diffuse_only.fShader", "diffuse");
	diffuse_shader   = load_shader("shaders/diffuse_only.vShader", "shaders/diffuse_only.fShader", "diffuse");
	
	shader_uniform(default_shader3d, "wlightdir", "fff", PERSIST, 1.0, 0.0, 0.0);
	shader_uniform(default_shader3d, "wambient", "fff", PERSIST, 0.3, 0.3, 0.3);
	shader_uniform(default_shader3d, "wdiffuse", "fff", PERSIST, 0.6, 0.6, 0.6);
	shader_uniform(default_shader3d, "map_diffuse", "i", PERSIST, 0);
	shader_uniform(texco_shader, "speedfact", "f", PERSIST, 24.0);

loaded = true;
end

local function gridledetail_setnoisedisplay()
	if (detailview.model.labels["display"] == nil) then return; end
	
	local rvid = set_image_as_frame(detailview.model.vid, instance_image(noise_image), detailview.model.labels["display"], 1);
	mesh_shader(detailview.model.vid, texco_shader, detailview.model.labels["display"]);

	if (rvid ~= BADID) then 
		delete_image(rvid); 
	end
end

local function gridledetail_imagestatus(source, status)
-- all asynchronous operations can fail (status == 0), or the resource may not be interesting anymore
	if (status == 0 or source ~= detailview.asynchimg_dstvid) then 
		delete_image(source);
	else
-- the last flag, detatches the vid from the default render-list, however it will still be an addressable vid,
-- we can't do this for movie, as we need 'tick' operations for it to properly poll the frameserver
		mesh_shader(detailview.model.vid, diffusef_shader, detailview.model.labels["display"]);
		rvid = set_image_as_frame(detailview.model.vid, source, detailview.model.labels["display"]);

		if (rvid ~= ARCAN_BADID) then  
			delete_image(rvid);
		end
	end
end

local function gridledetail_moviestatus(source, status)
	if (status == 1 and source == detailview.asynchimg_dstvid) then
		vid,aid = play_movie(source);
		resize_image(vid, settings.cell_width, settings.cell_height);
		
		audio_gain(aid, 0.0);
		audio_gain(aid, 1.0, settings.fadedelay);
	end
	
	gridledetail_imagestatus(source, status);
end

-- figure out what to show based on a "source data string" (detailres, dependency to havedetails) and a gametable
local function gridledetail_buildview(detailres, gametbl )

-- if we have a "load script", use that.
	if (".lua" == string.sub(detailres, -4, -1)) then
		return nil
	else
-- otherwise, use the generic model loader		
		detailview.game = gametbl;
		detailview.model = load_model(detailres);

-- this can fail (no model found) 
		if (detailview.model) then

			image_shader(detailview.model.vid, default_shader3d);
			scale_3dvertices(detailview.model.vid);

-- we can hardcode these values because the "scale vertices" part forces the actual value range of any model hierarchy to -1..1
			detailview.startx = -1.0;
			detailview.starty = 0.0;
			detailview.startz = -4.0;

-- if the model specifies a default view pos (position + view + up), set that one as the target (and calculate linear steps by scaling)
			if (detailview.model.screenview) then
					
			else
				
-- otherwise just thake a harcoded guess 
				detailview.zoomx = 0.0;
				detailview.zoomy = -0.5;
				detailview.zoomz = -1.0;
			end

-- set specific shaders for marquee (fullbright, blink every now and then 
			if (detailview.model.labels["marquee"]) then 
				mesh_shader(detailview.model.vid, backlit_shader3d, detailview.model.labels["marquee"]); 
			end
			if (detailview.model.labels["display"]) then
				local moviefile = have_video(detailview.game.setname);
				if (moviefile) then
					detailview.asynchimg_dstvid = load_movie(moviefile, 1, gridledetail_moviestatus);
					print("movie allocated: " .. detailview.asynchimg_dstvid);
				elseif resource("screenshots/" .. detailview.game.setname .. ".png") then
					detailview.asynchimg_dstvid = load_image_asynch( "screenshots/" .. detailview.game.setname .. ".png", gridledetail_imagestatus);
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

		move3d_model(detailview.model.vid, detailview.startx + dx, detailview.starty + dy, detailview.startz + dz, 20 + settings.transitiondelay);
		expire_image(detailview.model.vid, 20 + settings.transitiondelay);
		detailview.model = nil;
	end
end

function gridledetail_video_event(source, event)
	if (event.kind == "resized") then
		if (source == detailview.internal_vid) then
			resize_image(source, event.width, event.height, 0);

			local rvid = set_image_as_frame(detailview.model.vid, source, detailview.model.labels["display"]);
			if (rvid ~= source and rvid ~= BADID) then delete_image(rvid); end 
			
-- with a gl source, it means it comes from a readback, means that we might need to flip texture coordinates for it to be rendered correctly
			if (event.glsource) then 
				mesh_shader(detailview.model.vid, diffusef_shader, detailview.model.labels["display"]);
			else 
				mesh_shader(detailview.model.vid, diffuse_shader, detailview.model.labels["display"]); 
			end

			move3d_model(detailview.model.vid, detailview.zoomx, detailview.zoomy, detailview.zoomz, 20);
		end
	end
end

function gridledetail_clock_pulse(tick)
	timestamp = tick;
	if (detailview.cooldown > 0) then detailview.cooldown = detailview.cooldown - 1; end
	
	if (detailview.zoompress and (tick - detailview.zoompress > 200)) then
		detailview.zoomed = true;
		props = image_surface_properties(detailview.model.vid);
		move3d_model(detailview.model.vid, props.x + gridledetail_stepx, props.y + gridledetail_stepy, props.z + gridledetail_stepz);
	end
end

function gridledetail_internalinput(iotbl)
	local restbl = keyconfig:match(iotbl);

	if (restbl) then
		for ind,val in pairs(restbl) do
			if (iotbl.active and val == "ZOOM_CURSOR") then
-- switch between running with fullscreen and running with cabinet zoomed in
				if (detailview.fullscreen) then
					hide_image(detailview.internal_vid);
					show_image(detailview.model.vid);
					detailview.fullscreen = false;
				else
					detailview.fullscreen = true;
					show_image(detailview.internal_vid);

					local props = image_surface_properties(detailview.internal_vid);
					
					if (props.width / props.height > 1.0) then -- horizontal game
						resize_image(detailview.internal_vid, VRESW, 0, NOW);
					else -- vertical game
						resize_image(detailview.internal_vid, VRESH, 0, NOW);
						props = image_surface_properties(detailview.internal_vid);
						if (props.width < VRESW) then
							move_image(detailview.internal_vid, 0.5 * (VRESW - props.width), 0, NOW);
						end
					end
	
					hide_image(detailview.model.vid);
					return;
				end
			elseif (iotbl.active and val == "MENU_ESCAPE") then
-- stop the internal launch, zoom out the model and replace display with static
				delete_image(detailview.internal_vid);
				detailview.internal_vid = BADID;
				show_image(detailview.model.vid);
				gridledetail_setnoisedisplay();
				move3d_model(detailview.model.vid, detailview.startx, detailview.starty, detailview.startz, 20);
				return;
			end
		end
	end

	target_input(iotbl, detailview.internal_vid);
end

-- 
-- need some more advanced functionality to "zoom"
-- a short press will immediately zoom in/out from the default position to focus on the display
-- a continous press will gradually zoom in
-- if we have an internal launch running though, MENU_ZOOM will switch from fullscreen- display to "mapped to monitor"
--
function gridledetail_input(iotbl)
-- if internal launch is active, only "ESCAPE" and "ZOOM" is accepted, all the others are being forwarded.
	if (detailview.internal_vid ~= BADID) then
		return gridledetail_internalinput(iotbl);
	end
	
	if (iotbl.kind == "digital") then
		local restbl = keyconfig:match(iotbl);
		if (restbl == nil) then return; end

		for ind,val in pairs(restbl) do
-- This only works without key-repeat on
			if (val == "ZOOM_CURSOR" and detailview.cooldown == 0) then
					if (iotbl.active) then -- start moving
						detailview.zoompress = timestamp;
						gridledetail_stepx = 0.5 * ((detailview.zoomx - detailview.startx) / settings.transitiondelay);
						gridledetail_stepy = 0.5 * ((detailview.zoomy - detailview.starty) / settings.transitiondelay);
						gridledetail_stepz = 0.5 * ((detailview.zoomz - detailview.startz) / settings.transitiondelay);
					else -- release
						if (detailview.zoompress and 
								timestamp - detailview.zoompress < 200) then
							-- full- zoom or revert to normal
							if (detailview.zoomed) then
								detailview.zoomed = false;
								move3d_model(detailview.model.vid, detailview.startx, detailview.starty, detailview.startz, 20);
							else
								move3d_model(detailview.model.vid, detailview.zoomx, detailview.zoomy, detailview.zoomz, 20);
								detailview.zoomed = true;
							end
						else -- stop moving
							gridledetail_stepx = 0.0;
							gridledetail_stepy = 0.0;
							gridledetail_stepz = 0.0;
						end
						detailview.zoompress = nil;
					end
			end
		end

-- The rest of the dispatch is similar to gridle.lua 
		if (restbl and iotbl.active) then
			for ind,val in pairs(restbl) do
				if (settings.iodispatch[val]) then	settings.iodispatch[val](restbl); end
			end
		end
	end
end

function gridledetail_havedetails(gametbl)
	if (gridledetail_modellut == nil) then
		-- since resource() doesn't yield anything for directory entries, and no model is expected to
-- provide a .lua script for loading, we glob and cache 
		local tmptbl = glob_resource("models/*");
		gridledetail_modellut = {};
		gridledetail_neogeosets = {};

-- special treatment of neo-geo games (and possibly later on, naomi) 
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
	if (gridledetail_modellut[gametbl.setname] == nil) then
		if (resource("gamescripts/" .. gametbl.setname .. ".lua")) then
			return "gamescripts/" .. gametbl.setname .. ".lua";

		elseif (gridledetail_neogeosets[gametbl.setname] == true and
				gridledetail_modellut["neogeo"]) then
			return "neogeo";
		end
	else
		return gametbl.setname;
	end

	return nil;
end

local function find_prevdetail()
	local nextind = detailview.curind - 1;
	local detailres = nil;
	
-- reverse- scan for a gametbl that 'havedetail' will return something for
	while nextind ~= detailview.curind do
		if (nextind == 0) then nextind = #settings.games end
		detailres = gridledetail_havedetails(settings.games[nextind]);
		if (detailres) then break; end
		nextind = nextind - 1;
	end
	
-- if we found a new, have a different fade "out" 
	if (detailview.curind ~= nextind) then
		gridledetail_freeview(2, 6.0);
		gridledetail_buildview(detailres, settings.games[ nextind ])
-- start "far away" and quickly zoom in, while that happens, prevent some keys from being used ("cooldown") 
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, 0.0, -80.0);
		move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
		detailview.zoomed = false;
		detailview.zoompress = nil;
		detailview.cooldown = settings.transitiondelay;
		detailview.curind = nextind;
	end	
end

local function find_nextdetail(current, gametbl)
	local nextind = detailview.curind + 1;
	local detailres = nil;
	
-- reverse- scan for a gametbl that 'havedetail' will return something for
	while nextind ~= detailview.curind do
		if (nextind > #settings.games) then nextind = 1; end
		detailres = gridledetail_havedetails(settings.games[nextind]);
		if (detailres) then break; end
		nextind = nextind + 1;
	end
	
-- if we found a new, have a different fade "out" 
	if (detailview.curind ~= nextind) then
		gridledetail_freeview(2, -80.0);
		gridledetail_buildview(detailres, settings.games[ nextind ]);
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, 0.0, 6.0);
		move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
		detailview.zoomed = false;
		detailview.zoompress = nil;
		detailview.cooldown = settings.transitiondelay;
		detailview.curind = nextind;
	end
end

function gridledetail_show(detailres, gametbl, ind)
	if (loaded == false) then
		gridledetail_load();
	end

	-- override I/O table
	if (detailres == nil or gametbl == nil or gridledetail_buildview(detailres, gametbl) == nil) then
		return;
	else
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, -6.0, -4.0);
		move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
	end
	
	kbd_repeat(0);
	
	griddispatch = settings.iodispatch;
	gridvideo = gridle_video_event;
	gridinput = gridle_input;
	gridclock = gridle_clock_pulse;
	
	gridle_video_event = gridledetail_video_event;
	gridle_input = gridledetail_input;
	gridle_clock_pulse = gridledetail_clock_pulse;

	detailview.curind = ind;
	detailview.curgame = gametbl;
	detailview.cooldown = 0;
	
	settings.iodispatch = {};
	settings.iodispatch["MENU_UP"] = function(iotbl)
		if (detailview.cooldown == 0) then find_nextdetail(); end
	end
	settings.iodispatch["MENU_DOWN"] = function(iotbl)
		if (detailview.cooldown == 0) then find_prevdetail(); end
	end
	settings.iodispatch["MENU_LEFT"] = function(iotbl)
		if (detailview.model) then
			if (detailview.cooldown == 0) then
				instant_image_transform(detailview.model.vid);
			end

			rotate3d_model(detailview.model.vid, 45, 0, 0, 10);
		end
	end
	
	settings.iodispatch["MENU_RIGHT"] = function(iotbl)
		if (detailview.model) then
			if (detailview.cooldown == 0) then
				instant_image_transform(detailview.model.vid);
			end
			
			rotate3d_model(detailview.model.vid, -45, 0, 0, 10);
		end
	end

-- Don't add this label unless internal support is working for the underlying platform
	settings.iodispatch["LAUNCH_INTERNAL"] = function(iotbl)
		gridledetail_setnoisedisplay();
		local vid, aid = launch_target(detailview.game.title, LAUNCH_INTERNAL);
		detailview.internal_vid = vid;
	end

-- Works the same, just make sure to stop any "internal session" as it is 
	settings.iodispatch["MENU_SELECT"] = function (iotbl) 
		launch_target( current_game().title, LAUNCH_EXTERNAL);
		gridledetail_setnoisedisplay();
	end 

	settings.iodispatch["MENU_ESCAPE"] = function(iotbl)
		gridledetail_freeview(1, -6.0);

		gridle_clock_pulse = gridclock;
		gridle_input = gridinput;
		gridle_video_event = gridvideo;
		
		build_grid(settings.cell_width, settings.cell_height);
		settings.iodispatch = griddispatch;
	end

	erase_grid(false);
end
