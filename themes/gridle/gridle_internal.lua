--
-- Same mess as with gridle_settings
-- most are just lists of  textlabels mapping to a similar 
-- callback structure that, when triggered, either spawns a submenu or 
-- updates the settings table, possibly calling store_key.
--
-- The ones that work differently are mostly shader submenu (scans filesystem)
-- saves/loads menu (scans filesystem and pops up OSD keyboard)
-- input-port config menu (generates "N" slots, with possible constraints 
-- for each submenu in each slot)
--
-- changes to most/all of these needs to be tested both from "grid view" 
-- and from "detailed view + zoom"
--

local scalemodelist = {
	"Keep Aspect",
	"Original Size",
	"2X",
	"Stretch",
	"Rotate 90 CW",
	"Rotate 90 CCW",
	"Bezel"
};

local deffshdr = [[
	uniform sampler2D map_diffuse;
	varying vec2 texco;
	uniform float obj_opacity;

	void main(){
		vec4 col = texture2D(map_diffuse, texco);
		col.a = obj_opacity;
		gl_FragColor = col;
	}
]];
build_shader(nil, deffshdr, "default_target");

-- NOTE; H264 encoding seems to yield broken MOV
local codectbl = {};
local codeclbls = {"Lossless (MKV/FFV1/RAW)", "Lossless (MKV/FFV1/FLAC)", 
	"WebM (MKV/VP8/OGG)", "H264 (MKV/H264/MP3)"};

codectbl["Lossless (MKV/FFV1/RAW)"]  = 
	"acodec=RAW:vcodec=FFV1:container=matroska";

codectbl["Lossless (MKV/FFV1/FLAC)"] = 
	"acodec=FLAC:vcodec=FFV1:container=matroska";
	
codectbl["WebM (MKV/VP8/OGG)"]       = 
	"acodec=VORBIS:vcodec=VP8:container=matroska";

codectbl["H264 (MKV/H264/MP3)"]      = 
	"acodec=MP3:vcodec=H264:container=matroska";

local recstr = "libvorbis:vcodec=H264:container=stream:acodec=MP3:streamdst=" 
	.. string.gsub(settings.stream_url and settings.stream_url or "", ":", "\t");

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

	gridlemenu_rebuilddisplay(settings.internal_toggles);
end

for ind, val in ipairs(scalemodelist) do scalemodeptrs[val] = scalemodechg; end

local inputmodelist = {
-- revert all manipulation to default settings
	"Normal",
	"Rotate 90 CW",
	"Rotate 90 CCW",
	"Invert Axis (analog)",
	"Mirror Axis (analog)",
	"Filter Opposing",
	"Toggle Mouse Grab",
	"---Permanent",
	"Reconfigure Keys"
};

local inputmodeptrs = {};
local function inputmodechg(label, save)
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	if (label == "Toggle Mouse Grab") then
		toggle_mouse_grab();
		play_audio(soundmap["MENU_SELECT"]);
		return;
	end

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

	current_menu:invalidate();
	current_menu:redraw();

	if (save) then
		store_key("filter_opposing", settings.filter_opposing and "1" or "0");
	end
end

inputmodeptrs["Reconfigure Keys"] = function()
	if (settings.privileged ~= true) then
		return;
	end
	
	keyconfig:reconfigure_players();
	kbd_repeat(0);

	dispatch_push({}, "reconfigure keys (player, in game)", function(iotbl)
		if (keyconfig:input(iotbl) == true) then
			dispatch_pop();
			kbd_repeat(settings.repeatrate);
    end	
	end, 0);
end

inputmodeptrs["Toggle Mouse Grab"] = inputmodechg;
inputmodeptrs["Normal"] = inputmodechg;
inputmodeptrs["Rotate 90 CW"] = inputmodechg;
inputmodeptrs["Rotate 90 CCW"] = inputmodechg;
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

	gridlemenu_rebuilddisplay(settings.internal_toggles);

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
-- upon selection, load it into the "fullscreen" 
-- slot and reset the relevant uniforms
local function build_shadermenu()
	local reslbls = {};
	local resptrs = {};
	local shaderlist = {};
	local vreslist = glob_resource(
		"shaders/fullscreen/*.vShader", SHARED_RESOURCE);

	local freslist = glob_resource(
		"shaders/fullscreen/*.fShader", SHARED_RESOURCE);

-- make sure both exist, add vertex to list, 
-- then add to real list if fragment exist as well
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
	gridlemenu_rebuilddisplay(settings.internal_toggles);
end

local cocktaillist = {
	"Disabled",
	"H-Split", 
	"V-Split",
	"H-Split SBS", 
  "H-Split Slice" 
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
	image_set_txcos_default(source, settings.internal_mirror);
	local cv = instance_image(source);

	imagery.cocktail_vid = cv;
	table.insert(imagery.temporary, cv);
	show_image(cv);
	image_tracetag(cv, "cocktail");
	image_mask_clear(cv, MASK_ORIENTATION);

	if (settings.fullscreen_shader ~= nil) then
		image_shader(cv, settings.fullscreen_shader);
	end

	if (mode == "H-Split" or mode == "H-Split SBS" 
		or mode == "H-Split Slice") then
		image_mask_clear(cv, MASK_POSITION);
	
		if (mode == "H-Split") then
			rotate_image(cv, 180);
		end

-- for this one, patch the texture coordinates to only show half and half
		if (mode == "H-Split Slice") then
			local lary = {};
			local rary = {};
			local txcos = image_get_txcos(source);
			
			local ul = 0.0;
			for i=1,#txcos do
				if (txcos[i] > ul) then ul = txcos[i]; end
			end

			ul = ul * 0.5;
			
			for i=1,#txcos do
				lary[i] = (i % 2 == 0) and (txcos[i] * 0.5     ) or txcos[i];
				rary[i] = (i % 2 == 0) and (txcos[i] * 0.5 + ul) or txcos[i];
			end

			image_set_txcos(source, lary);
			image_set_txcos(cv,     rary);
		end

		move_image(source, math.floor(0.5 * (vresw - props.width)), 
			math.floor(0.5 * (vresh - props.height)) );

		move_image(cv, vresw + math.floor(0.5 * (vresw - props.width)), 
			math.floor(0.5 * (vresh - props.height)) );

	elseif (mode == "V-Split") then
		move_image(source, math.floor(0.5 * (vresh - props.width)), 
			math.floor(0.5 * (vresw - props.height)));

		move_image(cv, vresh, 0);
		rotate_image(cv,    -90);
		rotate_image(source, 90);
	end
end

local function setup_bezel(source)
	if (image_loaded(source)) then
		local props = image_storage_properties(source);
		resize_image(source, INTERW, INTERH); 
		local x1,y1,x2,y2 = image_borderscan(source);

		x1 = (x1 / props.width) * INTERW;
		x2 = (x2 / props.width) * INTERW;
		y1 = (y1 / props.height) * INTERH;
		y2 = (y2 / props.height) * INTERH;

		local dstvid = valid_vid(imagery.display_vid) 
			and imagery.display_vid or internal_vid;

		resize_image(dstvid, x2 - x1, y2 - y1);
		move_image(dstvid, x1, y1);
		order_image(source, image_surface_properties(dstvid).order);
		force_image_blend(source, BLEND_NORMAL);
		show_image(source);
	else
		hide_image(source);
	end
end

--
-- generates a shader with the purpose of mixing together history frames 
-- with the help of a set of weighhts
-- frames : array of #of frames and textures to be used
-- delta  : don't mix "everything" just the changes versus the first texture
-- deltaonly : only output the changes relative 
-- 	to the first frame (use with delta)
--
function create_weighted_fbo( frames, delta, deltaonly )
	local resshader = {};
	table.insert(resshader, "varying vec2 texco;");

	for i=0,#frames-1 do
		table.insert(resshader, "uniform sampler2D map_tu" .. tostring(i) .. ";");
	end

	table.insert(resshader, "void main(){");
	table.insert(resshader, "vec4 col0 = texture2D(map_tu0, texco);");
		
	mixl = "";
	for i=1,#frames-1 do
		if (delta) then
			table.insert(resshader, 
				string.format(
					"vec4 col%d = clamp(col0 - " ..
					"texture2D(map_tu%d, texco), 0.0, 1.0);", i, i));
		else
			table.insert(resshader, 
				string.format("vec4 col%d = texture2D(map_tu%d, texco);", i, i));
		end

		local strv = tostring(frames[i]);
		strv = string.gsub(strv, ",", "."); 

		local coll = "vec4(" .. strv .. ", " .. strv .. ", " .. strv .. ", 1.0)";
		mixl = mixl .. "col" .. tostring(i) .. " * " .. coll;

		if (i == #frames-1) then
			mixl = mixl .. ";\n}\n";
		else
			mixl = mixl .. " + ";
		end
	end

	if (delta and deltaonly) then
		table.insert(resshader, 
			"gl_FragColor = vec4(0.0, 0.0, 0.0, 1.0) + " ..mixl);
	else
		table.insert(resshader, "gl_FragColor = col0 + " ..mixl);
	end
	
	return resshader;
end

-- configure shaders for the blur / glow / bloom effect
function vector_setupblur(targetw, targeth, blurw, blurh, hbias, vbias)
	local blurshader_h = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/fullscreen/gaussianH.fShader", "blur_horiz", {});

	local blurshader_v = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/fullscreen/gaussianV.fShader", "blur_vert", {});

	shader_uniform(blurshader_h, "blur", "f", PERSIST, 1.0 / blurw);
	shader_uniform(blurshader_v, "blur", "f", PERSIST, 1.0 / blurh);
	shader_uniform(blurshader_h, "ampl", "f", PERSIST, hbias);
	shader_uniform(blurshader_v, "ampl", "f", PERSIST, vbias);
	
	local blur_hbuf = fill_surface(blurw, blurh, 1, 1, 1, blurw, blurh);
	local blur_vbuf = fill_surface(targetw, targeth, 1, 1, 1, blurw, blurh);

	image_shader(blur_hbuf, blurshader_h);
	image_shader(blur_vbuf, blurshader_v);

	show_image(blur_hbuf);
	show_image(blur_vbuf);

	return blur_hbuf, blur_vbuf;
end

-- "slightly" easier than SMAA ;-)
function display_fxaa(source, targetw, targeth)
	local fxaa_shader = load_shader("shaders/fullscreen/default.vShader", 
		"display/fxaa.fShader", "fxaa", {});
	local node        = instance_image(source);
	local fxaa_outp   = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);

	local props = image_surface_properties(source);

	shader_uniform(fxaa_shader, "pixel_size", "ff", 
		PERSIST, 1.0 / targetw, 1.0 / targeth);

	hide_image(source);
	image_shader(node, fxaa_shader);
	resize_image(node, targetw, targeth);
	image_mask_clear(node, MASK_POSITION);
	image_mask_clear(node, MASK_OPACITY);
	image_mask_set(node, MASK_MAPPING);
	show_image(node);

	define_rendertarget(fxaa_outp, {node}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	show_image(fxaa_outp);
	order_image(fxaa_outp, INGAMELAYER_DISPLAY);

	return fxaa_outp;
end

function display_smaa(source, targetw, targeth)
-- start with edge detection
	local edge_shader = load_shader("display/smaa_edge.vShader", 
		"display/smaa_edge.fShader", "smaa_edge", {});

	local node        = instance_image(source);
	local edge_outp   = fill_surface(targetw, targeth, 1, 1, 1, targetw, targeth);
	shader_uniform(edge_shader, "pixel_size", 
		"ff", PERSIST, 1.0 / targetw, 1.0 / targeth);

	hide_image(source);

	image_shader(node, edge_shader);
	resize_image(node, targetw, targeth);
	image_mask_clear(node, MASK_POSITION);
	image_mask_clear(node, MASK_OPACITY);
	show_image(node);

	define_rendertarget(edge_outp, {node}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	show_image(edge_outp);

-- return edge_outp; here to verify the edge detection step
-- the complicated part, generate the blend map 
-- by using the edge detection as input,
-- along with two LUTs (area / search)
	local blend_shader = load_shader("display/smaa_blend.vShader", 
		"display/smaa_blend.fShader", "smaa_blend", {});

	shader_uniform(blend_shader, "pixel_size", "ff", 
		PERSIST, 1.0 / targetw, 1.0 / targeth);

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

	define_rendertarget(blend_outp, {blend_comb}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- last step is instancing source again, 
-- combine with blend_outp and the neighbor shader unfinished
	return blend_outp;
end

local function get_blendcopy(srcvid, resvid, blendmode)
	local tmpover = instance_image(srcvid);
	image_mask_clear(tmpover, MASK_OPACITY);
	image_mask_clear(tmpover, MASK_POSITION);

	copy_surface_properties(resvid, tmpover);
	order_image(tmpover, INGAMELAYER_DISPLAY);
	force_image_blend(tmpover, blendmode);
	show_image(tmpover);

	table.insert(imagery.temporary, tmpover);
	return tmpover;
end

--
-- Set up a number of "spare" textures that act as storage for 
-- previous frames in the 'source' vid.
-- Will return the vid of the output rendertarget
-- trails    : number of history frames
-- trailstep : number of frames between each "step"
-- trailfall : >=0..9 (1.0-n then step to 0.1), 1+ exponential fade
-- targetw / targeth: down or upscale the output
--
function add_historybuffer(source, trails, 
	trailstep, trailfall, targetw, targeth)
	local frames = {};
	local base = 1.0;
	
	if (trailfall > 0) then
		local startv = 0.9 - (math.abs(trailfall) / 10.0);
		local endv   = 0.1;
		local step   = (startv - endv) / trails;
		
		for i=0, trails do
			frames[i+1] = startv - (step * i);
		end
	else
		trailfall = math.abs(trailfall);
-- exponential
		for i=0, trails do
			frames[i+1] = 1.0 / math.exp( trailfall * (i / trails) );
		end
	end
	
-- dynamically generate a shader that multitextures 
-- and blends using the above weights
	local fshader;
	if (settings.vector_deltamethod == "Off") then
		fshader = create_weighted_fbo(frames, false, false);
	elseif (settings.vector_deltamethod == "On") then
		fshader = create_weighted_fbo(frames, true, false);
	else
		fshader = create_weighted_fbo(frames, true, true);
	end
	
	local mixshader = load_shader("shaders/fullscreen/default.vShader", 
		fshader, "history_mix", {});

	image_framesetsize(source, #frames, FRAMESET_MULTITEXTURE);
	image_framecyclemode(source, trailstep);
	image_shader(source, mixshader);
	show_image(source);
	move_image(source, 0, 0);
	image_mask_set(source, MASK_MAPPING);
	
-- generate textures to use as round-robin store, 
-- these need to match the storage size to avoid  a copy/scale each frame
	local props = image_surface_initial_properties(internal_vid);
	for i=1,trails do
		local vid = fill_surface(targetw, targeth, 
			0, 0, 0, props.width, props.height);

		image_texfilter(vid, FILTER_NONE);
		set_image_as_frame(source, vid, i, FRAMESET_DETACH);
	end

	image_texfilter(source, FILTER_NONE);
	rendertgt = fill_surface(targetw, targeth, 0, 0, 0, targetw, targeth);
	image_texfilter(rendertgt, FILTER_NONE);
	define_rendertarget(rendertgt, {source}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	resize_image(source, targetw, targeth);
	show_image(rendertgt);
	image_tracetag(rendertgt, "vector(trailblur)");

	return rendertgt;
end

function display_defects(source, targetw, targeth, blur, trails)
	local hbuffer = source;
	
	if (trails) then
		hbuffer = add_historybuffer(source, settings.vector_glowtrails, 
			settings.vector_trailstep, settings.vector_trailfall, targetw, targeth);
	end
	
	if (blur) then
-- clone the source and use as "normal" overlay
		local normal = instance_image(source);
		image_mask_set(normal, MASK_FRAMESET);
		show_image(normal);
		resize_image(normal, targetw, targeth);
		image_mask_set(normal, MASK_MAPPING);

-- add a gaussian blur
		local blurw = targetw * settings.vector_hblurscale;
		local blurh = targeth * settings.vector_vblurscale;
		local blur_hbuf, blur_vbuf = vector_setupblur(targetw, targeth, 
			blurw, blurh, settings.vector_hbias, settings.vector_vbias);

		image_tracetag(blur_hbuf, "vector(hblur)");
		image_tracetag(blur_vbuf, "vector(vblur)");
		move_image(hbuffer, 0, 0);
		resize_image(hbuffer, blurw, blurh);
		
		define_rendertarget(blur_hbuf, {hbuffer},   
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

		define_rendertarget(blur_vbuf, {blur_hbuf}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

-- do a weighted additive blend into an output target, possibly offset as well, 
-- rescale and filter as needed
		local comp_outbuf = fill_surface(
			targetw, targeth, 1, 1, 1, targetw, targeth);

		blend_image(blur_vbuf, 0.99);
		force_image_blend(blur_vbuf, BLEND_ADD);
		resize_image(blur_vbuf, targetw, targeth);
		image_tracetag(comp_outbuf, "vector(composite)");

		force_image_blend(blur_vbuf, BLEND_ADD);
		force_image_blend(normal, BLEND_ADD); 
		order_image(blur_vbuf, 2);
		order_image(normal, 3);
		define_rendertarget(comp_outbuf, {blur_vbuf, normal}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

		show_image(comp_outbuf);
		hbuffer = comp_outbuf;
	end

	return hbuffer;
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
	image_shader(internal_vid, "default_target");

	image_framesetsize(internal_vid, 0);
	image_framecyclemode(internal_vid, 0);

-- lots of things happening beneath the surface here, 
-- killing the vector vid will cascade and drop all detached images
-- that are part of the render target, EXCEPT for the initial 
-- internal vid that has its MASKED_LIVING disabled
-- this means that it gets reattached to the main pipe instead of deleted
	if (valid_vid(imagery.display_vid)) then
		delete_image(imagery.display_vid);
	end

	for ind,val in ipairs(imagery.temporary) do
		if (valid_vid(val)) then
			delete_image(val);
		end
	end

	image_set_txcos_default(internal_vid, settings.internal_mirror);
	imagery.temporary = {};
	imagery.display_vid = BADID;
end

local function toggle_displaydefects(sourcevid, windw, windh)
	if (sourcevid == internal_vid) then
		image_mask_clear(internal_vid, MASK_LIVING);
		image_texfilter(internal_vid, FILTER_NONE);
	end

	imagery.display_vid = display_defects(sourcevid, windw, windh, 
		settings.internal_toggles.glow, settings.internal_toggles.trails);

	order_image(imagery.display_vid, 1);

-- CRT toggle is done through the fullscreen_shader member 
-- (should be refactored but that goes for this whole display 
-- toggle mess, there's just too many permutations 
-- at the moment...
end

--
-- factor is 2+, will return vid, newwidth, newheight, actual factor
-- mode is upscaler mode (sabr only currently)
--
local function toggle_upscaler(sourcevid, init_props, mode, factor)
-- there's compile time limitations to custom surfaces
	local neww = init_props.width  * factor;
	local newh = init_props.height * factor;

	while ((neww > INTERW or newh > INTERH) and factor > 1) do
		factor = factor - 1;
		neww = init_props.width * factor;
		newh = init_props.height * factor;
	end

	-- don't activate if there's no need or if we outsize
	if ( neww >= MAX_SURFACEW or newh >= MAX_SURFACEH or factor < 2) then
		return nil;
	end

	local shader = nil;
	if (mode == "sabr") then
		shader = load_shader("display/sabr.vShader", 
			"display/sabr.fShader", "sabr", {});
	else
		local definetbl = {};

		if (mode == "xbr-rounded") then
			definetbl["METHOD_A"] = true;
		elseif (mode == "xbr-semi-rounded") then
			definetbl["METHOD_B"] = true;
		elseif (mode == "xbr-square") then
			definetbl["METHOD_C"] = true;
			definetbl["REVAA_HYBRID"] = true;
		elseif (mode == "xbr-l3") then
			definetbl["LEVEL_3A"] = true;
		end

		shader = load_shader("display/xbr.vShader", 
			"display/xbr.fShader", "xbr", definetbl);
	end

	if (mode ~= "sabr") then
		shader_uniform(shader, "deltav", "f", PERSIST, settings.upscale_delta);
		shader_uniform(shader, "eq_threshold","ffff", PERSIST, 
			settings.upscale_ineq, settings.upscale_ineq, 
			settings.upscale_ineq, settings.upscale_ineq);
	end

	shader_uniform(shader, "storage_size", "ff", PERSIST, neww, newh);
	shader_uniform(shader, "texture_size", "ff", 
		PERSIST, init_props.width, init_props.height);

	hide_image(sourcevid);
	local workvid = instance_image(sourcevid);
	image_mask_clear(workvid, MASK_POSITION);
	image_mask_clear(workvid, MASK_OPACITY);
	image_shader(workvid, shader);
	image_tracetag(workvid, "(upscale_internal)");
	show_image(workvid);
	image_set_txcos_default(workvid, settings.internal_mirror);

	upscaler = fill_surface(neww, newh, 0, 0, 0, neww, newh);
	define_rendertarget(upscaler, {workvid}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

	show_image(upscaler);
	resize_image(workvid, neww, newh);
	move_image(workvid, 0, 0);
	image_texfilter(workvid, FILTER_NONE);
	image_texfilter(upscaler, FILTER_NONE);

	image_tracetag(upscaler, "(upscale_output)");
	table.insert(imagery.temporary, workvid);
	table.insert(imagery.temporary, upscaler);

-- optional additional postprocessor
	if (settings.upscale_ddt and upscaler) then
		local ddtshader = load_shader("display/ddt.vShader", 
			"display/ddt.fShader", "ddt", {});

		shader_uniform(ddtshader, "texture_size", "ff", PERSIST, neww, newh);

		ddtsurf = fill_surface(neww, newh, 0, 0, 0, neww, newh);
		define_rendertarget(ddtsurf, {upscaler}, 
			RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);

		image_shader(ddtsurf, ddtshader);
		image_tracetag(ddtsurf, "(upscale DDT filter)");

		table.insert(imagery.temporary, ddtsurf);
		return ddtsurf;
	end

	return upscaler;
end

local function toggle_crtmode(vid, props, windw, windh)
	local shaderopts = {};
-- CURVATURE, OVERSAMPLE, LINEAR_PROCESSING, USEGAUSSIAN
	if (settings.crt_curvature)  then shaderopts["CURVATURE"]         = true; end
	if (settings.crt_gaussian)   then shaderopts["USEGAUSSIAN"]       = true; end
	if (settings.crt_linearproc) then shaderopts["LINEAR_PROCESSING"] = true; end
	if (settings.crt_oversample) then shaderopts["OVERSAMPLE"]        = true; end

	local shader = load_shader("display/crt.vShader", 
		"display/crt.fShader", "crt", shaderopts);

	local sprops = image_storage_properties(vid);
	settings.fullscreen_shader = shader;

	shader_uniform(shader, "input_size",   "ff", 
		PERSIST, props.width, props.height);

	shader_uniform(shader, "output_size",  "ff", 
		PERSIST, props.width, props.height);

	shader_uniform(shader, "storage_size", "ff", 
		PERSIST, sprops.width, sprops.height);

	shader_uniform(shader, "CRTgamma",      "f", 
		PERSIST, settings.crt_gamma);

	shader_uniform(shader, "overscan",     "ff", 
		PERSIST, settings.crt_hoverscan, settings.crt_voverscan);

	shader_uniform(shader, "monitorgamma",  "f", 
		PERSIST, settings.crt_mongamma);

	shader_uniform(shader, "aspect",       "ff", 
		PERSIST, settings.crt_haspect, settings.crt_vaspect);

	shader_uniform(shader, "distance",      "f", 
		PERSIST, settings.crt_distance);

	shader_uniform(shader, "curv_radius",   "f", 
		PERSIST, settings.crt_curvrad);

	if (settings.internal_mirror) then
		shader_uniform(shader, "tilt_angle", "ff", 
			PERSIST, settings.crt_tilth, settings.crt_tiltv * -1);
	else
		shader_uniform(shader, "tilt_angle", "ff", 
			PERSIST, settings.crt_tilth, settings.crt_tiltv);
	end

	shader_uniform(shader, "cornersize",   "f",  
		PERSIST, settings.crt_cornersz);
	shader_uniform(shader, "cornersmooth", "f",  
		PERSIST, settings.crt_cornersmooth);

	image_shader(vid, shader);
end

local filterlut = {None = FILTER_NONE,
		Linear      = FILTER_LINEAR,
		Bilinear    = FILTER_BILINEAR};

local function update_filter(vid, filtermode)
	local modeval = filterlut[filtermode];

	if (modeval) then
		image_texfilter(vid, modeval);
	end
end

function push_ntsc(noresume)
	target_postfilter_args(internal_vid, 1, 
		settings.ntsc_hue, settings.ntsc_saturation, settings.ntsc_contrast);
	target_postfilter_args(internal_vid, 2, 
		settings.ntsc_brightness, settings.ntsc_gamma, settings.ntsc_sharpness);
	target_postfilter_args(internal_vid, 3, 
		settings.ntsc_resolution, settings.ntsc_artifacts, settings.ntsc_bleed);
	target_postfilter_args(internal_vid, 4, settings.ntsc_fringing);

	target_postfilter(internal_vid, 
		settings.internal_toggles.ntsc and POSTFILTER_NTSC or POSTFILTER_OFF);

-- for the argument changes to be reflected, we need the video rolling
	if (noresume == nil or noresume == false) then
		resume_target(internal_vid);
	end
end

--
-- Needs to be done to all changes to the original video source,
--
-- (upscale) -> (antialias) -> 
-- 	(final_scaler -> (vector | gameboy) -> (crt) -> (cocktail)
-- NTSC prefilter is enabled in the source frameserver so not included here
-- There's also a NTSC shader by themaister that 
-- could be considered, but the "switch" is really 
-- dependent on how heavy the GPU load already is
--
function gridlemenu_rebuilddisplay(toggles)
	if (toggles == nil) then
		toggles = {};
	end

	undo_displaymodes();

-- default filter preference isn't guaranteed 
-- to work as higher priority display mode
-- options can well override them.
	update_filter(internal_vid, settings.imagefilter);

	local props  = image_surface_initial_properties(internal_vid);
	local dstvid = internal_vid;

	if (toggles.upscaler) then
		local upscale = toggle_upscaler(internal_vid, props, 
			settings.upscale_method, settings.upscale_factor);
		if (upscale ~= nil) then
			dstvid = upscale;
			props = image_surface_initial_properties(dstvid);
		end
	end

	local windw, windh = gridlemenu_resize_fullscreen(dstvid, props);
	local props = image_surface_properties(dstvid);
	
	if (toggles.antialias) then
		dstvid = display_fxaa(dstvid, props.width, props.height);
		imagery.display_vid = dstvid;
	end
	
	if (settings.internal_toggles.glow or settings.internal_toggles.trails) then
		target_pointsize(dstvid, settings.vector_pointsz);
		target_linewidth(dstvid, settings.vector_linew);

		local dstw, dsth;
		if (props.width > INTERW or props.height > INTERH) then
			dstw = windw;
			dsth = windh;
		else
			dstw = props.width;
			dsth = props.height;
		end

		toggle_displaydefects(dstvid, dstw, dsth);
		dstvid = imagery.display_vid;
	else
		settings.fullscreen_shader = 
			gridlemenu_loadshader(settings.fullscreenshader, dstvid);
	end	

-- redo so that instancing etc. match
	order_image(dstvid, INGAMELAYER_DISPLAY);
	show_image(dstvid);

-- redo resize so it covers possible FBO rendertargets
	local windw, windh = gridlemenu_resize_fullscreen(dstvid, props)
	update_filter(dstvid, settings.imagefilter);

-- crt is always last
	if (toggles.crt) then
-- special case with cocktail modes
		toggle_crtmode(dstvid, 
			image_surface_initial_properties(dstvid), windw, windh);

		if ( valid_vid(imagery.cocktail_vid) ) then
			image_shader(imagery.cocktail_vid, settings.fullscreen_shader);
		end
	end

	if (toggles.backdrop and valid_vid(imagery.backdrop)) then
		get_blendcopy(imagery.backdrop, dstvid, BLEND_ADD);
		
		if (valid_vid(imagery.cocktail_vid)) then
			local cockt_cpy = get_blendcopy(imagery.backdrop, 
				imagery.cocktail_vid, BLEND_ADD);
		end
	end

	if (toggles.overlay and valid_vid(imagery.overlay)) then
		get_blendcopy(imagery.overlay, dstvid, BLEND_MULTIPLY);
		
		if (valid_vid(imagery.cocktail_vid)) then
			local cockt_cpy = get_blendcopy(imagery.overlay, 
				imagery.cocktail_vid, BLEND_MULTIPLY);
		end
	end

--
-- with NTSC rolling, we need to keep updating to get the changes 
-- to be reflected, thus the "noresume" thing,
-- this can unfortunately lead to a resize event and thereafter, 
-- a new call to this function
--
	if (toggles.ntsc) then
		push_ntsc();
	end

	if (INTERX ~= nil) then
		move_image(dstvid, INTERX, INTERY);
		rotate_image(dstvid, INTERANG);
	end
-- all the above changes may have reordered the menu
	gridlemenu_tofront(current_menu);
--	push_ntsc(true);
end

local function match_aspect(sourcew, sourceh, destw, desth)
	local ar = sourcew / sourceh;
	local wr = sourcew / destw;
	local hr = sourceh / desth;

	if (hr > wr) then
		return math.floor(desth * ar), desth;
	else
		return destw, math.floor(destw / ar);
	end
end

--
-- Figure out how much workspace surface we have, 
-- combine that with the current scalemode and apply to source.
-- Returns the final workspace surface
-- 
function gridlemenu_resize_fullscreen(source, init_props)
-- rotations are not allowed for H-Split / 
-- H-Split SBS and V-Split needs separate treatment
	local rotate = nil;
	imagery.cocktail_vid = nil;
	
	if (settings.scalemode == "Rotate 90 CW") then
		rotate = 90;
	elseif (settings.scalemode == "Rotate 90 CCW") then
		rotate = -90;
	end

	local windw = INTERW;
	local windh = INTERH;
	local scalemode = settings.scalemode;
	local cocktailmode = settings.cocktail_mode;

	rotate_image(source, 0);

	local props = init_props;

-- since rotate isn't a toggle flag, assume rotate means rotate + keep aspect
	if (rotate ~= nil) then
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
		local neww, newh = match_aspect(props.width, props.height, windw, windh);
		resize_image(source, neww, newh);

	elseif (scalemode == "Stretch") then
		resize_image(source, windw, windh);
	end

-- some operations overshoot, aspect match the possible stretched source
	props = image_surface_properties(source);
	if (props.width > windw or props.height > windw) then
		local neww, newh = match_aspect(props.width, props.height, windw, windh);
		resize_image(source, neww, newh);
	end

-- rotate / reposition
	props = image_surface_properties(source);
	if (settings.cocktail_mode ~= "Disabled") then
		setup_cocktail(settings.cocktail_mode, source, windw, windh);
	else
		if (rotate ~= nil) then
			rotate_image(source, rotate);
			move_image(source, math.floor(0.5 * (windh - props.width)), 
				math.floor(0.5 * (windw - props.height)) );
		elseif (scalemode ~= "Bezel") then
			move_image(source, math.floor(0.5 * (windw - props.width)), 
				math.floor(0.5 * (windh - props.height)) );
		end
	end
	
	return windw, windh;
end

function gridlemenu_loadshader(basename, dstvid)
	local vsh = nil;
	local fsh = nil;

	local storprops  = image_storage_properties(dstvid);
	local dispprops  = image_surface_properties(dstvid);
	local startprops = image_surface_initial_properties(dstvid);

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

	if (settings.shader_opts) then
		local resshdr = load_shader(vsh, fsh, "fullscreen", settings.shader_opts);

		shader_uniform(resshdr, "output_size",  "ff", 
			PERSIST, dispprops.width,  dispprops.height );

		shader_uniform(resshdr, "input_size",   "ff", 
			PERSIST, startprops.width, startprops.height);

		shader_uniform(resshdr, "storage_size", "ff", 
			PERSIST, storprops.width,  storprops.height );

		image_shader(dstvid, resshdr);
		return resshdr;
	end
end

local function get_saveslist(gametbl)
-- check for existing snapshots (ignore auto and quicksave)
	local saveslist = {};
	local saves = glob_resource("savestates/" .. 
		gametbl.target .. "_" .. gametbl.setname .. "_*", SHARED_RESOURCE);

	for ind, val in ipairs( saves ) do
		if not (string.sub( val, -5, -1 ) == "_auto" or
				string.sub( val, -10, -1 ) == "_quicksave") then

			local prefix = string.sub( val, 
				string.len( gametbl.target ) + 
				string.len(gametbl.setname) + 3 );

			table.insert(saveslist, prefix);
		end
	end

	return saveslist;
end

local function grab_shaderconf(basename)
	local vdef, vcond = parse_shader(
		"shaders/fullscreen/" .. basename .. ".vShader");

	local fdef, fcond = parse_shader(
		"shaders/fullscreen/" .. basename .. ".fShader");

	local resdef = {};
	local rescond = {};

-- remap the tables into hash/LUT, doesn't separate namespaces in v/f shaders
	for ind, val in ipairs( vdef )  do resdef[val]  = true; end
	for ind, val in ipairs( fdef )  do resdef[val]  = true; end
	for ind, val in ipairs( vcond ) do rescond[val] = true; end
	for ind, val in ipairs( fcond ) do rescond[val] = true; end

	return resdef, rescond;
end

local function load_savestate(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	internal_statectl(label, false);
end

local function save_savestate(label, store)
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	internal_statectl(label, true);
end

local function build_savemenu()
	local reslbls = {};
	local resptrs = {};
	local saveslist = get_saveslist( current_game );
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
		
		local osdkbd_input = function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdsavekbd);

			if (complete) then
				osdsavekbd:destroy();
				osdsavekbd = nil;

				if (resstr ~= nil and string.len(resstr) > 0) then
					internal_statectl(resstr, true);
					spawn_warning("state saved as (" .. resstr .. ")");
				end

				dispatch_pop();
				settings.iodispatch["MENU_ESCAPE"]();
				settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
			end
		end
	
		dispatch_push({}, "(internal) osd keyboard", osdkbd_input, -1);
	end

-- just grab the last num found, increment by one and use as prefix
	resptrs["(New)"] = function(label, store)
		settings.iodispatch["MENU_ESCAPE"]();
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		spawn_warning("state saved as (" .. tostring( highind + 1) .. ")");
		internal_statectl(highind + 1, true);
	end
	
	return reslbls, resptrs, {};
end

function gen_keymap_name( gamespecific )
	local reslbl = "keymaps/" .. current_game.target;

	if (gamespecific) then
		reslbl = reslbl .. "_" .. current_game.setname;
	end

	reslbl = reslbl .. ".lua";
	return reslbl;
end

-- quick heuristic, look for a game-specific, 
-- then target specific, else just use global
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
	local saveslist = get_saveslist( current_game );

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

	current_menu:invalidate();
	current_menu:redraw();
end

local function configure_players(dstname)
	if (settings.privileged ~= true) then
		return;
	end
	
	keyconfig_oldfname = keyconfig.keyfile;
	keyconfig.keyfile = dstname;
	local gametbl = retrohelper_lookup(settings.internal_ident);
-- NOTE: could show background / helper image here as well

	if (gametbl) then
		keyconfig:reconfigure_players(gametbl.buttons, gametbl.axes, gametbl.ident);
	else
		keyconfig:reconfigure_players();
	end
	
	kbd_repeat(0);

	dispatch_push({}, "reconfigure players (" 
		.. tostring(dstname) ..")", function(iotbl)
		if (keyconfig:input(iotbl) == true) then
			dispatch_pop();
			
      if (gametbl) then
				gametbl:destroy();
			end
			
			keyconfig.keyfile = keyconfig_oldfname;
    end
	end, 0);
end

local function add_gamelbls( lbltbl, ptrtbl )
	local captbl = settings.capabilities;

	if (captbl.snapshot) then
		if ( (# get_saveslist( current_game )) > 0 ) then
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

-- fixme; generate menus for all the different kinds of
-- "frame-stepping" options we'd like to have
-- (auto, draw every n frames, rewind n frames, ...)

-- fixme; generate menus for each input port with 
-- (gamepad, mouse, keyboard, ...) sort of options
-- in order to plug into proper libretro devices ..
--	if ( captbl.ports and captbl.ports > 0) then
--		local numslots = captbl.ports > keyconfig.table.player_count 
--		and keyconfig.table.player_count or captbl.ports;
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

			ptrs["Set (Game) Keyconfig"]   = function() 
        settings.iodispatch["MENU_ESCAPE"]();
        configure_players( gen_keymap_name( true ) );  
      end

			ptrs["Set (Target) Keyconfig"] = function() 
        settings.iodispatch["MENU_ESCAPE"]();
        configure_players( gen_keymap_name( false ) ); 
      end

			if ( resource( gen_keymap_name(true)) ) then
				table.insert(lbls, "Drop (Game) Keyconfig");
				
				ptrs["Drop (Game) Keyconfig"] = function()
					settings.iodispatch["MENU_ESCAPE"]();
					settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
					zap_resource( gen_keymap_name( true ) );
					set_internal_keymap();
				end
			end

			if ( resource( gen_keymap_name(false)) ) then
				table.insert(lbls, "Drop (Target) Keyconfig");
				ptrs["Drop (Target) Keyconfig"] = function()
					settings.iodispatch["MENU_ESCAPE"]();
					settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
					zap_resource( gen_keymap_name( false ) );
					set_internal_keymap();
				end
			end

			menu_spawnmenu( lbls, ptrs, {} );
		end
	end

	advtbl = { "Toggle Debugmode" };
	advptrs = {};

	local function aligntrig()
		settings.iodispatch["MENU_ESCAPE"]();
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
		target_framemode(internal_vid, skipremap[settings.skip_mode], 
			settings.frame_align, 
			settings.preaud, settings.jitterstep, settings.jitterxfer);
	end

	add_submenu(advtbl, advptrs, "Frame Alignment...",
		"frame_align", gen_num_menu("frame_align", -1,  2, 6,  aligntrig));
	add_submenu(advtbl, advptrs, "Skip Method...", 
		"skip_mode",   gen_tbl_menu("skip_mode", skiptbl, aligntrig, true));

	add_submenu(advtbl, advptrs, "Pre-audio (frames)...", "preaud",
		gen_num_menu("preaud",       0,  1, 4,  aligntrig));
	
	if (DEBUGLEVEL > 0) then
		add_submenu(advtbl, advptrs, "Emulation jitter...", "jitterstep",
			gen_num_menu("jitterstep",  -28, 4, 14, aligntrig));
		add_submenu(advtbl, advptrs, "Transfer jitter...", "jitterxfer",
			gen_num_menu("jitterxfer",  -28, 4, 14, aligntrig));
	end

	advptrs["Toggle Debugmode"] = function()
		settings.graph_mode = settings.graph_mode == 1 and 0 or 1;
		target_graphmode(internal_vid, settings.graph_mode);
		settings.iodispatch["MENU_ESCAPE"]();
		settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	end

	table.insert(lbltbl, "Advanced...");
	ptrtbl[ "Advanced..." ] = function(label, store)
		menu_spawnmenu(advtbl, advptrs, {});
	end

	local coretbl = {}; 
	local coreptr = {};
	
	local update_corearg = function(k, v)
		settings.coreargs[k].curv = v;
		target_coreopt(internal_vid, settings.coreargs[k].num,
			settings.coreargs[k].curv);
	
		settings.coreargs_dirty = true;
		settings.iodispatch["MENU_ESCAPE"]();
	end

-- map the core options as menus, call update_corearg on
-- trigger, which will try to update the corearg (though
-- that might not always work), this table is also 
-- flushed / stored on close.
	for k,v in pairs(settings.coreargs) do
		table.insert(coretbl, k);
		coreptr[k] = function()
			local argptr = {};

			for ind, av in ipairs(v.args) do
				argptr[av] = function(v)
					update_corearg(k, v);
				end
			end

			local defs = {};
			defs[v.curv] = settings.colourtable.notice_fontstr;
			menu_spawnmenu(v.args, argptr, defs); 
		end
	end

	table.sort(coretbl);

	if (#coretbl > 0) then
		table.insert(lbltbl, "Core Options...");
		ptrtbl["Core Options..."] = function()
			menu_spawnmenu(coretbl, coreptr, {});
		end
	end

	if ( captbl.reset ) then
		table.insert(lbltbl, "Reset Game");
			ptrtbl["Reset Game"] = function(label, store)
				valcbs = {};
				valcbs["YES"] = function()
					reset_target(internal_vid);
				end

				valcbs["NO"]  = function()	end
				dialog_option("Resetting emulation, OK?", {"YES", "NO"}, true, 
					valcbs, function() 
						settings.iodispatch["MENU_ESCAPE"](nil, nil, true); 
					end );
			end
		end

	return true;
end

function screenshot()
	local lblbase = "screenshots/" .. 
		current_game.target .. "_" .. current_game.setname;

	local ofs = 1;

-- only add sequence number if we already have a screenshot for the game
	if (resource( lblbase .. ".png" ) ) then
		while resource(lblbase .. "_" .. tostring(ofs) .. ".png") do
			ofs = ofs + 1;
		end
		save_screenshot(lblbase .. "_" .. tostring(ofs) .. ".png", 1);
	else
		save_screenshot(lblbase .. ".png", 1);
	end
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
	local lblbase = "movies/" .. current_game.setname;
	local dst = lblbase .. ".mkv";

	local ofs = 1;

-- only add sequence number if we already have a recording for the game
	while resource(dst) do
		dst = lblbase .. "_" .. tostring(ofs) .. ".mkv";
		ofs = ofs + 1;
	end

-- create an instance of this image to detach and record
	local lvid = instance_image( internal_vid );
	image_set_txcos_default(lvid, settings.internal_mirror);
	
-- set it to the top left of the screen
	image_mask_clear(lvid, MASK_POSITION);
	image_mask_clear(lvid, MASK_OPACITY);

	move_image(lvid, 0, 0);

-- allocate intermediate storage
	local dstvid = fill_surface(width, height, 0, 0, 0, width, height);
	resize_image(lvid, width, height);
	show_image(lvid);

	define_recordtarget(dstvid, dst, args, {lvid}, {internal_aid}, 
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, function(source, status)
		end
	);

	imagery.record_target = dstvid;
	imagery.record_indicator = load_image("images/icons/record.png");

	move_image(imagery.record_indicator);
	image_transform_cycle(imagery.record_indicator, 1);
	resize_image(imagery.record_indicator, 
		math.floor(VRESW * 0.05), math.floor(VRESW * 0.05));
	blend_image(imagery.record_indicator, 0.5, 128);
	blend_image(imagery.record_indicator, 0.0, 128);
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

-- Don't implement save / favorite for these ones without serious 
-- long-term testing As we have no automated heuristics (which would mean 
-- creating reference images, doing an FBO, read back,
-- compare output with reference and determine if it's "stable" or not) 
-- and GPU failures are still very much treated like a full on crash.
displaymodelist = {}; -- {"Custom Shaders..."};

local function add_displaymodeptr(list, ptrs, key, label, togglecb)
	local ctxmenus = {CRT = true, 
		Overlay = false, Backdrop = false, Filter = true, 
		NTSC = true, Glow = true, Trails = true, Upscaler = true};

	table.insert(list, label);

	ptrs[label] = function(label, save)
	settings.internal_toggles[key] = not settings.internal_toggles[key];

	current_menu.formats[label] = nil;
	local fz = settings.colourtable.font_size;
	local iconlbl = string.format("\\P%d,%d,%s,", 
		fz, fz, "images/icons/magnify.png");

	if (ctxmenus[label]) then
		current_menu.formats[label] = iconlbl;
	end

	current_menu.formats[label] = string.format("%s%s", 
		ctxmenus[label] and iconlbl or "",
		settings.internal_toggles[key] and settings.colourtable.notice_fontstr or 
		settings.colourtable.data_fontstr);

	togglecb();
	current_menu:invalidate();
	current_menu:redraw();
	gridlemenu_tofront(current_menu);
	end
end

local function updatetrigger()
	gridlemenu_rebuilddisplay(settings.internal_toggles);
end

add_displaymodeptr(displaymodelist, displaymodeptrs, "upscaler",  "Upscaler",  updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "glow",      "Glow",      updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "trails",    "Trails",    updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "crt",       "CRT",       updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "ntsc",      "NTSC",      push_ntsc);
add_displaymodeptr(displaymodelist, displaymodeptrs, "overlay",   "Overlay",   updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "backdrop",  "Backdrop",  updatetrigger );
add_displaymodeptr(displaymodelist, displaymodeptrs, "antialias", "Antialias", updatetrigger );

local glowlbls       = {};
local glowptrs       = {};
local traillbls      = {};
local trailptrs      = {};
local crtmenulbls    = {};
local crtmenuptrs    = {};
local ntscmenulbls   = {};
local ntscmenuptrs   = {};
local filtermenulbls = {};
local filtermenuptrs = {};
local scalerlbls     = {};
local scalerptrs     = {};
local xbrlbls = {};
local xbrptrs = {};

add_submenu(ntscmenulbls, ntscmenuptrs, "Artifacts...",  "ntsc_artifacts",  gen_tbl_menu("ntsc_artifacts",  {-1, -0.5, -0.2, 0}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Bleed...",      "ntsc_bleed",      gen_tbl_menu("ntsc_bleed",      {-1, -0.5, -0.2, 0}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Fringing...",   "ntsc_fringing",   gen_tbl_menu("ntsc_fringing",   {-1, 0, 1}, push_ntsc))
add_submenu(ntscmenulbls, ntscmenuptrs, "Hue...",        "ntsc_hue",        gen_tbl_menu("ntsc_hue",        {-0.1, -0.05, 0, 0.05, 0.1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Saturation...", "ntsc_saturation", gen_tbl_menu("ntsc_saturation", {-1, -0.5, 0, 0.5, 1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Contrast...",   "ntsc_contrast",   gen_tbl_menu("ntsc_contrast",   {-0.5, 0, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Brightness...", "ntsc_brightness", gen_tbl_menu("ntsc_brightness", {-0.5, -0.25, 0, 0.25, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Gamma...",      "ntsc_gamma",      gen_tbl_menu("ntsc_gamma",      {-0.5, -0.2, 0, 0.2, 0.5}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Sharpness...",  "ntsc_sharpness",  gen_tbl_menu("ntsc_sharpness",  {-1, 0, 1}, push_ntsc));
add_submenu(ntscmenulbls, ntscmenuptrs, "Resolution...", "ntsc_resolution", gen_tbl_menu("ntsc_resolution", {0, 0.2, 0.5, 0.7}, push_ntsc));

add_submenu(displaymodelist, displaymodeptrs, "Filtering...",         "imagefilter",       gen_tbl_menu("imagefilter", {"None", "Linear", "Bilinear"}, updatetrigger, true));

add_submenu(glowlbls, glowptrs, "Line Width...",         "vector_linew",      gen_num_menu("vector_linew",        1, 0.5,  6, updatetrigger));
add_submenu(glowlbls, glowptrs, "Point Size...",         "vector_pointsz",    gen_num_menu("vector_pointsz",      1, 0.5,  6, updatetrigger));
add_submenu(glowlbls, glowptrs, "Blur Scale (X)...",     "vector_hblurscale", gen_num_menu("vector_hblurscale", 0.2, 0.1,  9, updatetrigger));
add_submenu(glowlbls, glowptrs, "Blur Scale (Y)...",     "vector_vblurscale", gen_num_menu("vector_vblurscale", 0.2, 0.1,  9, updatetrigger));
add_submenu(glowlbls, glowptrs, "Vertical Bias...",      "vector_vbias",      gen_num_menu("vector_vbias",      0.6, 0.1, 13, updatetrigger));
add_submenu(glowlbls, glowptrs, "Horizontal Bias...",    "vector_hbias",      gen_num_menu("vector_hbias",      0.6, 0.1, 13, updatetrigger));
add_submenu(glowlbls, glowptrs, "Vertical Offset...",    "vector_vblurofs",   gen_num_menu("vector_vblurofs",    -6,   1, 13, updatetrigger));
add_submenu(glowlbls, glowptrs, "Horizontal Offset...",  "vector_hblurofs",   gen_num_menu("vector_hblurofs",    -6,   1, 13, updatetrigger));

add_submenu(traillbls, trailptrs, "Glow Trails...",       "vector_glowtrails", gen_num_menu("vector_glowtrails",   1,   1,  8, updatetrigger));
add_submenu(traillbls, trailptrs, "Delta Match...",       "vector_deltamethod",gen_tbl_menu("vector_deltamethod", {"Off", "On", "Delta Only"}, updatetrigger, true));
add_submenu(traillbls, trailptrs, "Trail Falloff...",     "vector_trailfall",  gen_num_menu("vector_trailfall",   -4,   1,  9, updatetrigger));
add_submenu(traillbls, trailptrs, "Trail Step...",        "vector_trailstep",  gen_tbl_menu("vector_trailstep",   {-4,-3,-2,-1,1,2,3,4}, updatetrigger, false));

add_submenu(crtmenulbls, crtmenuptrs, "CRT Gamma...",             "crt_gamma",       gen_num_menu("crt_gamma",       1.8, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Monitor Gamma...",         "crt_mongamma",    gen_num_menu("crt_mongamma",    1.8, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Curvature Radius...",      "crt_curvrad",     gen_num_menu("crt_curvrad",     1.4, 0.1 , 8, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Distance...",              "crt_distance",    gen_num_menu("crt_distance",    1.0, 0.2 , 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Overscan (Horizontal)...", "crt_hoverscan",   gen_num_menu("crt_hoverscan",   1.0, 0.02, 5, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Overscan (Vertical)...",   "crt_voverscan",   gen_num_menu("crt_voverscan",   1.0, 0.02, 5, updatetrigger));

add_submenu(crtmenulbls, crtmenuptrs, "Aspect (Horizontal)...",   "crt_haspect",     gen_tbl_menu("crt_haspect",     {0.75, 1.0, 1.25}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Aspect (Vertical)...",     "crt_vaspect",     gen_tbl_menu("crt_vaspect",     {0.75, 1.0, 1.25}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Corner Size...",           "crt_cornersz",    gen_tbl_menu("crt_cornersz",    {0.001, 0.01, 0.03, 0.05, 0.07, .1}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Corner Smooth...",         "crt_cornersmooth",gen_tbl_menu("crt_cornersmooth",{80.0, 1000.0, 1500.0}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Tilt (Horizontal)...",     "crt_tilth",       gen_tbl_menu("crt_tilth",       {-0.15, -0.05, 0.01, 0.05, 0.15}, updatetrigger));
add_submenu(crtmenulbls, crtmenuptrs, "Tilt (Vertical)...",       "crt_tiltv",       gen_tbl_menu("crt_tiltv",       {-0.15, -0.05, 0.01, 0.05, 0.15}, updatetrigger));

add_submenu(scalerlbls, scalerptrs, "Factor...", "upscale_factor", gen_tbl_menu("upscale_factor", {2, 3, 4, 5}, updatetrigger));
add_submenu(scalerlbls, scalerptrs, "Delta Value (xbr)...", "upscale_delta", gen_num_menu("upscale_delta", 0.1, 0.1, 6, updatetrigger));
add_submenu(scalerlbls, scalerptrs, "Method...", "upscale_method", gen_tbl_menu("upscale_method", {"sabr", "xbr-rounded", "xbr-semi-rounded", "xbr-square", "xbr-l3"}, updatetrigger, true));

local function recdim()
	local props  = image_surface_initial_properties(internal_vid);
	local width  = props.width;
	local height = props.height;

	if (settings.record_res < props.height) then
		width = ( width / height ) * settings.record_res;
	end

-- need to be evenly divisible
	width  = math.floor(width);
	height = math.floor(height);
	width  = (width % 2  == 0) and width  or width  + 1;
	height = (height % 2 == 0) and height or height + 1;

	return width, height;
end

-- Special treatment for CRT toggle lables, and Upscaler toggle labels
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

	current_menu.formats[label] = settings[dstkey] 
		and settings.colourtable.notice_fontstr or nil;

	current_menu:invalidate();
	current_menu:redraw();

	gridlemenu_rebuilddisplay(settings.internal_toggles);
end

local function flip_scalertog(label, save)
	local dstkey = "upscale_ddt";
	settings[dstkey] = not settings[dstkey];

	if (save) then
		store_key(dstkey, settings[dstkey] and 1 or 0);
		play_audio(soundmap["MENU_FAVORITE"]);
	else
		play_audio(soundmap["MENU_SELECT"]);
	end

	current_menu.formats[label] = settings[dstkey] 
		and settings.colourtable.notice_fontstr or nil;

	current_menu:invalidate();
	current_menu:redraw();

	gridlemenu_rebuilddisplay(settings.internal_toggles);
end

table.insert(scalerlbls, "DDT");
scalerptrs["DDT"] = flip_scalertog;

table.insert(crtmenulbls, "Curvature");
table.insert(crtmenulbls, "Gaussian Profile");
table.insert(crtmenulbls, "Oversample");
table.insert(crtmenulbls, "Linear Processing");
crtmenuptrs["Curvature"] = flip_crttog;
crtmenuptrs["Gaussian Profile"] = flip_crttog;
crtmenuptrs["Oversample"] = flip_crttog;
crtmenuptrs["Linear Processing"] = flip_crttog;

recordlist = {};
recordptrs = {};

add_submenu(recordlist, recordptrs, "Format...", "record_format", gen_tbl_menu("record_format", codeclbls, function() end, true));
add_submenu(recordlist, recordptrs, "Framerate...", "record_fps", gen_tbl_menu("record_fps", {12, 24, 25, 30, 50, 60}, function() end));
add_submenu(recordlist, recordptrs, "Max Vertical Resolution...", "record_res", gen_tbl_menu("record_res", {720, 576, 480, 360, 288, 240}, function() end));
add_submenu(recordlist, recordptrs, "Quality...", "record_qual", gen_tbl_menu("record_qual", {2, 4, 6, 8, 10}, function() end));

local streammenu = {};
local streamptrs = {};

streamptrs["Define Stream..."] = function(label, store)
		local resstr = nil;
		local opts = {};

		opts.case_insensitive = false;
		opts.prefix = "rtmp://";
		opts.startstr = settings.stream_url;

-- quick hack to make it slightly easier to 
-- enter "big and nasty justin.tv kind" keys
		if (settings.stream_url == "rtmp://" and resource("stream.key")) then
			if (open_rawresource("stream.key")) then
				local line = read_rawresource();
				if (line ~= nil and string.len(line) > 0) then
					opts.startstr = line;
				end
				close_rawresource();
			end
		end

		local osdsavekbd = osdkbd_create( osdkbd_extended_table(), opts );
		osdsavekbd:show();

-- do this here so we have access to the namespace where osdsavekbd exists
		dispatch_push({}, "osdkbd (streaming)", function(iotbl)
			complete, resstr = osdkbd_inputfun(iotbl, osdsavekbd);
			if (complete) then
				osdsavekbd:destroy();
				osdsavekbd = nil;
				dispatch_pop();
				if (resstr ~= nil and string.len(resstr) > 0) then
					settings.stream_url = resstr;
					store_key("stream_url", resstr);
				end
			end
		end
		, -1);
end

-- only if destination has been set up
table.insert(streammenu, "Define Stream...");
table.insert(streammenu, "Start Streaming");
local tmpfmt = {};
tmpfmt["Start Streaming"] = "\\b" .. settings.colourtable.notice_fontstr;
add_submenu(recordlist, recordptrs, "Streaming...", 
	"record_stream", streammenu, streamptrs, tmpfmt);
table.insert(recordlist, "Start Recording");

streamptrs["Start Streaming"] = function()
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);
	settings.iodispatch["MENU_ESCAPE"](nil, nil, true);

	local width, height = recdim();
	local recstr = 
		"libvorbis:vcodec=libx264:container=stream:acodec=libmp3lame:streamdst=" 
		.. string.gsub(settings.stream_url and
			settings.stream_url or "", ":", "\t");

	recstr = recstr .. ":fps=" .. tostring(settings.record_fps) 
		.. ":apreset=" .. tostring(settings.record_qual) .. ":vpreset=" 
		.. tostring(settings.record_qual);

	spawn_warning("Streaming to: " .. string.gsub(settings.stream_url 
		and settings.stream_url or "", "\\", "\\\\"));

	enable_record(width, height, recstr);
end

recordptrs["Start Recording"] = function()
	settings.iodispatch["MENU_ESCAPE"]();
	settings.iodispatch["MENU_ESCAPE"]();
	local width, height = recdim();

-- compile a string with all the settings- goodness
	local recstr = codectbl[settings.record_format];
	recstr = recstr .. ":fps=" .. tostring(settings.record_fps) 
		.. ":apreset=" .. tostring(settings.record_qual) .. 
			":vpreset=" .. tostring(settings.record_qual);

	enable_record(width, height, recstr);
end

function gridlemenu_internal(target_vid, contextlbls, settingslbls)
	if (not (contextlbls or settingslbls)) then return; end

	local menulbls = {};
	local ptrs = {};

	if (contextlbls) then
		add_gamelbls(menulbls, ptrs);
		if (#menulbls == 0 and not settingslbls) then return; end
	end

	local imenu = {};
	imenu["CONTEXT"] = function(iotbl)
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

		elseif (selectlbl == "Upscaler") then
			menu_spawnmenu(scalerlbls, scalerptrs, {});

		elseif (selectlbl == "CRT") then
			fmts = {};

			if (settings.crt_gaussian) then 
				fmts["Gaussian Profile"]  = settings.colourtable.notice_fontstr; 
			end

			if (settings.crt_linearproc) then 
				fmts["Linear Processing"] = settings.colourtable.notice_fontstr; 
			end

			if (settings.crt_curvature)  then 
				fmts["Curvature"] = settings.colourtable.notice_fontstr; 
			end

			if (settings.crt_oversample) then 
				fmts["Oversample"] = settings.colourtable.notice_fontstr; 
			end

			menu_spawnmenu(crtmenulbls, crtmenuptrs, fmts);

		elseif (selectlbl == "Trails") then
			menu_spawnmenu(traillbls, trailptrs, {});
		elseif (selectlbl == "Glow") then
			menu_spawnmenu(glowlbls, glowptrs, {});
		elseif (selectlbl == "NTSC") then
			menu_spawnmenu(ntscmenulbls, ntscmenuptrs, {});
		end
	end

	imenu["MENU_ESCAPE"] = function(iotbl, restbl, silent)
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
			dispatch_pop();
		end
	end

if (#menulbls > 0 and settingslbls) then
		table.insert(menulbls, "---" );
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
		local iconlbl = " \\P" .. settings.colourtable.font_size .. "," .. settings.colourtable.font_size .. ",images/icons/magnify.png,";

		def["CRT"      ] = iconlbl .. (settings.internal_toggles.crt    and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def["NTSC"     ] = iconlbl .. (settings.internal_toggles.ntsc   and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def["Trails"   ] = iconlbl .. (settings.internal_toggles.trails and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def["Glow"     ] = iconlbl .. (settings.internal_toggles.glow   and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def["Upscaler" ] = iconlbl .. (settings.internal_toggles.upscaler and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr);
		def["Overlay"  ] = settings.internal_toggles.overlay  and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr;
		def["Backdrop" ] = settings.internal_toggles.backdrop and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr
		def["Antialias"] = settings.internal_toggles.antialias and settings.colourtable.notice_fontstr or settings.colourtable.data_fontstr;

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
		def[ tostring(settings.internal_again) ] = 
			settings.colourtable.notice_fontstr;

		if (get_key("internal_again")) then
			def[ get_key("internal_again") ] = settings.colourtable.alert_fontstr;
		end

		menu_spawnmenu( audiogainlist, audiogainptrs, def );
	end

-- trickier than expected, as we don't want the game to 
-- progress and we don't want any UI elements involved */
	current_menu.ptrs["Screenshot"] = function()
		settings.iodispatch["MENU_ESCAPE"]();
		local tmpclock = gridle_clock_pulse;

		tmpclock_c = 22; -- listview has a fixed 20tick expire
		escape_locked = true;
		suspend_target( target_vid );

-- replace the current timing function with one that 
-- only ticks down and then takes a screenshot
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
		def[ tostring(settings.cocktail_mode) ] 
			= settings.colourtable.notice_fontstr;

		if (get_key("cocktail_mode")) then
			def[ get_key("cocktail_mode") ] = settings.colourtable.alert_fontstr;
		end

		menu_spawnmenu( cocktaillist, cocktailptrs, def);
	end

	current_menu.ptrs["Record..."] = function()
		local def = {};
		def["Start Recording"] = [[\b]] .. settings.colourtable.notice_fontstr;
		menu_spawnmenu( recordlist, recordptrs, def);
	end

	menu_defaultdispatch(imenu);
	dispatch_push(imenu, "internal_shared", nil, -1);
	
	settings.context_menu = nil;

	current_menu:show();
	suspend_target(internal_vid);
	play_audio(soundmap["MENU_TOGGLE"]);
	move_image(current_menu.anchor, 10, 
		math.floor(VRESH * 0.1), settings.fadedelay);
end

function gridle_load_internal_extras(restbl, tgt)
	if (restbl) then
		if (restbl.bezels and restbl.bezels[1]) then 
			imagery.bezel = load_image_asynch(restbl.bezels[1]);
			image_tracetag(imagery.bezel, "bezel");
		elseif (resource("bezels/" .. tgt .. ".png")) then
			imagery.bezel = load_image_asynch("bezels/" .. tgt .. ".png");
			image_tracetag(imagery.bezel, "bezel");
		end
			
		if (restbl.overlays and restbl.overlays[1]) then
			imagery.overlay = load_image_asynch(restbl.overlays[1]); 
			image_mask_clear(imagery.overlay, MASK_LIVING);
			image_tracetag(imagery.overlay, "overlay");
		end 
		if (restbl.backdrops and restbl.backdrops[1]) then
			imagery.backdrop = load_image_asynch(restbl.backdrops[1]);
			image_mask_clear(imagery.backdrop, MASK_LIVING);
			image_tracetag(imagery.backdrop, "backdrop");
		end
	end
end

function gridle_delete_internal_extras()
	if (valid_vid(imagery.backdrop)) then 
		blend_image(imagery.backdrop, 0.0, settings.transitiondelay);
		expire_image(imagery.backdrop, settings.transitiondelay);
		imagery.backdrop = BADID;
	end

	if (valid_vid(imagery.overlay)) then
		blend_image(imagery.overlay, 0.0, settings.transitiondelay);
		expire_image(imagery.overlay, settings.transitiondelay);
		imagery.overlay = BADID;
	end
		
	if (valid_vid(imagery.bezel)) then
		blend_image(imagery.bezel, 0.0, settings.transitiondelay);
		expire_image(imagery.bezel, settings.transitiondelay);
		imagery.bezel = BADID;
	end
		
	if (valid_vid(imagery.cocktail_vid)) then
		image_mask_clear(imagery.cocktail_vid, MASK_POSITION);
		expire_image(imagery.cocktail_vid, settings.transitiondelay);
		resize_image(imagery.cocktail_vid, 1, 1, settings.transitiondelay);
		blend_image(imagery.cocktail_vid, 0.0, settings.transitiondelay);
		move_image(imagery.cocktail_vid, 
			INTERW * 0.5, INTERH * 0.5, settings.transitiondelay);

		imagery.cocktail_vid = BADID;
	end
end
	
