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

	gridlemenu_rebuilddisplay();
end

for ind, val in ipairs(scalemodelist) do scalemodeptrs[val] = scalemodechg; end

local inputmodelist = {
-- revert all manipulation to default settings
	"Normal",
	"Rotate CW",
	"Rotate CCW",
	"Invert Axis (analog)",
	"Mirror Axis (analog)",
	"Filter Opposing"
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

inputmodeptrs["Filter Opposing"] = function(label, save)
	settings.filter_opposing = not settings.filter_opposing;

	if (settings.filter_opposing) then
		current_menu.formats[ label ] = "\\#ff0000";
	else
		current_menu.formats[ label ] = nil; 
	end
	
	current_menu:move_cursor(0, 0, true);

	if (save) then
		store_key("filter_opposing", settings.filter_opposing and "1" or "0");
	end
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

local function select_shaderfun(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.fullscreenshader = label;
	settings.internal_toggles = {};
	
	gridlemenu_rebuilddisplay();
	
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

-- glob shaders/fullscreen/*
-- for each unique basename, add to the menulist.
-- upon selection, load it into the "fullscreen" slot and reset the relevant uniforms
local function build_shadermenu()
	local reslbls = {};
	local resptrs = {};
	local shaderlist = {};
	local vreslist = glob_resource("shaders/fullscreen/*.vShader", SHARED_RESOURCE);
	local freslist = glob_resource("shaders/fullscreen/*.fShader", SHARED_RESOURCE);

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

local function cocktailmodechg(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (save) then
		store_key("cocktail_mode", label);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end
	
	settings.cocktail_mode = label;
	gridlemenu_rebuilddisplay();
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

local vectormenuptrs = {};

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
	image_tracetag(imagery.cocktail_vid, "cocktail");
	image_shader(imagery.cocktail_vid, fullscreen_shader);
	
	image_mask_clear(imagery.cocktail_vid, MASK_OPACITY);
	image_mask_clear(imagery.cocktail_vid, MASK_ORIENTATION);
	resize_image(imagery.cocktail_vid, props.width, props.height);
	show_image(imagery.cocktail_vid);

	if (mode == "H-Split" or mode == "H-Split SBS") then
		if (mode == "H-Split") then 
			rotate_image(imagery.cocktail_vid, 180); 
		end
		
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
	if (status.kind == "loaded") then
		local props = image_storage_properties(source);
		resize_image(source, VRESW, VRESH);
		local x1,y1,x2,y2 = image_borderscan(source);
		image_tracetag(source, "bezel");
		
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

-- generate a special "mix shader" for multitexturing purposes,
-- where input frames is an array of weights e.g {1.0, 0.8, 0.6} 
function create_weighted_fbo( frames )
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");
	
	for i=0,#frames-1 do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i) .. ";");
	end

	table.insert(resshader, "void main(){");

	local mixl = "gl_FragColor = "
	for i=0,#frames-1 do
		table.insert(resshader, "vec4 col" .. tostring(i) .. " = texture2D(map_tu" .. tostring(i) .. ", texco);");

		local strv = tostring(frames[i+1]);
		local coll = "vec4(" .. strv .. ", " .. strv .. ", " .. strv .. ", 1.0)";
		mixl = mixl .. "col" .. tostring(i) .. " * " .. coll;
		
		if (i == #frames-1) then 
			mixl = mixl .. ";\n}\n";
		else
			mixl = mixl .. " + ";
		end
	end

	table.insert(resshader, mixl);
	return resshader; 
end

-- configure shaders for the blur / glow / bloom effect
function vector_setupblur(targetw, targeth)
	local blurshader_h = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianH.fShader", "blur_horiz", {});
	local blurshader_v = load_shader("shaders/fullscreen/default.vShader", "shaders/fullscreen/gaussianV.fShader", "blur_vert", {});
	local blurw = targetw * settings.vector_hblurscale;
	local blurh = targeth * settings.vector_vblurscale;
	
	shader_uniform(blurshader_h, "blur", "f", PERSIST, 1.0 / blurw);
	shader_uniform(blurshader_v, "blur", "f", PERSIST, 1.0 / blurh);
	shader_uniform(blurshader_h, "ampl", "f", PERSIST, settings.vector_hbias);
	shader_uniform(blurshader_v, "ampl", "f", PERSIST, settings.vector_vbias);	

	local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
	local blur_vbuf = fill_surface(targetw, targeth, 1, 1, 1, blurw, blurh);

	image_shader(blur_hbuf, blurshader_h);
	image_shader(blur_vbuf, blurshader_v);

	show_image(blur_hbuf);
	show_image(blur_vbuf);

	return blur_hbuf, blur_vbuf;
end

-- additive blend with blur
function vector_lightmode(source, targetw, targeth)
	local blur_hbuf, blur_vbuf = vector_setupblur(targetw, targeth);
	local blurw = targetw * settings.vector_hblurscale;
	local blurh = targeth * settings.vector_vblurscale;
	
-- undo / ignore everything put in place by the normal resize
	move_image(source, 0, 0);
	resize_image(source, targetw, targeth);
	show_image(source);
	
	local node = instance_image(source);
	
	resize_image(node, blurw, blurh);
	show_image(node);
	image_tracetag(node, "vector(source:clone)");

	image_tracetag(blur_hbuf, "vector(hblur)");
	image_tracetag(blur_vbuf, "vector(vblur)");
	
	define_rendertarget(blur_hbuf, {node}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	blend_image(blur_vbuf, 0.99);
	force_image_blend(blur_vbuf, BLEND_ADD);
	order_image(blur_vbuf, max_current_image_order() + 1);

	local comp_outbuf = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	image_tracetag(comp_outbuf, "vector(composite)");
	move_image(blur_vbuf, settings.vector_hblurofs, settings.vector_vblurofs);
	define_rendertarget(comp_outbuf, {blur_vbuf, source}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(comp_outbuf);
	
	return comp_outbuf;
end

--
-- additive blend with blur, base image for blur as a weighted blend of previous images
-- creates lots of little FBOs container resources that needs to be cleaned up
--
function vector_heavymode(source, targetw, targeth)
	local blur_hbuf, blur_vbuf = vector_setupblur(targetw, targeth);
	image_tracetag(blur_hbuf, "vector(hblur)");
	image_tracetag(blur_vbuf, "vector(vblur)");

	local blurw = targetw * settings.vector_hblurscale;
	local blurh = targeth * settings.vector_vblurscale;
		
	local normal = instance_image(source);
	image_mask_set(normal, MASK_FRAMESET);
	show_image(normal);
	resize_image(normal, targetw, targeth);
	image_mask_set(normal, MASK_MAPPING);

	local frames = {};
	local base = 1.0;
	
	for i=1, settings.vector_glowtrails+1 do
		frames[i] = base;
		base = base - settings.vector_trailfall;
	end
	
-- set frameset for parent to work as around robin with multitexture,
-- build a shader that blends the frames according with user-defined weights	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", create_weighted_fbo(frames) , "history_mix", {});
	print(#frames);
	image_framesetsize(source, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(source, settings.vector_trailstep);
	image_shader(source, mixshader);
	show_image(source);
	resize_image(source, blurw, blurh); -- borde inte den vara ehrm, blurw, blurh?
	move_image(source, 0, 0);
	image_mask_set(source, MASK_MAPPING);

-- generate textures to use as round-robin store, these need to math the storage size to avoid
-- a copy/scale each frame
	for i=1,settings.vector_glowtrails do
		local vid = fill_surface(targetw, targeth, 0, 0, 0, targetw, targeth);
		set_image_as_frame(source, vid, i, FRAMESET_DETACH);
	end

	rendertgt = fill_surface(blurw, blurh, 0, 0, 0, blurw, blurh);
	define_rendertarget(rendertgt, {source}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(rendertgt);
	image_tracetag(rendertgt, "vector(trailblur)");

	define_rendertarget(blur_hbuf, {rendertgt}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	define_rendertarget(blur_vbuf, {blur_hbuf}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	blend_image(blur_vbuf, 0.99);
	force_image_blend(blur_vbuf, BLEND_ADD);
	order_image(blur_vbuf, max_current_image_order() + 1);

	local comp_outbuf = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	image_tracetag(comp_outbuf, "vector(composite)");
	move_image(blur_vbuf, settings.vector_hblurofs, settings.vector_vblurofs);
	define_rendertarget(comp_outbuf, {blur_vbuf, normal}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(comp_outbuf);
	
	return comp_outbuf;
end

function undo_vectormode()
	if (valid_vid(imagery.vector_vid)) then
		image_shader(internal_vid, "DEFAULT");
		image_framesetsize(internal_vid, 0);
		image_framecyclemode(internal_vid, 0);
-- lots of things happening beneath the surface here, killing the vector vid will cascade and drop all detached images
-- that are part of the render target, EXCEPT for the initial internal vid that has its MASKED_LIVING disabled
-- this means that it gets reattached to the main pipe instead of deleted
		delete_image(imagery.vector_vid);
		imagery.vector_vid = BADID;
	end
end

local function toggle_vectormode()
-- should only happen when shutting down internal_launch with vector mode active
	image_mask_clear(internal_vid, MASK_LIVING);
	local props = image_surface_initial_properties(internal_vid);

-- activate trails or not?
	if (settings.vector_glowtrails > 0) then
		imagery.vector_vid = vector_heavymode(internal_vid, props.width, props.height);
	else
		imagery.vector_vid = vector_lightmode(internal_vid, props.width, props.height);
	end
	
	order_image(imagery.vector_vid, 1);
-- CRT toggle is done through the fullscreen_shader member
end

function gridlemenu_rebuilddisplay()
	undo_vectormode();
	
	if (settings.internal_toggles.vector) then
		toggle_vectormode();
		target_pointsize(internal_vid, settings.vector_pointsz);
		target_linewidth(internal_vid, settings.vector_linew);
		
		if (settings.internal_toggles.crt) then
			gridlemenu_loadshader("crt", imagery.vector_vid, image_surface_initial_properties(internal_vid));
		end

		gridlemenu_resize_fullscreen(imagery.vector_vid, image_surface_initial_properties(internal_vid));
		return;

	elseif (settings.internal_toggles.crt) then
		gridlemenu_loadshader("crt");

	else
		gridlemenu_loadshader(settings.fullscreenshader);
	end

	gridlemenu_resize_fullscreen(internal_vid, image_surface_initial_properties(internal_vid))
end

function gridlemenu_resize_fullscreen(source, init_props)
	print("resize");
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
	
	local props = init_props; 
	
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
	local dprops = init_props;
	
	if (fullscreen_shader) then
		shader_uniform(fullscreen_shader, "rubyInputSize", "ff", PERSIST, sprops.width, sprops.height); -- need to reflect actual texel size
		shader_uniform(fullscreen_shader, "rubyTextureSize", "ff", PERSIST, dprops.width, dprops.height); -- since target is allowed to resize at more or less anytime, we need to update this
		shader_uniform(fullscreen_shader, "rubyOutputSize", "ff", PERSIST, windw, windh);
		shader_uniform(fullscreen_shader, "rubyTexture", "i", PERSIST, 0);
	end
	
end

function gridlemenu_loadshader(basename, dstvid, dstprops)
	local vsh = nil;
	local fsh = nil;
	if (dstvid == nil) then dstvid = internal_vid; end
	if (dstprops == nil) then dstprops = image_surface_initial_properties(dstvid); end
	
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

	image_shader(dstvid, fullscreen_shader);
end

local function get_saveslist(gametbl)
-- check for existing snapshots (ignore auto and quicksave)
	local saveslist = {};
	local saves = glob_resource("savestates/" .. gametbl.target .. "_" .. gametbl.setname .. "_*", SHARED_RESOURCE)
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

					if (string.len(resstr) > 0) then
						internal_statectl(resstr, true);
						spawn_warning("state saved as (" .. resstr .. ")");
					end
					
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
	
-- fixme; generate menus for all the different kinds of "frame-stepping" options we'd like to have
-- (auto, draw every n frames, rewind n frames, ...)
	
-- fixme; generate menus for each input port with (gamepad, mouse, keyboard, ...) sort of options
-- in order to plug into proper libretro devices .. 
--	if ( captbl.ports and captbl.ports > 0) then
--		local numslots = captbl.ports > keyconfig.table.player_count and keyconfig.table.player_count or captbl.ports;
--		if (numslots > 0) then
--			table.insert(lbltbl, "Input Ports");
--			for i=1,numslots do
--				local key = "Input " .. tostring(i);
--				table.insert(lbltbl, key);
--				ptrtbl[key] = "
--			end
--		end
--	end
	
	if ( captbl.reset ) then
		table.insert(lbltbl, "Reset Game");
			ptrtbl["Reset Game"] = function(label, store)
				valcbs = {};
				valcbs["YES"] = function() 
					reset_target(internal_vid); 
					settings.iodispatch["MENU_ESCAPE"]();
				end
				
				valcbs["NO"]  = function()
					settings.iodispatch["MENU_ESCAPE"](); 
				end
				
				dialog_option("Resetting emulation, OK?", {"YES", "NO"}, nil, true, valcbs);
			end
		end
	
	return true;
end	

function screenshot()
	local tbl = current_game();
	local lblbase = "screenshots/" .. tbl.target .. "_" .. tbl.setname;
	local ofs = 1;

-- only add sequence number if we already have a screenshot for the game
	if (resource( lblbase .. ".png" ) ) then
		while resource(lblbase .. "_" .. tostring(ofs) .. ".png") do
			ofs = ofs + 1;
		end
		save_screenshot(lblbase .. "_" .. tostring(ofs) .. ".png");
	else
		save_screenshot(lblbase .. ".png");
	end
end

displaymodeptrs = {};
displaymodeptrs["Custom Shaders..."] = function() 
	local def = {};
	def[ settings.fullscreenshader ] = "\\#00ffff";
	if (get_key("defaultshader")) then
		def[ get_key("defaultshader") ] = "\\#00ff00";
	end
	
	local listl, listp = build_shadermenu();
	settings.context_menu = "custom shaders";
	menu_spawnmenu( listl, listp, def ); 
end
	
-- Don't implement save / favorite for these ones,
-- want fail-safe as default, and the others mess too much with GPU for that
displaymodelist = {"NTSC", "Upscale", "CRT", "Vector", "Overlay", "Custom Shaders..."};

-- the vector display modes take a lot of options and the set of shaders
-- used need to be set up and configured in a very specific order,
-- some options also need to be propagated to the launched target
displaymodeptrs["Vector"] = function(label, save)
	settings.internal_toggles.vector = not settings.internal_toggles.vector;
	if (settings.internal_toggles.vector) then
		current_menu.formats[ "Vector" ] = "\\#ff0000";
	else
		current_menu.formats[ "Vector" ] = nil;
	end
	
	current_menu:move_cursor(0, 0, true);

	gridlemenu_rebuilddisplay();
	current_menu:push_to_front();
end;

-- similar to just loading the fullscreen shader,
-- but with menus for setting a lot more options
displaymodeptrs["CRT"] = function(label, save)
	settings.internal_toggles.crt = not settings.internal_toggles.crt;
	if (settings.internal_toggles.crt) then
		current_menu.formats[ "CRT" ] = "\\#ff0000";
	else
		current_menu.formats[ "CRT" ] = nil;
	end
	
	current_menu:move_cursor(0, 0, true);

	gridlemenu_rebuilddisplay();
	current_menu:push_to_front();
end;

vectormenulbls = {};
vectormenuptrs = {};

local function updatetrigger()
	gridlemenu_rebuilddisplay();
end

add_submenu(vectormenulbls, vectormenuptrs, "Line Width...", "vector_linew", gen_num_menu("vector_linew", 1, 1, 6, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Point Size...", "vector_pointsz", gen_num_menu("vector_pointsz", 1, 1, 6, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Blur Scale (X)...", "vector_hblurscale", gen_num_menu("vector_hblurscale", 0.2, 0.1, 9, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Blur Scale (Y)...", "vector_vblurscale", gen_num_menu("vector_vblurscale", 0.2, 0.1, 9, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Vertical Offset...", "vector_vblurofs", gen_num_menu("vector_vblurofs", -6, 1, 13, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Horizontal Offset...", "vector_hblurofs", gen_num_menu("vector_hblurofs", -6, 1, 13, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Vertical Bias...", "vector_vbias", gen_num_menu("vector_vbias", 0.6, 0.1, 9, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Horizontal Bias...", "vector_hbias", gen_num_menu("vector_hbias", 0.6, 0.1, 9, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Glow Trails...", "vector_glowtrails", gen_num_menu("vector_glowtrails", 0, 1, 6, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Trail Step...", "vector_trailstep", gen_num_menu("vector_trailstep", -1, -1, 12, updatetrigger));
add_submenu(vectormenulbls, vectormenuptrs, "Trail Falloff...", "vector_trailfall", gen_num_menu("vector_trailfall", 0.05, 0.05, 20, updatetrailtrigger));

function gridlemenu_internal(target_vid, contextlbls, settingslbls)
-- copy the old dispatch table, and keep a reference to the previous input handler
-- replace it with the one used for these menus (check iodispatch for MENU_ESCAPE for the handover)
	
	if (not (contextlbls or settingslbls)) then return; end

	local menulbls = {};
	local ptrs = {};

	if (contextlbls) then
		add_gamelbls(menulbls, ptrs);
		if (#menulbls == 0 and not settingslbls) then return; end
	end

	griddispatch = settings.iodispatch;
	settings.iodispatch = {};
	gridle_oldinput = gridle_input;
	gridle_input = gridle_dispatchinput;
	
	gridlemenu_destvid = target_vid;

	settings.iodispatch["CONTEXT"] = function(iotbl)
		selectlbl = current_menu:select()
	
		if (settings.context_menu == "custom shaders") then
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
			
		elseif (selectlbl == "CRT") then
			fmts = {};
			menu_spawnmenu(crtmenulbls, crtmenuptrs, fmts);
			
		elseif (selectlbl == "Vector") then
			fmts = {}; -- do for CRT / Overlay 
			menu_spawnmenu(vectormenulbls, vectormenuptrs, fmts);
		end
	end
	
	settings.iodispatch["MENU_ESCAPE"] = function(iotbl, restbl, silent)
		current_menu:destroy();
		settings.context_menu = nil;
		
		if (current_menu.parent ~= nil) then
			if (silent == nil or silent == false) then
					play_audio(soundmap["SUBMENU_FADE"]);
			end
			
			current_menu = current_menu.parent;
		else
			if (silent == nil or silent == false) then
				play_audio(soundmap["MENU_FADE"]);
			end
			
			resume_target(internal_vid);
			current_menu = nil;
			settings.iodispatch = griddispatch;
			gridle_input = gridle_oldinput;
		end
	end

if (#menulbls > 0 and settingslbls) then
		table.insert(menulbls, "---------   " );
	end

	if (settingslbls) then
		table.insert(menulbls, "Display Modes...");
		table.insert(menulbls, "Scaling...");
		table.insert(menulbls, "Input...");
		table.insert(menulbls, "Audio Gain...");
		table.insert(menulbls, "Cocktail Modes...");
		table.insert(menulbls, "Screenshot");
	end
	
	current_menu = listview_create(menulbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;

	current_menu.ptrs["Display Modes..."] = function()
		local def = {};
		if ( settings.internal_toggles.crt ) then 
			def[ "CRT" ] = "\\#00ffff";
		end
		
		if (settings.internal_toggles.vector ) then
			def[ "Vector" ] = "\\#00ffff";
		end
		
		settings.context_menu = "display modes";
		menu_spawnmenu(displaymodelist, displaymodeptrs, def );
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
		if (settings.filter_opposing) then
			def["Filter Opposing"]= "\\#ff0000";
		end
		
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
	
-- trickier than expected, as we don't want the game to progress and we don't want any UI elements involved */
	current_menu.ptrs["Screenshot"] = function()
		local tbl = current_game();
		
		settings.iodispatch["MENU_ESCAPE"]();
		local tmpclock = gridle_clock_pulse;
		local tmpclock_c = 22; -- listview has a fixed 20tick expire
		suspend_target( target_vid );

-- replace the current timing function with one that only ticks down and then takes a screenshot
		gridle_clock_pulse = function()
-- generate a filename that's not in use 
			if (tmpclock_c > 0) then 
				tmpclock_c = tmpclock_c - 1; 
			else
				screenshot();
				resume_target(target_vid);
				gridle_clock_pulse = tmpclock;
			end
		end
	end
	
	current_menu.ptrs["Cocktail Modes..."] = function()
		local def = {};
		def[ tostring(settings.cocktail_mode) ] = "\\#00ffff";
		if (get_key("cocktail_mode")) then
			def[ get_key("cocktail_mode") ] = "\\#00ff00";
		end
		
		menu_spawnmenu( cocktaillist, cocktailptrs, def);
	end

	gridlemenu_defaultdispatch();
	settings.context_menu = nil;
	
	current_menu:show();
	suspend_target(internal_vid);
	play_audio(soundmap["MENU_TOGGLE"]);
	move_image(current_menu.anchor, 100, 120, settings.fadedelay);
end
