-- just a copy of gridle menus with the stuff specific for internal launch / fullscreen
local scalemodelist = {
	"Keep Aspect",
	"Stretch",
	"Rotate CW",
	"Rotate CCW"
};

local scalemodeptrs = {};
local function scalemodechg(label, save)
	settings.scalemode = label;
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (save) then
		store_key("internal_scalemode", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	gridlemenu_resize_fullscreen(gridlemenu_destvid);
end

scalemodeptrs["Keep Aspect"] = scalemodechg;
scalemodeptrs["Stretch"] = scalemodechg;
scalemodeptrs["Rotate CW"] = scalemodechg;
scalemodeptrs["Rotate CCW"] = scalemodechg;

local inputmodelist = {
-- revert all manipulation to default settings
	"Normal",
-- help to compensate for when we rotate to scale, look for PLAYERn_UP/DOWN/LEFT/RIGHT and replace
	"Flip X/Y"
};

local inputmodeptrs = {};
inputmodeptrs["Normal"] = function(label, save)
	settings.internal_input = "Normal";
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);

	if (save) then
			play_audio(soundmap["MENU_FAVORITE"]);
			store_key("internal_input", "Normal");
	else
			play_audio(soundmap["MENU_SELECT"]);
	end
	
	settings.flipinputaxis = false;
end

inputmodeptrs["Flip X/Y"] = function(label, save)
	settings.internal_input = "Flip X/Y";
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);

	if (save) then
		play_audio(soundmap["MENU_FAVORITE"]);
		store_key("internal_input", "Flip X/Y");
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	settings.flipinputaxis = not settings.flipinputaxis; 
end

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

-- make sure source is centered and add black bars to hide the background if needed
-- decent place to add bezel- support
local function resize_reposition(source)
	local props = image_surface_properties(source);
	local dw = VRESW - props.width;
	local dh = VRESH - props.height;
	move_image(source, dw * 0.5, dh * 0.5);
end

local function similar_aspect(sourcew, sourceh)
	return (VRESW / VRESH > 1.0 and sourcew / sourceh > 1.0) or 
		(VRESW / VRESH < 1.0 and sourcew / sourceh < 1.0);
end

-- whenever a target resizes internally shaders might need to be updated with new values,
-- furthermore, the user might want to change scaling etc. in-game
function gridlemenu_resize_fullscreen(source)
	local props = image_surface_initial_properties(source);
	
-- always scale to source dominant axis 
	if (settings.scalemode == "Keep Aspect") then
		rotate_image(source, 0);
		if (props.width / props.height > 1.0) then
			resize_image(source, VRESW, 0);
		else
			resize_image(source, 0, VRESH);
		end

		resize_reposition(source);

-- just stretch to fill screen, no reposition etc. needed
	elseif (settings.scalemode == "Stretch") then 
		resize_image(source, VRESW, VRESH);
		rotate_image(source, 0);
		move_image(source, 0, 0);

-- if aspect ratios mismatch, rotate image and flip dominant axis 
	elseif (settings.scalemode == "Rotate CW" or settings.scalemode == "Rotate CCW") then
		local angdeg = 90;
		if (settings.scalemode == "Rotate CCW") then angdeg = -90; end
		
-- no mismatch? then it's the same as before, resize to dominant axis
		if ( similar_aspect(props.width, props.height) ) then 
			if (props.width / props.height > 1.0) then
				resize_image(source, VRESW, 0);
			else
				resize_image(source, 0, VRESH);
			end
		else
			rotate_image(source, angdeg);
			
			if (props.width / props.height > 1.0) then
				resize_image(source, 0, VRESW);
			else
				resize_image(source, VRESH, 0);
			end
		end

		resize_reposition(source);
	else
		warning("unknown scalemode specified: " .. settings.scalemode .. "\n");
	end
	
	local sprops = image_storage_properties(source);
	local dprops = image_surface_initial_properties(source);
	
	if (fullscreen_shader) then
		shader_uniform(fullscreen_shader, "rubyInputSize", "ff", PERSIST, sprops.width, sprops.height); -- need to reflect actual texel size
		shader_uniform(fullscreen_shader, "rubyTextureSize", "ff", PERSIST, dprops.width, dprops.height); -- since target is allowed to resize at more or less anytime, we need to update this
		shader_uniform(fullscreen_shader, "rubyOutputSize", "ff", PERSIST, VRESW, VRESH);
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
	
-- insert into 'fullscreen' slot
	fullscreen_shader = load_shader(vsh, fsh, "fullscreen");

-- this might be used from detail-view as well so don't assume we know what to update
	if (internal_vid ~= nil) then
		-- force the shader unto the current vid
		gridlemenu_resize_fullscreen(internal_vid);
		image_shader(internal_vid, fullscreen_shader);
	end
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

	for i = 1, #vreslist do 
		local basename = string.sub(vreslist[i], 1, -9);
		shaderlist[basename] = tue; 
	end
	
	for i = 1, #freslist do
		local basename = string.sub(vreslist[i], 1, -9);
		if (shaderlist[basename] == nil) then 
			shaderlist[basename] = true;
		end
	end

	for key, val in pairs(shaderlist) do
		resptrs[ key ] = function(lbl, store) 
			settings.iodispatch["MENU_ESCAPE"](); 
			gridlemenu_loadshader(lbl);
			if (store) then
				store_key("defaultshader", lbl);
			end
	end

		table.insert(reslbls, key);
	end
	
	return reslbls, resptrs, resstyles;
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
		end
	end
	settings.iodispatch["MENU_RIGHT"] = settings.iodispatch["MENU_SELECT"];
	settings.iodispatch["MENU_LEFT"]  = settings.iodispatch["MENU_ESCAPE"];

-- Decent entrypoint to add support for more esoteric functions (snapshot recording, highscore tracking,
-- Savestate management, ...)
	local menulbls = {
		"Shaders...",
		"Scaling...",
		"Input...",
		"Audio Gain..."
	};

	current_menu = listview_create(menulbls, #menulbls * 24, VRESW / 3);
	current_menu.ptrs = {};
	current_menu.parent = nil;
	current_menu.ptrs["Shaders..."] = function() 
		local def = {};
		def[ settings.fullscreenshader ] = "\\#00ffff";
		if (get_key("fullscreen_shader")) then
				def[ get_key("fullscreen_shader") ] = "\\#00ff00";
		end
	
		local listl, listp = build_shadermenu();
		menu_spawnmenu( listl, listp, def ); 
	end
	
	current_menu.ptrs["Scaling..."] = function()
		local def = {};
		def[ settings.scalemode ] = "\\#00ffff";
		if (get_key("internal_scalemode")) then
			def[ get_key("internal_scalemode") ] = "\\#00ff00";
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
	
	play_audio(soundmap["MENU_TOGGLE"]);
	move_image(current_menu:anchor_vid(), 100, 120, settings.fadedelay);
end