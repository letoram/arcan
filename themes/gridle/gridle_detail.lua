detailview = {
	modeldisplay_aid = BADID,
	loaded = false
};

local function gridledetail_load()
-- non-visible 3d object as camtag
	detailview.dir_light = load_shader("shaders/dir_light.vShader", 
		"shaders/dir_light.fShader", "default3d");

	shader_uniform(detailview.dir_light, 
		"map_diffuse", "i", PERSIST, 0);

	shader_uniform(detailview.dir_light, "wlightdir", "fff", 
		PERSIST, 1.0, 0.0, 0.0);

	shader_uniform(detailview.dir_light, "wambient", 
		"fff", PERSIST, 0.3, 0.3, 0.3);

	shader_uniform(detailview.dir_light, "wdiffuse", 
		"fff", PERSIST, 0.3, 0.3, 0.3);

	detailview.loaded = true;
end

-- figure out what to show based on a "source data string" 
-- (detailres, dependency to havedetails) and a gametable
local function gridledetail_buildview(detailres, gametbl )
	video_3dorder(ORDER_LAST);

	detailview.game  = gametbl;
	detailview.model = setup_cabinet_model(detailres, gametbl.resources, {});
	
-- replace the "on load" fullbright shader with a directional lighting one  
	if (detailview.model) then
		image_shader(detailview.model.vid, detailview.dir_light);
		
-- we can hardcode these values because the "scale vertices" 
-- part forces the actual value range of any model hierarchy to -1..1
		detailview.startpos = {x = -1.0, y = 0.0, z = -4.0};
		detailview.startang = {roll = 0, pitch = 0, yaw = 0};
			
-- if the model specifies a default view pos (position + 
-- roll/pitch/yaw), set that one as the target)
		detailview.zoompos   = detailview.model.screenview.position;
		detailview.zoomang   = detailview.model.screenview.orientation;
		detailview.zoompos.x = detailview.zoompos.x * -1;
		detailview.zoompos.y = detailview.zoompos.y * -1;
		detailview.zoompos.z = detailview.zoompos.z * -1;

		return true;
	end

	return false;
end

-- deallocate a model and all associated resources (movie / screenshot),
-- axis (x:0, y:1, z:2), mag (value to add to the axis) 
local function gridledetail_freeview(axis, mag)
	local dx = 0;
	local dy = 0;
	local dz = 0;
	
	if (axis == 0) then dx = mag;
		elseif (axis == 1) then dy = mag;
		elseif (axis == 2) then dz = mag;
	end

	move3d_model(detailview.model.vid, 
		detailview.startpos.x + dx,
		detailview.startpos.y + dy, 
		detailview.startpos.z + dz, 20 + settings.transitiondelay
	);

	detailview.model:destroy(settings.transitiondelay);
	
	detailview.fullscreen = false;
	detailview.model = nil;
end

function gridledetail_internal_status(source, datatbl)
	if (datatbl.kind == "resized") then
		local flipped = datatbl.mirrored ~= 1;
		local displayimg = null_surface(1,1);
		image_sharestorage(source, displayimg);
		detailview.model:update_display(displayimg, flipped); 
	
		audio_gain(datatbl.source_audio, settings.internal_gain, NOW);
		move3d_model(detailview.model.vid, 
			detailview.zoompos.x, 
			detailview.zoompos.y, 
			detailview.zoompos.z, 20
		);

		rotate3d_model(detailview.model.vid, 
			detailview.zoomang.roll, 
			detailview.zoomang.pitch, 
			detailview.zoomang.yaw, 20, ROTATE_ABSOLUTE
		);
	end
end

-- just use this to make sure we don't load 
-- models before the animation has finished.  
function gridledetail_clock_pulse(tick)
	timestamp = tick;
	if (detailview.cooldown > 0) then 
		detailview.cooldown = detailview.cooldown - 1; 
	end
end

local orig_order = order_image;
function trace_order(vid, order)
	orig_order(vid, order);
end

-- switch between running with fullscreen and 
-- running with cabinet zoomed in
local function gridledetail_switchfs()

	if (detailview.fullscreen) then
-- undo vectordisplay etc. remove the 
-- "black image" used to block background
		gridlemenu_rebuilddisplay();
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

-- setup black frame around output, 
-- then initialze effects etc.
		internal_vidborder = instance_image( imagery.black );
		image_tracetag(internal_vidborder, "detailfs_background");
		detailview.fullscreen = true;
		image_mask_clearall(internal_vidborder);
		order_image(internal_vidborder, INGAMELAYER_BACKGROUND);
		resize_image(internal_vidborder, VRESW, VRESH);
		show_image(internal_vidborder);

		image_tracetag(internal_vid,"internal_vid(detailfs)");
		show_image(internal_vid);
		image_mask_clear(internal_vid, MASK_OPACITY);

		order_image = trace_order;

		gridlemenu_rebuilddisplay(settings.internal_toggles);
	end
end

function gridledetail_stopinternal()
-- stop the internal launch, zoom out 
-- the model and replace display with static
	if (valid_vid( internal_vidborder )) then 
		delete_image(internal_vidborder);
		internal_vidborder = nil;
	end

-- clean-up any used effect resources
	undo_displaymodes();
	detailview.fullscreen = false;
	
	if (settings.autosave == "On") then
		internal_statectl("auto", true);
		expire_image(internal_vid, 20);
		blend_image(internal_vid, 0.0, 20);
	else
		delete_image(internal_vid);
	end

	gridle_delete_internal_extras();
	show_image(detailview.model.vid);
	detailview.model:display_broken();

	if (valid_vid(internal_vid)) then
		delete_image(internal_vid);
	end
	internal_vid = BADID;

-- reset model to start position
	rotate3d_model(detailview.model.vid, 
		0, 0, 0, 20, ROTATE_ABSOLUTE);
	move3d_model(detailview.model.vid, 
		detailview.startpos.x, 
		detailview.startpos.y, 
		detailview.startpos.z, 20
	);
end

-- regular dispatch-input, but we override MENU/etc. 
-- to support switching between fullscreen and not
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
	
-- iotbl.active filter here is just to make sure 
-- we don't save twice (press and release) 
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

-- used to zoom in / out of the model view 
local function gridledetail_contextinput()
	if (detailview.zoomed) then
		detailview.zoomed = false;
		if (detailview.modeldisplay_aid ~= BADID) then
			audio_gain(detailview.modeldisplay_aid, 
				settings.movieagain * 0.5, 20);
		end

		move3d_model(detailview.model.vid, 
			detailview.startpos.x, 
			detailview.startpos.y, 
			detailview.startpos.z, 20
		);
		rotate3d_model(detailview.model.vid, 0, 0, 0, 20, ROTATE_ABSOLUTE);
	else
		move3d_model(detailview.model.vid, 
			detailview.zoompos.x, 
			detailview.zoompos.y, 
			detailview.zoompos.z, 20);

		rotate3d_model(detailview.model.vid, 
			detailview.zoomang.roll, 
			detailview.zoomang.pitch,
			detailview.zoomang.yaw, 
			20, ROTATE_ABSOLUTE);

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

local function find_detail(step, zout)
	local nextind = detailview.curind + step;

-- scan and look for next
	while nextind ~= detailview.curind do
		if (nextind == 0) then nextind = #settings.games
		elseif (nextind > #settings.games) then nextind = 1; end

		if (settings.games[nextind].resources == nil) then
			settings.games[nextind].resources = 
				resourcefinder_search( settings.games[nextind], true); 
		end

		detailres = find_cabinet_model(settings.games[nextind]);
		if (detailres) then break; end

		nextind = nextind + step;
	end
	
-- at the very worst, we'll loop (and it takes a bit of time .. )
	if (detailview.curind ~= nextind) then
		gridledetail_freeview(2, 6.0);
		gridledetail_buildview(detailres, settings.games[ nextind ])

-- start "far away" and quickly zoom in, while 
-- that happens, prevent some keys from being used ("cooldown")
		show_image(detailview.model.vid);
		move3d_model(detailview.model.vid, -1.0, 0.0, zout);
		move3d_model(detailview.model.vid, 
			-1.0, 0.0, -4.0, settings.transitiondelay);

		detailview.zoomed = false;
		detailview.zoompress = nil;
		detailview.cooldown = settings.transitiondelay;
		detailview.curind = nextind;
		play_audio(soundmap["DETAILVIEW_SWITCH"]);
	end	
end

function gridledetail_show(detailres, gametbl, ind)
	if (detailview.loaded == false) then
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
	gridle_clock_pulse = gridledetail_clock_pulse;
	dispatch_push({}, "gridle_detail", gridledetail_input);
	
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

			rotate3d_model(detailview.model.vid, 0, 0, 20, 10, ROTATE_RELATIVE);
		end
	end
	
	detailview.iodispatch["MENU_RIGHT"] = function(iotbl)
		if (detailview.model) then
			if (detailview.cooldown == 0) then
				instant_image_transform(detailview.model.vid);
			end
			
			rotate3d_model(detailview.model.vid, 0, 0, -20, 10, ROTATE_RELATIVE);
		end
	end

-- launch based on current preferences and target capabilities 
	detailview.iodispatch["MENU_SELECT"] = function(iotbl)
		local captbl = launch_target_capabilities( detailview.game.target )
		local launch_internal = (settings.default_launchmode 
			== "Internal" or captbl.external_launch == false) 
			and captbl.internal_launch;
		
			if (launch_internal) then
			settings.capabilities = captbl;
				gridle_load_internal_extras();

				internal_vid = launch_target(
					detailview.game.gameid, LAUNCH_INTERNAL, 
					gridledetail_internal_status );
	
				if (internal_vid) then
					settings.internal_txcos = image_get_txcos(internal_vid);

					if (settings.autosave == "On") then
						internal_statectl("auto", false);
					end
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
		gridle_video_event = gridvideo;
		
		detailview.iodispatch = griddispatch;
		kbd_repeat(settings.repeatrate);
		move_cursor(0);
		dispatch_pop();
	end
end
