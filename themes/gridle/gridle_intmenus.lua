-- 
-- Same mess as with gridle_settings
-- most are just lists of  textlabels mapping to a similar callback structure that, when triggered,
-- either spawns a submenu or updates the settings table, possibly calling store_key.
--
-- The ones that work differently are mostly shader submenu (scans filesystem)
-- saves/loads menu (scans filesystem and pops up OSD keyboard)
-- input-port config menu (generates "N" slots, with possible constraints for each submenu in each slot)
--
-- changes to most/all of these needs to be tested both from "grid view" and from "detailed view + zoom"
--

local scalemodelist = {
	"Keep Aspect",
	"Original Size",
	"2X",
	"Stretch",
	"Rotate CW",
	"Rotate CCW",
	"Bezel"
};

local scalemodeptrs = {};
local function scalemodechg(label, save)
	settings.scalemode = label;
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (save) then
		store_key("scalemode", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	gridlemenu_resize_fullscreen(gridlemenu_destvid);
end

for ind, val in ipairs(scalemodelist) do scalemodeptrs[val] = scalemodechg; end

local inputmodelist = {
-- revert all manipulation to default settings
	"Normal",
	"Rotate CW",
	"Rotate CCW",
	"Invert Axis (analog)",
	"Mirror Axis (analog)"
};

local inputmodeptrs = {};
local function inputmodechg(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (save) then
		store_key("internal_input", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	settings.internal_input = label;
end

inputmodeptrs["Normal"] = inputmodechg;
inputmodeptrs["Rotate CW"] = inputmodechg;
inputmodeptrs["Rotate CCW"] = inputmodechg;
inputmodeptrs["Invert Axis (analog)"] = inputmodechg;
inputmodeptrs["Mirror Axis (analog)"] = inputmodechg;

local audiogainlist = {};
local audiogainptrs = {};

local function audiogaincb(label, save)
	settings.internal_again = tonumber(label);
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	
	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);
		store_key("internal_again", label);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end

	audio_gain(internal_aid, settings.internal_again, settings.fadedelay);
end

for i=0,10 do
	table.insert(audiogainlist, tostring( i * 0.1 ));
	audiogainptrs[tostring( i * 0.1 )] = audiogaincb;
end

local function cocktailmodechg(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (save) then
		store_key("cocktail_mode", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	settings.cocktail_mode = label;
	gridlemenu_resize_fullscreen(gridlemenu_destvid);
end

local cocktaillist = {
	"Disabled",
-- horizontal split, means scale to fit width, instance and flip instance 180
	"H-Split",
-- vsplit means scale to fit width to height, instance, and rotate 90 -90
	"V-Split",
-- same as h-split, but don't rotate 
	"H-Split SBS"
};

local cocktailptrs = {};
for ind, val in ipairs(cocktaillist) do
	cocktailptrs[val] = cocktailmodechg;
end

local inputportoptlist = {
	"GAMEPAD",
	"KEYBOARD",
	"MOUSE" 
};
	
local function inputport_submenu(label, store, silent)
end

local inputportlist = { };
local inputportptrs = { };
for i=1,6 do 
	table.insert(inputportlist, tostring(i));
	inputportptrs[ tostring(i) ] = inputport_submenu;
end

local function setup_cocktail(mode, source, vresw, vresh)
local props = image_surface_properties(source);
	
	imagery.cocktail_vid = instance_image(source);
	image_mask_clear(imagery.cocktail_vid, MASK_OPACITY);
	image_mask_clear(imagery.cocktail_vid, MASK_ORIENTATION);
	resize_image(imagery.cocktail_vid, props.width, props.height);
	show_image(imagery.cocktail_vid);

	if (mode == "H-Split" or mode == "H-Split SBS") then
		if (mode == "H-Split") then rotate_image(imagery.cocktail_vid, 180); end
		image_mask_clear(imagery.cocktail_vid, MASK_POSITION);
		move_image(source, 0.5 * (vresw - props.width), 0.5 * (vresh - props.height));
		move_image(imagery.cocktail_vid, vresw + 0.5 * (vresw - props.width), 0.5 * (vresh - props.height));
		
	elseif (mode == "V-Split") then
		move_image(source, 0.5 * (vresh - props.width), 0.5 * (vresw - props.height))
		move_image(imagery.cocktail_vid, vresh, 0);
		rotate_image(imagery.cocktail_vid, -90);
		rotate_image(source, 90);
	end
end

local function bezel_loaded(source, status)

	if (status == 1) then
		local props = image_storage_properties(source);
		resize_image(source, VRESW, VRESH);
		local x1,y1,x2,y2 = image_borderscan(source);
		x1 = (x1 / props.width) * VRESW;
		x2 = (x2 / props.width) * VRESW;
		y1 = (y1 / props.height) * VRESH;
		y2 = (y2 / props.height) * VRESH;
		
		resize_image(internal_vid, x2 - x1, y2 - y1);
		move_image(internal_vid, x1, y1);
		order_image(source, image_surface_properties(internal_vid).order - 1);
		blend_image(source, 1.0, settings.transitiondelay);
		blend_image(internal_vid, 1.0, settings.transitiondelay);
		bezel_loading = false;
	end
	
end

local function setup_bezel()
	local bzltbl = current_game().resources["bezels"];
	local bezel = bzltbl and bzltbl[1] or nil;

	if (bezel) then
-- this will be cleared everytime internal mode is shut down
		if (valid_vid(imagery.bezel) == false) then
			imagery.bezel = load_image_asynch(bezel, bezel_loaded);
			force_image_blend(imagery.bezel);
			bezel_loading = true;
			hide_image(internal_vid);
		else
			local props = image_surface_properties(imagery.bezel);
			if (bezel_loading == false) then
				bezel_loaded(imagery.bezel, 1);
			end
		end
		
		return true;
	end
	
	return false;
end

function gridlemenu_resize_fullscreen(source)
-- rotations are not allowed for H-Split / H-Split SBS and V-Split needs separate treatment 
	local rotate = (settings.scalemode == "Rotate CW" or settings.scalemode == "Rotate CCW") and (settings.cocktail_mode == "Disabled");
	local scalemode = settings.scalemode;
	local cocktailmode = settings.cocktail_mode;
	
	local windw = VRESW;
	local windh = VRESH;
	rotate_image(source, 0);

	if (valid_vid(imagery.cocktail_vid)) then
		delete_image(imagery.cocktail_vid);
		imagery.cocktail_vid = BADID;
	end
		
	local props = image_surface_initial_properties(source);
	if (rotate) then
		local tmp = windw;
		windw = windh;
		windh = tmp;
		scalemode = "Keep Aspect";
	end

-- use an external image (if found) for defining position and dimensions
	if (scalemode == "Bezel") then
		hide_image(internal_vid);
		if (setup_bezel() == false) then
			scalemode = "Keep Aspect";
			show_image(internal_vid);
		end

-- this excludes cocktailmode from working
		cocktailmode = "Disabled";
	else
		if (valid_vid(imagery.bezel)) then
			hide_image(imagery.bezel);
		end
	end

-- for cocktail-modes, we fake half-width or half-height
	if (cocktailmode ~= "Disabled") then
		if (cocktailmode == "V-Split") then
			local tmp = windw;
			windw = windh;
			windh = tmp;
			windh = windh * 0.5;
			scalemode = "Keep Aspect";
		else
			windw = windw * 0.5;
		end
	end
	
-- some of the scale modes also work for cocktail, treat them the same
	if (scalemode == "Original Size") then
		resize_image(source, props.width, props.height);

	elseif (scalemode == "2X") then
		resize_image(source, props.width * 2, props.height * 2);

	elseif (scalemode == "Keep Aspect") then
-- more expensive than the 'correct' way, but less math ;p  
		local step = 0;
		local ar = props.width / props.height;
		while ( (step < windw) and (step / ar < windh) ) do
			step = step + 1;
		end
	
		resize_image(source, step, math.ceil(step / ar) );
	
	elseif (scalemode == "Stretch") then 
		resize_image(source, windw, windh);
	end
	
-- some operations overshoot, just step down
	props = image_surface_properties(source);
	if (props.width > windw or props.height > windw) then
		local ar = props.width / props.height;
		local step = windw;

		while ( (step > windw ) or (step / ar > windh) ) do
			step = step - 1;
		end
		resize_image(source, step, math.ceil(step / ar) );
	end
	
-- update all the values to the result of calculations
	props = image_surface_properties(source);
	if (settings.cocktail_mode ~= "Disabled") then
		setup_cocktail(settings.cocktail_mode, source, windw, windh);
	else
		if (rotate) then
			rotate_image(source, settings.scalemode == "Rotate CW" and -90 or 90);
			move_image(source, 0.5 * (windh - props.width), 0.5 * (windw - props.height));
		elseif (scalemode ~= "Bezel") then
			move_image(source, 0.5 * (windw - props.width), 0.5 * (windh - props.height));
		end
	end
	
	local sprops = image_storage_properties(source);
	local dprops = image_surface_initial_properties(source);
	
	if (fullscreen_shader) then
		shader_uniform(fullscreen_shader, "rubyInputSize", "ff", PERSIST, sprops.width, sprops.height); -- need to reflect actual texel size
		shader_uniform(fullscreen_shader, "rubyTextureSize", "ff", PERSIST, dprops.width, dprops.height); -- since target is allowed to resize at more or less anytime, we need to update this
		shader_uniform(fullscreen_shader, "rubyOutputSize", "ff", PERSIST, windw, windh);
		shader_uniform(fullscreen_shader, "rubyTexture", "i", PERSIST, 0);
	end
	
end

function gridlemenu_loadshader(basename)
	local vsh = nil;
	local fsh = nil;
	
	if ( resource("shaders/fullscreen/" .. basename .. ".vShader") ) then
		vsh = "shaders/fullscreen/" .. basename .. ".vShader";
	else
		warning("Refusing to load shader(" .. basename .. "), missing .vShader");
		return nil;
	end

	if ( resource("shaders/fullscreen/" .. basename .. ".fShader") ) then
		fsh = "shaders/fullscreen/" .. basename .. ".fShader";
	else
		warning("Refusing to load shader(" .. basename .."), missing .fShader");
		return nil;
	end
	
	fullscreen_shader = load_shader(vsh, fsh, "fullscreen", settings.shader_opts);

-- this might be used from detail-view as well so don't assume we know what to update
	if (internal_vid ~= nil) then
	-- force the shader unto the current vid
		gridlemenu_resize_fullscreen(internal_vid);
		image_shader(internal_vid, fullscreen_shader);
	end
end

local function select_shaderfun(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	
	gridlemenu_loadshader(label);
	settings.fullscreenshader = label;

	if (store) then
		store_key("defaultshader", label);

		if (settings.shader_opts) then
			local keyopts = nil;
			
			for key, val in pairs(settings.shader_opts) do
				if (keyopts == nil) then
					keyopts = key;
				else 
					keyopts = keyopts .. "," .. key;
				end
			end
	
			store_key("defaultshader_defs", keyopts or "");
		end

		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
end

local function get_saveslist(gametbl)
-- check for existing snapshots (ignore auto and quicksave)
	local saveslist = {};
	local saves = glob_resource("savestates/" .. gametbl.target .. "_" .. gametbl.setname .. "_*", 2)
	for ind, val in ipairs( saves ) do
		if not (string.sub( val, -5, -1 ) == "_auto" or 
				string.sub( val, -10, -1 ) == "_quicksave") then
		
			local prefix = string.sub( val, string.len( gametbl.target ) + string.len(gametbl.setname) + 3 );
			table.insert(saveslist, prefix);
		end
	end
	
	return saveslist;
end


local function grab_shaderconf(basename)
	local vdef, vcond = parse_shader("shaders/fullscreen/" .. basename .. ".vShader");
	local fdef, fcond = parse_shader("shaders/fullscreen/" .. basename .. ".fShader");
	
	local resdef = {};
	local rescond = {};
	
-- remap the tables into hash/LUT, doesn't separate namespaces in v/f shaders 
	for ind, val in ipairs( vdef ) do resdef[val] = true; end
	for ind, val in ipairs( fdef ) do resdef[val] = true; end
	for ind, val in ipairs( vcond ) do rescond[val] = true; end
	for ind, val in ipairs( fcond ) do rescond[val] = true; end

	return resdef, rescond;
end

-- glob shaders/fullscreen/*
-- for each unique basename, add to the menulist.
-- upon selection, load it into the "fullscreen" slot and reset the relevant uniforms
local function build_shadermenu()
	local reslbls = {};
	local resptrs = {};
	local shaderlist = {};
	local vreslist = glob_resource("shaders/fullscreen/*.vShader", 2);
	local freslist = glob_resource("shaders/fullscreen/*.fShader", 2);

-- make sure both exist, add vertex to list, then add to real list if fragment
-- exist as well
	for i = 1, #vreslist do 
		local basename = string.sub(vreslist[i], 1, -9);
		vreslist[basename] = true; 
	end
	
	for i = 1, #freslist do
		local basename = string.sub(freslist[i], 1, -9);
		if (vreslist[basename]) then 
			shaderlist[basename] = true;
		end
	end
	
	for key, val in pairs(shaderlist) do
		resptrs[ key ] = select_shaderfun;
		table.insert(reslbls, key);
	end

	return reslbls, resptrs, resstyles;
end

local function load_savestate(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"]();
	internal_statectl(label, false);
end

local function save_savestate(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"]();
	internal_statectl(label, true);
end

local function build_savemenu()
	local reslbls = {};
	local resptrs = {};
	local saveslist = get_saveslist( current_game() );
	local highind = 0;
	
	for key, val in pairs(saveslist) do
		table.insert(reslbls, val);
		resptrs[ val ] = save_savestate;
		local num = tonumber( val );
		if (num and num > highind) then highind = num; end
	end

	table.insert(reslbls, "(New)");
	table.insert(reslbls, "(Create)");

	resptrs["(Create)"] = function(label, store)
	local resstr = nil;
	local keymap = {  
		"A", "B", "C", "D", "E", "F", "G", "1", "2", "3", "\n",
		"H", "I", "J", "K", "L", "M", "N", "4", "5", "6", "\n",
		"O", "P", "Q", "R", "S", "T", "U", "7", "8", "9", "\n",
		"V", "W", "X", "Y", "Z", "_", "0" };
		
	local osdsavekbd = osdkbd_create( keymap );
	osdsavekbd:show();
		
-- do this here so we have access to the namespace where osdsavekbd exists
		gridle_input = function(iotbl)
			if (iotbl.active) then
				local restbl = keyconfig:match(iotbl);
				if (restbl) then
					for ind,val in pairs(restbl) do

-- go back to menu without doing anything
						if (val == "MENU_ESCAPE") then
							play_audio(soundmap["OSDKBD_HIDE"]);
							settings.iodispatch["MENU_ESCAPE"]();
							osdsavekbd:destroy();
							osdsavekbd = nil;
							gridle_input = gridle_dispatchinput;

-- input character or select an action (
						elseif (val == "MENU_SELECT" or val == "MENU_UP" or val == "MENU_LEFT" or 
							val == "MENU_RIGHT" or val == "MENU_DOWN") then
							resstr = osdsavekbd:input(val);
							play_audio(val == "MENU_SELECT" and soundmap["OSDKBD_SELECT"] or soundmap["OSDKBD_MOVE"]);

-- also allow direct keyboard input
						elseif (iotbl.translated) then
							resstr = osdsavekbd:input_key(iotbl);
					end
					end
				end

-- input/input_key returns the filterstring when finished
				if (resstr) then
					osdsavekbd:destroy();
					osdsavekbd = nil;
					gridle_input = gridle_dispatchinput;
					internal_statectl(resstr, true);
					spawn_warning("state saved as (" .. resstr .. ")");
					settings.iodispatch["MENU_ESCAPE"]();
					settings.iodispatch["MENU_ESCAPE"]();
				end
				
			end
		end
-- remap input to a temporary function that just maps to osdkbd until ready,
-- then use that to save if finished
	end
	
-- just grab the last num found, increment by one and use as prefix
	resptrs["(New)"] = function(label, store)
		settings.iodispatch["MENU_ESCAPE"]();
		settings.iodispatch["MENU_ESCAPE"]();
		spawn_warning("state saved as (" .. tostring( highind + 1) .. ")");
		internal_statectl(highind + 1, true);
	end
	
	return reslbls, resptrs, {};
end

local function build_loadmenu()
	local reslbls = {};
	local resptrs = {};
	local saveslist = get_saveslist( current_game() );

	for key, val in pairs(saveslist) do
		table.insert(reslbls, val);
		resptrs[ val ] = load_savestate;
	end
	
	return reslbls, resptrs, {};
end

local function toggle_shadersetting(label, save)
	if (settings.shader_opts[label]) then
		settings.shader_opts[label] = nil;
		current_menu.formats[ label ] = nil;
	else
		current_menu.formats[ label ] = "\\#ff0000";
		settings.shader_opts[label] = true;
	end
	
	current_menu:move_cursor(0, 0, true);
end

local function add_gamelbls( lbltbl, ptrtbl )
	local cg = current_game();
	local captbl = cg.capabilities;
	
	if not (captbl.snapshot or captbl.reset) then
			return false;
	end

if (captbl.snapshot) then
		if ( (# get_saveslist( cg )) > 0 ) then
			table.insert(lbltbl, "Load State...");
			ptrtbl[ "Load State..." ] = function(label, store)
				local lbls, ptrs, fmt = build_loadmenu();
				menu_spawnmenu( lbls, ptrs, fmt );
			end
		
		end
		
		table.insert(lbltbl, "Save State...");
		ptrtbl[ "Save State..." ] = function(label, store)
			local lbls, ptrs, fmt = build_savemenu();
			menu_spawnmenu( lbls, ptrs, fmt );
		end
	end
	
	if ( captbl.reset ) then
		table.insert(lbltbl, "Reset Game");
			ptrtbl["Reset Game"] = function(label, store)
				valcbs = {};
				valcbs["YES"] = function() reset_target(internal_vid); settings.iodispatch["MENU_ESCAPE"](); end
				valcbs["NO"]  = function() settings.iodispatch["MENU_ESCAPE"](); end
				dialog_option("Resetting emulation, OK?", {"YES", "NO"}, nil, true, valcbs);
			end
		end
	
	return true;
end	

function gridlemenu_internal(target_vid)
-- copy the old dispatch table, and keep a reference to the previous input handler
-- replace it with the one used for these menus (check iodispatch for MENU_ESCAPE for the handover)
	griddispatch = settings.iodispatch;
	settings.iodispatch = {};
	gridle_oldinput = gridle_input;
	gridle_input = gridle_dispatchinput;
	
	gridlemenu_destvid = target_vid;

	settings.iodispatch["MENU_SELECT"] = function(iotbl) 
		selectlbl = current_menu:select()
		if (current_menu.ptrs[selectlbl]) then
			current_menu.ptrs[selectlbl](selectlbl, false);
		end
	end

	settings.iodispatch["CONTEXT"] = function(iotbl)
		selectlbl = current_menu:select()
		
		if (settings.inshader) then
			local def, cond = grab_shaderconf(selectlbl);
			local labels = {};
			local ptrs   = {};
			local fmts   = {};

			if (settings.shader_opts) then 
				def = settings.shader_opts; 
			end
			
			for key, val in pairs(cond) do
				table.insert(labels, key);
				ptrs[ key ] = toggle_shadersetting;
				if (def [ key ] ) then
					fmts[ key ] = "\\#ff0000";
				end
			end

			if (#labels > 0) then
				settings.shader_opts = def;
				menu_spawnmenu(labels, ptrs, fmts);
			end
			
		end
	end
	
	settings.iodispatch["FLAG_FAVORITE"] = function(iotbl)
			selectlbl = current_menu:select();
			if (current_menu.ptrs[selectlbl]) then
				current_menu.ptrs[selectlbl](selectlbl, true);
			end
		end	
	
	settings.iodispatch["MENU_UP"] = function(iotbl)
		play_audio(soundmap["MENUCURSOR_MOVE"]);
		current_menu:move_cursor(-1, true);
	end

	settings.iodispatch["MENU_DOWN"] = function(iotbl)
		play_audio(soundmap["MENUCURSOR_MOVE"]);
		current_menu:move_cursor(1, true); 
	end

	settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();
		settings.inshader = false;
		
		if (current_menu.parent ~= nil) then
			if (silent == nil or silent == false) then
					play_audio(soundmap["SUBMENU_FADE"]);
			end
			
			current_menu = current_menu.parent;
		else
			if (silent == nil or silent == false) then
				play_audio(soundmap["MENU_FADE"]);
			end
			
			current_menu = nil;
			settings.iodispatch = griddispatch;
			gridle_input = gridle_oldinput;
			resume_target(internal_vid);
		end
	end
	settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];

	local menulbls = {};
	local ptrs = {};
	local gameopts = add_gamelbls(menulbls, ptrs);

	if (#menulbls > 0) then
		table.insert(menulbls, "---------   " );
	end

	table.insert(menulbls, "Shaders...");
	table.insert(menulbls, "Scaling...");
	table.insert(menulbls, "Input...");
	table.insert(menulbls, "Audio Gain...");
	table.insert(menulbls,	"Cocktail Modes...");
	
	current_menu = listview_create(menulbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;

	current_menu.ptrs["Shaders..."] = function() 
	local def = {};
		def[ settings.fullscreenshader ] = "\\#00ffff";
		if (get_key("defaultshader")) then
			def[ get_key("defaultshader") ] = "\\#00ff00";
		end
	
		local listl, listp = build_shadermenu();
		settings.inshader = true;
		menu_spawnmenu( listl, listp, def ); 
	end
	
	current_menu.ptrs["Scaling..."] = function()
		local def = {};
		def[ settings.scalemode ] = "\\#00ffff";
		if (get_key("scalemode")) then
			def[ get_key("scalemode") ] = "\\#00ff00";
		end
		
		menu_spawnmenu( scalemodelist, scalemodeptrs, def );
	end
	
	current_menu.ptrs["Input..."] = function()
		local def = {};
		def[ settings.internal_input ] = "\\#00ffff";
		if (get_key("internal_input")) then
			def[ get_key("internal_input") ] = "\\#00ff00";
		end
		
		menu_spawnmenu( inputmodelist, inputmodeptrs, def );
	end
	
	current_menu.ptrs["Audio Gain..."] = function()
		local def = {};
		def[ tostring(settings.internal_again) ] = "\\#00ffff";
		if (get_key("internal_again")) then
			def[ get_key("internal_again") ] = "\\#00ff00";
		end
		
		menu_spawnmenu( audiogainlist, audiogainptrs, def );
	end
	
	current_menu.ptrs["Cocktail Modes..."] = function()
		local def = {};
		def[ tostring(settings.cocktail_mode) ] = "\\#00ffff";
		if (get_key("cocktail_mode")) then
			def[ get_key("cocktail_mode") ] = "\\#00ff00";
		end
		
		menu_spawnmenu( cocktaillist, cocktailptrs, def);
	end
	
	current_menu:show();
	suspend_target(internal_vid);
	play_audio(soundmap["MENU_TOGGLE"]);
	move_image(current_menu.anchor, 100, 120, settings.fadedelay);
end