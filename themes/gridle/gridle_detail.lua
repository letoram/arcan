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
local detailview = {};
local loaded = false;

local function gridledetail_load()
	noise_image      = random_surface(256, 256);

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

local function gridledetail_buildview(detailres, gametbl )
	if (".lua" == string.sub(detailres, -4, -1)) then
		return nil
	else
		detailview.game = gametbl;
		detailview.model = load_model(detailres);
		if (detailview.model) then
			show_image(detailview.model.vid);
			move3d_model(detailview.model.vid, -1.0, 0.0, -40.0);
			move3d_model(detailview.model.vid, -1.0, 0.0, -4.0, settings.transitiondelay);
			image_shader(detailview.model.vid, default_shader3d);
			detailview.startx = -1.0;
			detailview.starty = 0.0;
			detailview.startz = -4.0;
			detailview.zoomx = 0.0;
			detailview.zoomy = -0.5;
			detailview.zoomz = -1.0;
		
			if (detailview.model.labels["display"]) then
				set_image_as_frame(detailview.model.vid, noise_image, detailview.model.labels["display"], 1);
				mesh_shader(detailview.model.vid, texco_shader, detailview.model.labels["display"]);
			end

			if (detailview.model.labels["marquee"]) then
				mesh_shader(detailview.model.vid, backlit_shader3d, detailview.model.labels["marquee"]);
			end

			scale_3dvertices(detailview.model.vid);
			local moviefile = have_video(setname);
			if (moviefile) then
				movievid = load_movie(moviefile);
			end

			return true;
		else
			return nil
		end
	end
end

local function gridledetail_freeview()
	if (detailview.model) then
		local delay = 2.0 * settings.transitiondelay;
		if (gridledetail_zoomed) then
			move3d_model(detailview.model.vid, detailview.startx, detailview.starty, detailview.startz, delay);
			delay = delay + delay;
		end

		move3d_model(detailview.model.vid, detailview.startx, detailview.starty - 5.0, detailview.startz, settings.transitiondelay);
		expire_image(detailview.model.vid, delay);
		detailview.model = nil;
	end
end

function gridledetail_video_event(source, event)
	if (event.kind == "resized") then
		if (source == detailview.internal_vid) then
			resize_image(source, event.width, event.height, 0);
			set_image_as_frame(detailview.model.vid, source, detailview.model.labels["display"]);
			print("event.glsource?" .. event.glsource);
			if (event.glsource) then
				mesh_shader(detailview.model.vid, diffusef_shader, detailview.model.labels["display"]);
			else
				mesh_shader(detailview.model.vid, diffuse_shader, detailview.model.labels["display"]);
			end
			move3d_model(detailview.model.vid, detailview.zoomx, detailview.zoomy, detailview.zoomz, 20);
		end
	end

	if (event.kind == "movieready") then
		if (source == movievid) then
			vid,aid = play_movie(movievid);
			audio_gain(aid, 0.0);
			audio_gain(aid, 1.0, settings.fadedelay);
			detailview.movievid = vid;
			if (detailview.model.labels["display"]) then
				set_image_as_frame(detailview.model.vid, vid, detailview.model.labels["display"]);
				mesh_shader(detailview.model.vid, diffusef_shader, detailview.model.labels["display"]);
			end
		else
			delete_image(source);
		end
	end
end

function gridledetail_clock_pulse(tick)
	timestamp = tick;

	if (gridledetail_zoompress and (tick - gridledetail_zoompress > 100)) then
		gridledetail_zoomed = true;
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
				detailview.internal_vid = NULL;
				move3d_model(detailview.model.vid, detailview.startx, detailview.starty, detailview.startz, 20);
				set_image_as_frame(detailview.model.vid, noise_image, detailview.model.labels["display"]);
				mesh_shader(detailview.model.vid, texco_shader, detailview.model.labels["display"]);
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
	if (detailview.internal_vid) then
		return gridledetail_internalinput(iotbl);
	end
	
	if (iotbl.kind == "digital") then
		local restbl = keyconfig:match(iotbl);
		if (restbl == nil) then return; end

		for ind,val in pairs(restbl) do
-- This only works without key-repeat on
			if (val == "ZOOM_CURSOR") then
					if (iotbl.active) then -- start moving
						gridledetail_zoompress = timestamp;
						gridledetail_stepx = 0.5 * ((detailview.zoomx - detailview.startx) / settings.transitiondelay);
						gridledetail_stepy = 0.5 * ((detailview.zoomy - detailview.starty) / settings.transitiondelay);
						gridledetail_stepz = 0.5 * ((detailview.zoomz - detailview.startz) / settings.transitiondelay);
					else -- release
						if (timestamp - gridledetail_zoompress < 100) then
							-- full- zoom or revert to normal
							if (gridledetail_zoomed) then
								gridledetail_zoomed = false;
								move3d_model(detailview.model.vid, detailview.startx, detailview.starty, detailview.startz, 20);
							else
								move3d_model(detailview.model.vid, detailview.zoomx, detailview.zoomy, detailview.zoomz, 20);
								gridledetail_zoomed = true;
							end
						else -- stop moving
							gridledetail_stepx = 0.0;
							gridledetail_stepy = 0.0;
							gridledetail_stepz = 0.0;
						end
						gridledetail_zoompress = nil;
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

		for a,b in pairs(tmptbl) do
			gridledetail_modellut[b] = true;
		end
	end

-- we might not have a model, but do we have a gamescript?
	if (gridledetail_modellut[gametbl.setname] == nil) then
		if (resource("gamescripts/" .. gametbl.setname .. ".lua")) then
			return "gamescripts/" .. gametbl.setname .. ".lua";
		end
	else
		return gametbl.setname;
	end

	return nil;
end

function gridledetail_show(detailres, gametbl)
	if (loaded == false) then
		gridledetail_load();
	end

	if (movievid and movievid ~= BADID) then
		delete_image(movievid);
	end

	-- override I/O table
	if (detailres == nil or gametbl == nil or gridledetail_buildview(detailres, gametbl) == nil) then
		return;
	end
	
	kbd_repeat(0);
	
	griddispatch = settings.iodispatch;
	gridvideo = gridle_video_event;
	gridinput = gridle_input;
	gridclock = gridle_clock_pulse;
	
	gridle_video_event = gridledetail_video_event;
	gridle_input = gridledetail_input;
	gridle_clock_pulse = gridledetail_clock_pulse;
	
	settings.iodispatch = {};
	settings.iodispatch["MENU_UP"] = function(iotbl)
-- scan for next detailview
	end
	settings.iodispatch["MENU_DOWN"] = function(iotbl)
-- scan for previous detailview
	end
	settings.iodispatch["MENU_LEFT"] = function(iotbl)
		if (detailview.model) then
			instant_image_transform(detailview.model.vid);
			rotate3d_model(detailview.model.vid, 45, 0, 0, 10);
		end
	end
	
	settings.iodispatch["MENU_RIGHT"] = function(iotbl)
		if (detailview.model) then
			instant_image_transform(detailview.model.vid);
			rotate3d_model(detailview.model.vid, -45, 0, 0, 10);
		end
	end

-- Don't add this label unless internal support is working for the underlying platform
	settings.iodispatch["LAUNCH_INTERNAL"] = function(iotbl)
		if (detailview.movie) then delete_image(detailview.movie, 20); end
		local vid, aid = launch_target(detailview.game.title, LAUNCH_INTERNAL);

		set_image_as_frame(detailview.model.vid, noise_image, detailview.model.labels["display"]);
		mesh_shader(detailview.model.vid, texco_shader, detailview.model.labels["display"]);
		detailview.internal_vid = vid;
	end

-- Works the same, just make sure to stop any "internal session" as it is 
	settings.iodispatch["MENU_SELECT"] = griddispatch["MENU_SELECT"];

	settings.iodispatch["MENU_ESCAPE"] = function(iotbl)
		gridledetail_freeview();

		gridle_clock_pulse = gridclock;
		gridle_input = gridinput;
		gridle_video_event = gridvideo;
		
		build_grid(settings.cell_width, settings.cell_height);
		settings.iodispatch = griddispatch;
	end

	erase_grid(false);
end
