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
	"Filter Opposing",
	"---",
	"Reconfigure Keys"
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
		current_menu.formats[ label ] = settings.colourtable.notice_fontstr;
	else
		current_menu.formats[ label ] = nil; 
	end
	
	current_menu:move_cursor(0, 0, true);

	if (save) then
		store_key("filter_opposing", settings.filter_opposing and "1" or "0");
	end
end

inputmodeptrs["Reconfigure Keys"] = function()
	keyconfig:reconfigure_players();
	kbd_repeat(0);

	gridle_input = function(iotbl) -- keyconfig io function hook
		if (keyconfig:input(iotbl) == true) then
			gridle_input = gridle_dispatchinput;
			kbd_repeat(settings.repeatrate);
		end
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

local function setup_bezel(source)
	if (image_loaded(source)) then
		local props = image_storage_properties(source);
		resize_image(source, VRESW, VRESH);
		local x1,y1,x2,y2 = image_borderscan(source);
		
		x1 = (x1 / props.width) * VRESW;
		x2 = (x2 / props.width) * VRESW;
		y1 = (y1 / props.height) * VRESH;
		y2 = (y2 / props.height) * VRESH;
		
		local dstvid = valid_vid(imagery.display_vid) and imagery.display_vid or internal_vid;
	
		resize_image(dstvid, x2 - x1, y2 - y1);
		move_image(dstvid, x1, y1);
		order_image(source, image_surface_properties(dstvid).order);
		force_image_blend(source, BLEND_NORMAL);
		show_image(source);
	else
		hide_image(source);
	end
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

local function merge_compositebuffer(sourcevid, blurvid, targetw, targeth, blurw, burh)
	local rtgts = {};

	if (valid_vid(blurvid)) then
		order_image(blurvid, 2);
		force_image_blend(blurvid, BLEND_ADD);
		table.insert(rtgts, blurvid);
	end
	
	order_image(sourcevid, 3);
	force_image_blend(sourcevid, BLEND_ADD);
	
	table.insert(rtgts, sourcevid);
		
	if (settings.internal_toggles.backdrop and valid_vid(imagery.backdrop)) then
		local backdrop = instance_image(imagery.backdrop);
		image_mask_clear(backdrop, MASK_OPACITY);
		order_image(backdrop, 1);
		blend_image(backdrop, 0.95);
		resize_image(backdrop, targetw, targeth);
		table.insert(rtgts, backdrop);
		force_image_blend(sourcevid, BLEND_ADD);
	end
	
	if (settings.internal_toggles.overlay and valid_vid(imagery.overlay)) then
		local overlay = instance_image(imagery.overlay);
		image_mask_clear(overlay, MASK_OPACITY);
		resize_image(overlay, targetw, targeth);
		show_image(overlay);
		order_image(overlay, 4);
		force_image_blend(overlay, BLEND_MULTIPLY);
		table.insert(rtgts, overlay);
	end
	
	return rtgts;
end

-- "slightly" easier than SMAA ;-)
function display_fxaa(source, targetw, targeth)
	local fxaa_shader = load_shader("shaders/fullscreen/default.vShader", "display/fxaa.fShader", "fxaa", {});
	local node        = instance_image(source);
	local fxaa_outp   = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);

	local props = image_surface_properties(source);

	shader_uniform(fxaa_shader, "pixel_size", "ff", PERSIST, 1.0 / targetw, 1.0 / targeth);
	hide_image(source);
	image_shader(node, fxaa_shader);
	resize_image(node, targetw, targeth);
	image_mask_clear(node, MASK_POSITION);
	image_mask_clear(node, MASK_OPACITY);
	show_image(node);

	define_rendertarget(fxaa_outp, {node}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(fxaa_outp);
	order_image(fxaa_outp, 3);

	return fxaa_outp;
end

function display_smaa(source, targetw, targeth)
-- start with edge detection
	local edge_shader = load_shader("display/smaa_edge.vShader", "display/smaa_edge.fShader", "smaa_edge", {});
	local node        = instance_image(source);
	local edge_outp   = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	shader_uniform(edge_shader, "pixel_size", "ff", PERSIST, 1.0 / targetw, 1.0 / targeth);
	hide_image(source);
	
	image_shader(node, edge_shader);
	resize_image(node, targetw, targeth);
	image_mask_clear(node, MASK_POSITION);
	image_mask_clear(node, MASK_OPACITY);
	show_image(node);
	
	define_rendertarget(edge_outp, {node}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(edge_outp);

-- return edge_outp; here to verify the edge detection step
-- the complicated part, generate the blend map by using the edge detection as input,
-- along with two LUTs (area / search)
	local blend_shader = load_shader("display/smaa_blend.vShader", "display/smaa_blend.fShader", "smaa_blend", {});
	shader_uniform(blend_shader, "pixel_size", "ff", PERSIST, 1.0 / targetw, 1.0 / targeth);
	local blend_outp = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	local blend_comb = fill_surface(targetw, targeth, 1, 1, 1, 2, 2);

	image_framesetsize(blend_comb, 3, FRAMESET_MULTITEXTURE);
	set_image_as_frame(blend_comb, edge_outp, 0, FRAMESET_DETACH);
	
	area   = load_image("display/smaa_area.png");
	search = load_image("display/smaa_search.png");
	
	set_image_as_frame(blend_comb, area, 1, FRAMESET_DETACH);
	set_image_as_frame(blend_comb, search, 2, FRAMESET_DETACH);
	image_shader(blend_comb, blend_shader);
	show_image(blend_outp);
	show_image(blend_comb);
	
	define_rendertarget(blend_outp, {blend_comb}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- last step is instancing source again, combine with blend_outp and the neighbor shader
-- unfinished
	return blend_outp;
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
	
	local cbuf = merge_compositebuffer(source, blur_vbuf, targetw, targeth, blurw, blurh);
	define_rendertarget(comp_outbuf, cbuf, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
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

-- generate a list of weights as input to code-generator for mix- shader 
	local ul = settings.vector_glowtrails + 1;

	if (settings.vector_trailfall == 0) then
-- linear
		local step = 1.0 / ul;
		for i=1, ul do
			frames[i] = (ul - (i + 1)) * step;
		end
	else
-- exponential
		for i=1, ul do
			frames[i] = 1.0 / math.exp( settings.vector_trailfall * ((i-1) / ul) );
		end
	end

-- set frameset for parent to work as around robin with multitexture,
-- build a shader that blends the frames according with user-defined weights	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", create_weighted_fbo(frames) , "history_mix", {});
	image_framesetsize(source, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(source, settings.vector_trailstep);
	image_shader(source, mixshader);
	show_image(source);
	resize_image(source, blurw, blurh); -- borde inte den vara ehrm, blurw, blurh?
	move_image(source, 0, 0);
	image_mask_set(source, MASK_MAPPING);

-- generate textures to use as round-robin store, these need to math the storage size to avoid
-- a copy/scale each frame
	local props = image_surface_initial_properties(internal_vid);
	for i=1,settings.vector_glowtrails do
		local vid = fill_surface(targetw, targeth, 0, 0, 0, props.width, props.height);
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
	
	local cbuf = merge_compositebuffer(normal, blur_vbuf, targetw, targeth, blurw, blurh);
	define_rendertarget(comp_outbuf, cbuf, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(comp_outbuf);
	
	return comp_outbuf;
end

function gridlemenu_tofront(cur)
	if (cur) then
		if (cur.parent) then
			gridlemenu_tofront(cur.parent);
		end
		
		cur:push_to_front();
	end
end

function undo_displaymodes()
	image_shader(internal_vid, "DEFAULT");

	image_framesetsize(internal_vid, 0);
	image_framecyclemode(internal_vid, 0);
		
-- lots of things happening beneath the surface here, killing the vector vid will cascade and drop all detached images
-- that are part of the render target, EXCEPT for the initial internal vid that has its MASKED_LIVING disabled
-- this means that it gets reattached to the main pipe instead of deleted
	if (valid_vid(imagery.display_vid)) then
		delete_image(imagery.display_vid);
	end
	
	for ind,val in ipairs(imagery.temporary) do

		if (valid_vid(val)) then
			delete_image(val);
		end

	end

	imagery.temporary = {};
	imagery.display_vid = BADID;
end

local function toggle_vectormode(sourcevid, windw, windh)
	if (sourcevid == internal_vid) then
		image_mask_clear(internal_vid, MASK_LIVING);
		image_texfilter(internal_vid, FILTER_NONE);
	end
	
-- activate trails or not?
	if (settings.vector_glowtrails > 0) then
		imagery.display_vid = vector_heavymode(sourcevid, windw, windh);
	else
		imagery.display_vid = vector_lightmode(sourcevid, windw, windh);
	end
	
	order_image(imagery.display_vid, 1);
-- CRT toggle is done through the fullscreen_shader member
end

local function toggle_crtmode(vid, props, windw, windh)
	local shaderopts = {};
-- CURVATURE, OVERSAMPLE, LINEAR_PROCESSING, USEGAUSSIAN
	if (settings.crt_curvature) then shaderopts["CURVATURE"] = true; end
	if (settings.crt_gaussian)  then shaderopts["USEGAUSSIAN"] = true; end
	if (settings.crt_linearproc) then shaderopts["LINEAR_PROCESSING"] = true; end
	if (settings.crt_oversample) then shaderopts["OVERSAMPLE"] = true; end
	
	local shader = load_shader("display/crt.vShader", "display/crt.fShader", "crt", shaderopts); 
	local sprops = image_storage_properties(internal_vid);
	settings.fullscreen_shader = shader;

	shader_uniform(shader, "rubyInputSize", "ff", PERSIST, sprops.width, sprops.height);
	shader_uniform(shader, "rubyOutputSize", "ff", PERSIST, windw, windh); 
	shader_uniform(shader, "rubyTextureSize", "ff", PERSIST, props.width, props.height);
	shader_uniform(shader, "rubyTexture", "i", PERSIST, 0);
	shader_uniform(shader, "CRTgamma", "f", PERSIST, settings.crt_gamma);
	shader_uniform(shader, "overscan", "ff", PERSIST, settings.crt_hoverscan, settings.crt_voverscan);
	shader_uniform(shader, "monitorgamma", "f", PERSIST, settings.crt_mongamma);
	shader_uniform(shader, "aspect", "ff", PERSIST, settings.crt_haspect, settings.crt_vaspect);
	shader_uniform(shader, "distance", "f", PERSIST, settings.crt_distance);
	shader_uniform(shader, "curv_radius", "f", PERSIST, settings.crt_curvrad);
	shader_uniform(shader, "tilt_angle", "ff", PERSIST, settings.crt_tilth, settings.crt_tiltv);
	shader_uniform(shader, "cornersize", "f", PERSIST, settings.crt_cornersz);
	shader_uniform(shader, "cornersmooth", "f", PERSIST, settings.crt_cornersmooth);

	image_shader(vid, shader);
end

local filterlut = {None = FILTER_NONE, 
		Linear   = FILTER_LINEAR,
		Bilinear = FILTER_BILINEAR};

local function update_filter(vid, filtermode)
	local modeval = filterlut[filtermode];
	if (modeval) then
		image_texfilter(vid, modeval);
	end
end

function push_ntsc()
	target_postfilter_args(internal_vid, 1, settings.ntsc_hue, settings.ntsc_saturation, settings.ntsc_contrast);
	target_postfilter_args(internal_vid, 2, settings.ntsc_brightness, settings.ntsc_gamma, settings.ntsc_sharpness);
	target_postfilter_args(internal_vid, 3, settings.ntsc_resolution, settings.ntsc_artifacts, settings.ntsc_bleed);
	target_postfilter_args(internal_vid, 4, settings.ntsc_fringing);

	target_postfilter(internal_vid, settings.internal_toggles.ntsc and POSTFILTER_NTSC or POSTFILTER_OFF);

-- for the argument changes to be reflected, we need the video rolling
	resume_target(internal_vid);
end

function gridlemenu_rebuilddisplay()
	undo_displaymodes();
	update_filter(internal_vid, settings.imagefilter);
	
	local props  = image_surface_initial_properties(internal_vid);
	local dstvid = internal_vid;
	
-- need to do this twice in order to cover all the basis (upscaler, ...)
	local windw, windh = gridlemenu_resize_fullscreen(dstvid, props);

-- begin by antialias the source
	if (settings.internal_toggles.antialias) then
		dstvid = display_fxaa(dstvid, windw, windh); 
		imagery.display_vid = dstvid;
	end
	
-- enable all display options
	if (settings.internal_toggles.vector) then
		target_pointsize(dstvid, settings.vector_pointsz);
		target_linewidth(dstvid, settings.vector_linew);
		
		local dstw, dsth;
		if (props.width > VRESW or props.height > VRESH) then
			dstw = windw;
			dsth = windh;
		else
			dstw = props.width;
			dsth = props.height;
		end
			
		toggle_vectormode(dstvid, dstw, dsth);
		dstvid = imagery.display_vid;
	
	elseif ( (settings.internal_toggles.overlay and valid_vid(imagery.overlay)) or (settings.internal_toggles.backdrop and valid_vid(imagery.backdrop)) ) then
		image_mask_clear(internal_vid, MASK_LIVING);
		
		dstbuf = fill_surface(windw, windh, 1, 1, 1, windw, windh);
		
		image_tracetag(dstbuf, "overlay_backdrop");
	
		local cbuf = merge_compositebuffer(dstvid, BADID, windw, windh, 0, 0);
		define_rendertarget(dstbuf, cbuf, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

		imagery.display_vid = dstbuf;
		dstvid = dstbuf;
		blend_image(dstbuf, 1);
	else

		fullscreen_shader = gridlemenu_loadshader(settings.fullscreenshader);
	end
	
-- redo so that instancing etc. match
	order_image(dstvid, max_current_image_order() + 1);
	show_image(dstvid);
	
-- redo resize so it covers possible FBO rendertargets
	local windw, windh = gridlemenu_resize_fullscreen(dstvid, props)
	update_filter(dstvid, settings.imagefilter);
	
-- crt is always last
	if (settings.internal_toggles.crt) then

-- special case with cocktail modes
		toggle_crtmode(dstvid, props, windw, windh);
		if ( valid_vid(imagery.cocktail_vid) ) then
			image_shader(imagery.cocktail_vid, settings.fullscreen_shader);
		end

	end

	if (settings.internal_toggles.ntsc) then
		push_ntsc();
	end
	
-- all the above changes may have reordered the menu 
	gridlemenu_tofront(current_menu);
end

function gridlemenu_resize_fullscreen(source, init_props)
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
	if (valid_vid(imagery.bezel)) then hide_image(imagery.bezel); end
	
	if (scalemode == "Bezel") then
		if (valid_vid(imagery.bezel)) then
			setup_bezel(imagery.bezel);
		end
		cocktailmode = "Disabled";
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
	
	return windw, windh;
end

function gridlemenu_loadshader(basename, dstvid, dstprops, key)
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
	
	local resshdr = load_shader(vsh, fsh, "fullscreen", settings.shader_opts);
	image_shader(dstvid, resshdr);
	
	return resshdr;
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
			complete, resstr = osdkbd_inputfun(iotbl, osdsavekbd);
			
			if (complete) then
				osdsavekbd:destroy();
				osdsavekbd = nil;
				gridle_input = gridle_dispatchinput;

				if (resstr ~= nil and string.len(resstr) > 0) then
					internal_statectl(resstr, true);
					spawn_warning("state saved as (" .. resstr .. ")");
				end
					
				settings.iodispatch["MENU_ESCAPE"]();
				settings.iodispatch["MENU_ESCAPE"]();
			end
		end
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

-- assumes current_game()
function gen_keymap_name( gamespecific )
	local reslbl = "keymaps/" .. current_game().target;

	if (gamespecific) then
		reslbl = reslbl .. "_" .. current_game().setname;
	end

	reslbl = reslbl .. ".lua";
	return reslbl;
end

-- quick heuristic, look for a game-specific, then target specific, else just use global
function set_internal_keymap()
	if ( resource( gen_keymap_name( true )) ) then
		local keytbl = system_load( gen_keymap_name(true) )();
		keyconfig.table = keytbl;

	elseif ( resource( gen_keymap_name( false )) ) then
		local keytbl = system_load( gen_keymap_name(false) )();
		keyconfig.table = keytbl;

-- this one is saved / restored every launch/cleanup internal in gridle.lua
	else
		keyconfig.table = settings.keyconftbl;
	end
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
		current_menu.formats[ label ] = settings.colourtable.notice_fontstr;
		settings.shader_opts[label] = true;
	end
	
	current_menu:move_cursor(0, 0, true);
end

local function configure_players(dstname)
	keyconfig_oldfname = keyconfig.keyfile;
	keyconfig.keyfile = dstname;

	keyconfig:reconfigure_players();
	kbd_repeat(0);

	gridle_input = function(iotbl)
		if (keyconfig:input(iotbl) == true) then
			gridle_input = gridle_dispatchinput;
			keyconfig.keyfile = keyconfig_oldfname;
		end
	end
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
	
	if ( captbl.dynamic_input ) then
		table.insert(lbltbl, "Local Input...");
		ptrtbl["Local Input..."] = function(label, store, sound)
			local lbls = {"Set (Game) Keyconfig", "Set (Target) Keyconfig"};
			local ptrs = {};
			
			ptrs["Set (Game) Keyconfig"]   = function() configure_players( gen_keymap_name( true ) );  end
			ptrs["Set (Target) Keyconfig"] = function() configure_players( gen_keymap_name( false ) ); end

			if ( resource( gen_keymap_name(true)) ) then
				table.insert(lbls, "Drop (Game) Keyconfig");
				ptrs["Drop (Game) Keyconfig"] = function()
					settings.iodispatch["MENU_ESCAPE"]();
					settings.iodispatch["MENU_ESCAPE"]();
					zap_resource( gen_keymap_name( true ) );
					set_internal_keymap();
				end
			end

			if ( resource( gen_keymap_name(false)) ) then
				table.insert(lbls, "Drop (Target) Keyconfig");
				ptrs["Drop (Target) Keyconfig"] = function()
					settings.iodispatch["MENU_ESCAPE"]();
					settings.iodispatch["MENU_ESCAPE"]();
					zap_resource( gen_keymap_name( false ) );
					set_internal_keymap();
				end
			end
			
			menu_spawnmenu( lbls, ptrs, {} );
		end
	end
	
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

function add_vidcap()
-- this one is part of gridle_customview
	customview.ci = {};
	local menudispatch = settings.iodispatch;
	
	local placeholdr = fill_surface(VRESW * 0.2, VRESH * 0.2, 255, 255, 0);
	customview.new_item(placeholdr, "vidcap", "vidcap");
	customview.ci.zv = max_current_image_order();

-- if positioned, store the setting of the desired vidcap position, when record is toggled
-- a vidcap frameserver will be launched as well, if it loads correctly, and will be positioned
-- according to the customview result
	customview.position_item(placeholdr, function(state, vid)
		if (state) then
			settings.vidcap = customview.ci;
		else
			settings.vidcap = nil;
		end

		cascade_visibility(current_menu, 1.0);
		settings.iodispatch = menudispatch;

		customview.ci = {};
		delete_image(placeholdr);
	end)
end

-- width, height are assumed to be :
-- % 2 == 0, and LE VRESW, LE VRESH
function disable_record()
	if (not valid_vid(imagery.record_target)) then return; end
	if (valid_vid(imagery.vidcap)) then delete_image(imagery.vidcap); end
	
	delete_image(imagery.record_target);
	delete_image(imagery.record_indicator);
end

function enable_record(width, height, args)
	local tbl = current_game();
	local lblbase = "movies/" .. tbl.setname;
	local dst = lblbase .. ".mkv";
	
	local ofs = 1;

-- only add sequence number if we already have a recording for the game
	while resource(dst) do
		dst = lblbase .. "_" .. tostring(ofs) .. ".mkv";
		ofs = ofs + 1;
	end

-- create an instance of this image to detach and record 
	local lvid = instance_image( internal_vid );
-- set it to the top left of the screen
	image_mask_clear(lvid, MASK_POSITION);
	image_mask_clear(lvid, MASK_OPACITY);

	move_image(lvid, 0, 0);

-- allocate intermediate storage
	local dstvid = fill_surface(width, height, 0, 0, 0, width, height);
	resize_image(lvid, width, height);
	local rectbl = {lvid};
	
-- connect a vidcap frameserver
	if (settings.vidcap) then
		vid, aid = load_movie("vidcap:0", FRAMESERVER_NOLOOP, function(source, status) 
			if (status.kind == "resized") then -- show / reposition
				local props = image_surface_properties( internal_vid ); 
				local wfact = (settings.vidcap.width  / props.width ) * width;
				local hfact = (settings.vidcap.height / props.height) * height;
				local xfact = (settings.vidcap.x - props.y) / (props.width / width);
				local yfact = (settings.vidcap.y - props.x) / (props.height / height);
				link_image(vid, lvid);
				
-- translate to internal_vid coordinate space, and rescale according with destination resolution
				resize_image(source, math.floor(wfact), math.floor(hfact));
				blend_image(source,  settings.vidcap.opa);
				move_image(source,   math.floor(xfact), math.floor(yfact)); 
				rotate_image(source, settings.vidcap.ang);
				order_image(source, max_current_image_order() + 1);
			else -- died (likely immediately)
				delete_image(source);
			end
				settings.vidcap = nil;
		end)
	
		if (valid_vid(vid)) then table.insert(rectbl, vid); end
	end
	
	show_image(lvid);
	define_recordtarget(dstvid, dst, args, rectbl, {internal_aid}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1);
	
	imagery.record_target = dstvid;
	imagery.record_indicator = fill_surface(16, 16, 255, 0, 0);
	
	move_image(imagery.record_indicator);
	image_transform_cycle(imagery.record_indicator, 1);
	blend_image(imagery.record_indicator, 255.0, 64);
	blend_image(imagery.record_indicator, 0.0, 64);
	order_image(imagery.record_indicator, max_current_image_order() + 1);
end

displaymodeptrs = {};
displaymodeptrs["Custom Shaders..."] = function() 
	local def = {};
	def[ settings.fullscreenshader ] = settings.colourtable.notice_fontstr;
	if (get_key("defaultshader")) then
		def[ get_key("defaultshader") ] = settings.colourtable.alert_fontstr;
	end
	
	local listl, listp = build_shadermenu();
	settings.context_menu = "custom shaders";
	menu_spawnmenu( listl, listp, def ); 
end

-- Don't implement save / favorite for these ones,
-- want fail-safe as default, and the others mess too much with GPU for that
displaymodelist = {"Custom Shaders..."};

local function add_displaymodeptr(list, ptrs, key, label, togglecb)
	local ctxmenus = {CRT = true, Overlay = false, Backdrop = false, Filter = true, NTSC = true, Vector = true};
	
	table.insert(list, label);
	
	ptrs[label] = function(label, save)
	settings.internal_toggles[key] = not settings.internal_toggles[key];

	current_menu.formats[label] = nil; 
	local iconlbl = " \\P" .. settings.colourtable.font_size .. "," .. settings.colourtable.font_size .. ",images/magnify.png,"	

	if (ctxmenus[label]) then 
		current_menu.formats[label] = iconlbl; 
	end
	
	if (settings.internal_toggles[key]) then
		current_menu.formats[label] = (ctxmenus[label] and iconlbl or "") .. settings.colourtable.notice_fontstr;
	else
		current_menu.formats[label] = (ctxmenus[label] and iconlbl or "") .. settings.colourtable.data_fontstr;
	end
	
	togglecb();
	current_menu:move_cursor(0, 0, true);
	gridlemenu_tofront(current_menu);
	end
end

add_displaymodeptr(displaymodelist, displaymodeptrs, "vector", "Vector", gridlemenu_rebuilddisplay);
add_displaymodeptr(displaymodelist, displaymodeptrs, "overlay", "Overlay", gridlemenu_rebuilddisplay);
add_displaymodeptr(displaymodelist, displaymodeptrs, "backdrop", "Backdrop", gridlemenu_rebuilddisplay);
add_displaymodeptr(displaymodelist, displaymodeptrs, "ntsc", "NTSC", push_ntsc);
add_displaymodeptr(displaymodelist, displaymodeptrs, "antialias", "Antialias", gridlemenu_rebuilddisplay);
add_displaymodeptr(displaymodelist, displaymodeptrs, "crt", "CRT", gridlemenu_rebuilddisplay);
	
local vectormenulbls = {};
local vectormenuptrs = {};
local crtmenulbls    = {};
local crtmenuptrs    = {};
local ntscmenulbls   = {};
local ntscmenuptrs   = {};
local filtermenulbls = {};
local filtermenuptrs = {};

local function updatetrigger()
	gridlemenu_rebuilddisplay();
end

add_submenu(ntscmenulbls, ntscmenuptrs, "Hue...",        "ntsc_hue",        gen_tbl_menu("ntsc_hue",        {-0.1, -0.05, 0, 0.05, 0.1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Saturation...", "ntsc_saturation", gen_tbl_menu("ntsc_saturation", {-1, -0.5, 0, 0.5, 1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Contrast...",   "ntsc_contrast",   gen_tbl_menu("ntsc_contrast",   {-0.5, 0, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Brightness...", "ntsc_brightness", gen_tbl_menu("ntsc_brightness", {-0.5, -0.25, 0, 0.25, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Gamma...",      "ntsc_gamma",      gen_tbl_menu("ntsc_gamma",      {-0.5, -0.2, 0, 0.2, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Sharpness...",  "ntsc_sharpness",  gen_tbl_menu("ntsc_sharpness",  {-1, 0, 1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Resolution...", "ntsc_resolution", gen_tbl_menu("ntsc_resolution", {0, 0.2, 0.5, 0.7}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Artifacts...",  "ntsc_artifacts",  gen_tbl_menu("ntsc_artifacts",  {-1, -0.5, -0.2, 0}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Bleed...",      "ntsc_bleed",      gen_tbl_menu("ntsc_bleed",      {-1, -0.5, -0.2, 0}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Fringing...",   "ntsc_fringing",   gen_tbl_menu("ntsc_fringing",   {-1, 0, 1}, push_ntsc))

add_submenu(displaymodelist, displaymodeptrs, "Filtering...",         "imagefilter",       gen_tbl_menu("imagefilter", {"None", "Linear", "Bilinear"}, updatetrigger, true));
add_submenu(vectormenulbls,  vectormenuptrs,  "Line Width...",        "vector_linew",      gen_num_menu("vector_linew",        1, 0.5,  6, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Point Size...",        "vector_pointsz",    gen_num_menu("vector_pointsz",      1, 0.5,  6, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Blur Scale (X)...",    "vector_hblurscale", gen_num_menu("vector_hblurscale", 0.2, 0.1,  9, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Blur Scale (Y)...",    "vector_vblurscale", gen_num_menu("vector_vblurscale", 0.2, 0.1,  9, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Vertical Offset...",   "vector_vblurofs",   gen_num_menu("vector_vblurofs",    -6,   1, 13, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Horizontal Offset...", "vector_hblurofs",   gen_num_menu("vector_hblurofs",    -6,   1, 13, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Vertical Bias...",     "vector_vbias",      gen_num_menu("vector_vbias",      0.6, 0.1, 13, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Horizontal Bias...",   "vector_hbias",      gen_num_menu("vector_hbias",      0.6, 0.1, 13, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Glow Trails...",       "vector_glowtrails", gen_num_menu("vector_glowtrails",   0,   1,  8, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Trail Step...",        "vector_trailstep",  gen_num_menu("vector_trailstep",   -1,  -1, 12, updatetrigger));
add_submenu(vectormenulbls,  vectormenuptrs,  "Trail Falloff...",     "vector_trailfall",  gen_num_menu("vector_trailfall",    0,   1,  9, updatetrigger));

add_submenu(crtmenulbls, crtmenuptrs, "CRT Gamma",             "crt_gamma",       gen_num_menu("crt_gamma",       1.8, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Monitor Gamma",         "crt_mongamma",    gen_num_menu("crt_mongamma",    1.8, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Curvature Radius",      "crt_curvrad",     gen_num_menu("crt_curvrad",     1.4, 0.1 , 8, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Distance",              "crt_distance",    gen_num_menu("crt_distance",    1.0, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Overscan (Horizontal)", "crt_hoverscan",   gen_num_menu("crt_hoverscan",   1.0, 0.02, 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Overscan (Vertical)",   "crt_voverscan",   gen_num_menu("crt_voverscan",   1.0, 0.02, 5, updatetrigger));

add_submenu(crtmenulbls, crtmenuptrs, "Aspect (Horizontal)",   "crt_haspect",     gen_tbl_menu("crt_haspect",     {0.75, 1.0, 1.25}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Aspect (Vertical)",     "crt_vaspect",     gen_tbl_menu("crt_vaspect",     {0.75, 1.0, 1.25}, updatetrigger)); 
add_submenu(crtmenulbls, crtmenuptrs, "Corner Size",           "crt_cornersz",    gen_tbl_menu("crt_cornersz",    {0.001, 0.01, 0.03, 0.05, 0.07, .1}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Corner Smooth",         "crt_cornersmooth",gen_tbl_menu("crt_cornersmooth",{80.0, 1000.0, 1500.0}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Tilt (Horizontal)",     "crt_tilth",       gen_tbl_menu("crt_tilth",       {-0.15, -0.05, 0.01, 0.05, 0.15}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Tilt (Vertical)",       "crt_tiltv",       gen_tbl_menu("crt_tiltv",       {-0.15, -0.05, 0.01, 0.05, 0.15}, updatetrigger));

local function flip_crttog(label, save)
	local dstkey;
	
	if (label == "Curvature")         then dstkey = "crt_curvature";  end
	if (label == "Gaussian Profile")  then dstkey = "crt_gaussian";   end
	if (label == "Oversample")        then dstkey = "crt_oversample"; end
	if (label == "Linear Processing") then dstkey = "crt_linearproc"; end
	
	settings[dstkey] = not settings[dstkey];
	
	if (save) then
		store_key(dstkey, settings[dstkey] and 1 or 0);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end

	current_menu.formats[label] = settings[dstkey] and settings.colourtable.notice_fontstr or nil;
	current_menu:move_cursor(0,0,true);
	
	gridlemenu_rebuilddisplay();
end

table.insert(crtmenulbls, "Curvature"); table.insert(crtmenulbls, "Gaussian Profile"); table.insert(crtmenulbls, "Oversample"); table.insert(crtmenulbls, "Linear Processing");
crtmenuptrs["Curvature"] = flip_crttog;
crtmenuptrs["Gaussian Profile"] = flip_crttog;
crtmenuptrs["Oversample"] = flip_crttog;
crtmenuptrs["Linear Processing"] = flip_crttog;

recordlist = {};
recordptrs = {};

add_submenu(recordlist, recordptrs, "Format...", "record_format", gen_tbl_menu("record_format", {"WebM (VP8/Vorbis)", "Lossless (FFV1/FLAC)"}, function() end, true));
add_submenu(recordlist, recordptrs, "Framerate...", "record_fps", gen_tbl_menu("record_fps", {12, 24, 25, 30, 50, 60}, function() end));
add_submenu(recordlist, recordptrs, "Max Vertical Resolution...", "record_res", gen_tbl_menu("record_res", {720, 576, 480, 360, 288, 240}, function() end));
add_submenu(recordlist, recordptrs, "Quality...", "record_qual", gen_tbl_menu("record_qual", {2, 4, 6, 8, 10}, function() end));
add_submenu(recordlist, recordptrs, "Overlay Feed...", "record_overlay", gen_tbl_menu("ignore", {"Vidcap"}, add_vidcap, true));

table.insert(recordlist, "Start");

recordptrs["Start"] = function() 
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"]();

	local props  = image_surface_initial_properties(internal_vid);
	local width  = props.width;
	local height = props.height;

	if (settings.record_res < props.height) then
		width = ( width / height ) * settings.record_res;
	end

-- need to be evenly divisible
	width = math.floor(width);
	height = math.floor(height);
	width = (width % 2 == 0) and width or width + 1;
	height = (height % 2 == 0) and height or height + 1;

-- compile a string with all the settings- goodness
	local recstr = settings.record_format == "Lossless (FFV1/FLAC)" and "acodec=flac:vcodec=ffv1" or "acodec=libvorbis:vcodec=libvpx";
	recstr = recstr .. ":fps=" .. tostring(settings.record_fps) .. ":apreset=" .. tostring(settings.record_qual) .. ":vpreset=" .. tostring(settings.record_qual);
	
	enable_record(width, height, recstr);
end

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
					fmts[ key ] = settings.colourtable.notice_fontstr; 
				end
			end

			if (#labels > 0) then
				settings.shader_opts = def;
				menu_spawnmenu(labels, ptrs, fmts);
			end
			
		elseif (selectlbl == "CRT") then
			fmts = {};

			if (settings.crt_gaussian) then fmts["Gaussian Profile"] = settings.colourtable.notice_fontstr; end
			if (settings.crt_linearproc) then fmts["Linear Processing"] = settings.colourtable.notice_fontstr; end
			if (settings.crt_curvature) then fmts["Curvature"] = settings.colourtable.notice_fontstr; end
			if (settings.crt_oversample) then fmts["Oversample"] = settings.colourtable.notice_fontstr; end

			menu_spawnmenu(crtmenulbls, crtmenuptrs, fmts);

		elseif (selectlbl == "Vector") then
			fmts = {}; 
			menu_spawnmenu(vectormenulbls, vectormenuptrs, fmts);
	
		elseif (selectlbl == "NTSC") then
			fmts = {};
			menu_spawnmenu(ntscmenulbls, ntscmenuptrs, fmts);
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
		table.insert(menulbls, "-----" );
	end

	if (settingslbls) then
		table.insert(menulbls, "Display Modes...");
		table.insert(menulbls, "Scaling...");
		table.insert(menulbls, "Input...");
		table.insert(menulbls, "Audio Gain...");
		table.insert(menulbls, "Cocktail Modes...");
		table.insert(menulbls, "Record...");
		table.insert(menulbls, "Screenshot");
	end

	local fmts = {};
	fmts["Screenshot"] = [[\b]] .. settings.colourtable.notice_fontstr;
	current_menu = listview_create(menulbls, VRESH * 0.9, VRESW / 3, fmts);
	current_menu.ptrs = ptrs;
	current_menu.parent = nil;

	current_menu.ptrs["Display Modes..."] = function()
		local def = {};
		local gottog = false;
		local iconlbl = " \\P" .. settings.colourtable.font_size .. "," .. settings.colourtable.font_size .. ",images/magnify.png,";
		
		def[ "CRT" ]     = iconlbl .. (settings.internal_toggles.crt    and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def[ "NTSC" ]    = iconlbl .. (settings.internal_toggles.ntsc   and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def[ "Vector" ]  = iconlbl .. (settings.internal_toggles.vector and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		
		def[ "Overlay"  ] = settings.internal_toggles.overlay  and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr;
		def[ "Backdrop" ] = settings.internal_toggles.backdrop and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr	
		def[ "Antialias"] = settings.internal_toggles.antialias and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr;
		
		settings.context_menu = "display modes";
		menu_spawnmenu(displaymodelist, displaymodeptrs, def );
	end

	current_menu.ptrs["Scaling..."] = function()
		local def = {};
		def[ settings.scalemode ] = settings.colourtable.notice_fontstr;
		if (get_key("scalemode")) then
			def[ get_key("scalemode") ] = settings.colourtable.alert_fontstr;
		end
		
		menu_spawnmenu( scalemodelist, scalemodeptrs, def );
	end
	
	current_menu.ptrs["Input..."] = function()
		local def = {};
		if (settings.filter_opposing) then
			def["Filter Opposing"]= settings.colourtable.notice_fontstr;
		end
		
		def[ settings.internal_input ] = settings.colourtable.notice_fontstr;
		if (get_key("internal_input")) then
			def[ get_key("internal_input") ] = settings.colourtable.alert_fontstr;
		end
		
		menu_spawnmenu( inputmodelist, inputmodeptrs, def );
	end
	
	current_menu.ptrs["Audio Gain..."] = function()
		local def = {};
		def[ tostring(settings.internal_again) ] = settings.colourtable.notice_fontstr;
		if (get_key("internal_again")) then
			def[ get_key("internal_again") ] = settings.colourtable.alert_fontstr;
		end
		
		menu_spawnmenu( audiogainlist, audiogainptrs, def );
	end
	
-- trickier than expected, as we don't want the game to progress and we don't want any UI elements involved */
	current_menu.ptrs["Screenshot"] = function()
		local tbl = current_game();
		
		settings.iodispatch["MENU_ESCAPE"]();
		local tmpclock = gridle_clock_pulse;

		tmpclock_c = 22; -- listview has a fixed 20tick expire
		escape_locked = true;
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
				escape_locked = false;
			end
		end
	end
	
	current_menu.ptrs["Cocktail Modes..."] = function()
		local def = {};
		def[ tostring(settings.cocktail_mode) ] = settings.colourtable.notice_fontstr;
		if (get_key("cocktail_mode")) then
			def[ get_key("cocktail_mode") ] = settings.colourtable.alert_fontstr;
		end
		
		menu_spawnmenu( cocktaillist, cocktailptrs, def);
	end

	
	current_menu.ptrs["Record..."] = function()
		local def = {};
		def["Start"] = [[\b]] .. settings.colourtable.notice_fontstr;
		menu_spawnmenu( recordlist, recordptrs, def); 
	end
	
	gridlemenu_defaultdispatch();
	settings.context_menu = nil;
	
	current_menu:show();
	suspend_target(internal_vid);
	play_audio(soundmap["MENU_TOGGLE"]);
	move_image(current_menu.anchor, 10, math.floor(VRESH * 0.1), settings.fadedelay);
end
