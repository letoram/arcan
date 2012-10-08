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

-- map resource-finder properties with their respective name in the editor dialog
local remaptbl = {};
remaptbl["bezel"]       = "bezels";
remaptbl["screenshot"]  = "screenshots";
remaptbl["marquee"]     = "marquees";
remaptbl["overlay"]     = "overlay";
remaptbl["bezel"]       = "bezels";
remaptbl["backdrop"]    = "backdrops";
remaptbl["movie"]       = "movies";
remaptbl["controlpanel"]= "controlpanels";
remaptbl["boxart"]      = "boxart";

customview.in_config = true;

-- list of the currently allowed modes (size, position, opacity, orientation)
customview.position_modes  = {"position", "size", "opacity", "orientation"};
customview.position_marker = 1;
customview.orderind = 1;
customview.temporary = {};

helplbls = {};
helplbls["position"] = {
	"Position",
	"SWITCH_VIEW to switch mode)",
	"(SELECT to save)",
	"(ESCAPE to cancel)"
};

helplbls["size"] = {
	"Scale",
};

helplbls["opacity"] = {
	"Blend (LEFT/RIGHT)",
	"Z-Order (UP/DOWN)"
};

helplbls["orientation"] = {
	"Rotate(45) (UP/DOWN)",
	"Rotate(inc/dec) (LEFT/RIGHT)"
};

-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end

function cascade_visibility(menu, val)
	if (menu.parent) then
		cascade_visibility(menu.parent, val);
	end

	if (val > 0.9) then
		if (infowin) then
			infowin:destroy();
			customview.position_marker = 1;
			infowin = nil;
		end
	end
	
	blend_image(menu.anchor, val);
	menu:push_to_front();
end

local function update_infowin()
	if (infowin) then
		infowin:destroy();
	end

-- use a quadrant away from the current item
	infowin = listview_create( helplbls[customview.position_modes[customview.position_marker]], VRESW / 2, VRESH / 2 );
	local xpos = (customview.ci.x < VRESW / 2) and (VRESW / 2) or 0;
	local ypos = (customview.ci.y < VRESH / 2) and (VRESH / 2) or 0;
	infowin:show();
	move_image(infowin.anchor, xpos, ypos);
end

local function position_toggle()
-- don't allow any other mode to be used except position until we have an upper left boundary
	customview.position_marker = (customview.position_marker + 1 > #customview.position_modes) and 1 or (customview.position_marker + 1);
	update_infowin();
end

local function update_object(imgvid)
	resize_image(imgvid, customview.ci.width, customview.ci.height);
	move_image(imgvid, customview.ci.x, customview.ci.y);
	blend_image(imgvid, customview.ci.opa);
	rotate_image(imgvid, customview.ci.ang);
	order_image(imgvid, customview.ci.zv);

	if (customview.ci.tiled) then
		local props = image_surface_initial_properties(imgvid);
		image_scale_txcos(imgvid, customview.ci.width / props.width, customview.ci.height / props.height);
	end
	
end

local function update_bgshdr()
	local dst = nil;
	
	if (customview.in_config) then
		for ind, val in ipairs(customview.itemlist) do
			if (val.kind == "background") then
				dst = val.vid;
				val.shader = customview.bgshader_label;
				break
			end
		end
	else
		dst = customview.background;
	end
	
	if (dst) then
		local props = image_surface_properties(dst);
		shader_uniform(customview.bgshader, "display", "ff", PERSIST, props.width, props.height);
		image_shader(dst, customview.bgshader);
	end
end

local function cursor_step(vid, x, y)
	customview.ci.width  = customview.ci.width + x;
	customview.ci.height = customview.ci.height + y;

	if (customview.ci.width <= 0)  then customview.ci.width  = 1; end
	if (customview.ci.height <= 0) then customview.ci.height = 1; end
	
	update_object(vid);
end

local function cursor_slide(vid, x, y)
	customview.ci.x = customview.ci.x + x;
	customview.ci.y = customview.ci.y + y;
	
	update_object(vid);
end

local function orientation_rotate(vid, ang, align)
	customview.ci.ang = customview.ci.ang + ang;

	if (align) then
		local rest = customview.ci.ang % 45;
		customview.ci.ang = (rest > 22.5) and (customview.ci.ang - rest) or (customview.ci.ang + rest);
	end
	
	update_object(vid);
end

local function order_increment(vid, val)
	customview.ci.zv = customview.ci.zv + val;
	if (customview.ci.zv < 1) then customview.ci.zv = 1; end
	if (customview.ci.zv >= customview.orderind) then customview.ci.zv = customview.orderind - 1; end
	
	update_object(vid);
end

local function opacity_increment(vid, byval)
	customview.ci.opa = customview.ci.opa + byval;
	
	if (customview.ci.opa < 0.0) then customview.ci.opa = 0.0; end
	if (customview.ci.opa > 1.0) then customview.ci.opa = 1.0; end
	
	update_object(vid);
end

customview.position_item = function(vid, trigger )
-- as the step size is rather small, enable keyrepeat (won't help for game controllers though,
-- would need state tracking and hook to the clock 
	kbd_repeat(20);
	update_object(vid);
	cascade_visibility(current_menu, 0.0);
	
	position_dispatch = settings.iodispatch;
	settings.iodispatch = {};

	settings.iodispatch["MENU_LEFT"]   = function()
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "size")        then cursor_step(vid, grid_stepx * -1, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid,-2, false);
		elseif (lbl == "opacity")     then opacity_increment(vid, 0.1);
		elseif (lbl == "position")    then cursor_slide(vid, grid_stepx * -1, 0); end
	end
	
	settings.iodispatch["MENU_RIGHT"]  = function() 
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "size")        then cursor_step(vid,grid_stepx, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid, 2, false);
		elseif (lbl == "opacity")     then opacity_increment(vid, -0.1);
		elseif (lbl == "position")    then cursor_slide(vid, grid_stepx, 0); end
	end

	settings.iodispatch["MENU_UP"]     = function()
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "size")        then cursor_step(vid,0, grid_stepy * -1);
		elseif (lbl == "orientation") then orientation_rotate(vid, -45, true);
		elseif (lbl == "opacity")     then order_increment(vid,1); 
		elseif (lbl == "position")    then cursor_slide(vid, 0, grid_stepy * -1); end
	end
	
	settings.iodispatch["MENU_DOWN"]   = function() 
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "size")        then cursor_step(vid,0, grid_stepy);
		elseif (lbl == "orientation") then orientation_rotate(vid, 45, true);
		elseif (lbl == "opacity")     then order_increment(vid,-1); 
		elseif (lbl == "position")    then cursor_slide(vid, 0, grid_stepy); end 
	end
	
	settings.iodispatch["MENU_ESCAPE"] = function() trigger(false, vid); end
	settings.iodispatch["SWITCH_VIEW"] = function() position_toggle();   end
	settings.iodispatch["MENU_SELECT"] = function() trigger(true, vid);  end
	
	update_infowin();
end

customview.new_item = function(vid, dstgroup, dstkey)
	local props = image_surface_properties(vid);

	customview.ci = {};
	customview.ci.width = (props.width  > VRESW * 0.5) and VRESW * 0.5 or props.width;
	customview.ci.height= (props.height > VRESH * 0.5) and VRESH * 0.5 or props.height;
	customview.ci.x     = 0.5 * (VRESW - customview.ci.width);
	customview.ci.y     = 0.5 * (VRESH - customview.ci.height);
	customview.ci.opa   = 1.0;
	customview.ci.ang   = 0;
	customview.ci.kind  = dstgroup;
	customview.ci.res   = dstkey;
	
	customview.ci.zv    = customview.orderind;
	customview.orderind = customview.orderind + 1;
end

local function to_menu()
	customview.ci = nil;
	settings.iodispatch = position_dispatch;
	settings.iodispatch["MENU_ESCAPE"]("", false, false);
	cascade_visibility(current_menu, 1.0);
end

local function save_item(state, vid)
	if (state) then
		customview.ci.vid = vid;
		table.insert(customview.itemlist, customview.ci);
	else
		delete_image(vid);
	end

	to_menu();
end

local function save_item_bg(state, vid)
	if (state == false) then
		delete_image(vid);
		to_menu();
		return;
	end
	
	local found = false;
	customview.ci.vid = vid;
	
-- background and navigator are unique, thus replace old one.
	for ind, val in ipairs(customview.itemlist) do
		if val.kind == "background" then
			delete_image(customview.itemlist[ind].vid);
			customview.itemlist[ind] = customview.ci; 
			found = true;
			break
		end
	end

	if (found == false) then
		table.insert(customview.itemlist, customview.ci);
	end

	to_menu();
end

local function navigator_toggle(status, x1, y1, x2, y2)
	if (status == true) then
-- setup and show new menu
		current_menu:destroy();
		lbls, ptrs = gen_contents_menu();

		current_menu:show();
		move_image(current_menu.anchor, 10, 120, settings.fadedelay);
	else 
		show_image(current_menu.anchor);
		settings.iodispatch = position_dispatch;
	end
end

local function positionfun(label)
	vid = load_image("images/" .. label);
	
	if (vid ~= BADID) then
		new_item(vid, "static_media", label);
		customview.ci.res = "images/" .. label;

		customview.position_item(vid, save_item);
	end
end

local cleanup = nil;

local function customview_internal(source, datatbl)
	if (datatbl.kind == "resized") then
		if (not settings.in_internal) then
			gridle_load_internal_extras( resourcefinder_search(customview.gametbl, true), customview.gametbl.target );
			if (settings.autosave == "On") then internal_statectl("auto", false); end
			internal_aid = datatbl.source_audio;
			internal_vid = source;
					
			settings.internal_toggles.bezel     = false;
			settings.internal_toggles.overlay   = false;
			settings.internal_toggles.backdrops = false;

			audio_gain(internal_aid, settings.internal_again, NOW);

			gridle_input = gridle_internalinput;
			settings.in_internal = true;

			gridlemenu_rebuilddisplay();
			image_tracetag(source, "internal_launch(" .. current_game().title ..")");
		else
			gridlemenu_rebuilddisplay();
		end
	elseif (datatbl.kind == "frameserver_terminated") then
		pop_video_context();
		cleanup();
	end
end

local function cleanup()
-- since new screenshots /etc. might have appeared, update cache 
	resourcefinder_cache.invalidate = true;
		local gameno = current_game_cellid();
		resourcefinder_search(customview.gametbl, true);
	resourcefinder_cache.invalidate = false;

	local resetview = function()
		pop_video_context();
		settings.iodispatch = customview.dispatchtbl;
		gridle_input = gridle_dispatchinput;
		settings.in_internal = false;
	end

-- setup a quick timer, wait 20 ticks for autosave etc. to finish THEN cleanup.
	if (settings.autosave == "On" and valid_vid(internal_vid)) then 
		local counter = 20;
		blend_image(internal_vid, 0.0, 20);
		audio_gain(internal_aid, 0.0, 20);
		
		internal_statectl("auto", true); 
		gridle_clock_pulse = function() 
			if counter > 0 then
				counter = counter - 1;
			else
				resetview();
				gridle_clock_pulse = nil;
			end
		end
	else
-- no autosave, pop_video_context is safe
		resetview();
	end
end

local function launch(tbl)
	local launch_internal = (settings.default_launchmode == "Internal" or tbl.capabilities.external_launch == false) and tbl.capabilities.internal_launch;
	push_video_context();

-- can also be invoked from the context menus
	if (launch_internal) then
		play_audio(soundmap["LAUNCH_INTERNAL"]);
		customview.gametbl = tbl;
		settings.cleanup_toggle = cleanup;

		if (valid_vid(internal_vid)) then delete_image(internal_vid); end

-- replace this one so that file-name, config names etc. are correct when emitted from intmenus
		current_game = function() return tbl; end

		internal_vid = launch_target( tbl.gameid, LAUNCH_INTERNAL, customview_internal );
		gridle_input = nil;

	else
		settings.in_internal = false;
		play_audio(soundmap["LAUNCH_EXTERNAL"]);
		launch_target( current_game().gameid, LAUNCH_EXTERNAL);
		pop_video_context();
	end
end

local function effecttrig(label)
	local shdr    = load_shader("shaders/fullscreen/default.vShader", "customview/bgeffects/" .. label, "bgeffect", {});
	customview.bgshader = shdr;
	customview.bgshader_label = label;

	update_bgshdr();
	settings.iodispatch["MENU_ESCAPE"]();
end

local function positiondynamic(label)
-- first try and find a template image based on label (most have special handling)
	local vid = BADID;
	
	if (resource("customview/" .. string.lower(label) .. ".png")) then
		vid = load_image("customview/" .. string.lower(label) .. ".png");
	end
	
	if (vid == BADID) then
-- as a fallback, generate a label
		switch_default_texmode(TEX_REPEAT, TEX_REPEAT);
		vid = render_text(settings.colourtable.label_fontstr .. label);
		
		switch_default_texmode(TEX_CLAMP, TEX_CLAMP);
		new_item(vid, "dynamic_media", string.lower(label));
		customview.ci.tiled  = true;
	else
		new_item(vid, "dynamic_media", string.lower(label));
		customview.ci.tiled = false;
	end

	customview.ci.width  = VRESW * 0.3;
	customview.ci.height = VRESH * 0.3; 
	customview.position_item(vid, save_item);
end

local function positionlabel(label)
	vid = render_text(settings.colourtable.label_fontstr .. label);
	new_item(vid, "label", string.lower(label));
	customview.position_item(vid, save_item);
end

-- only one navigator allowed, boring list, iconed list etc. use static preview- image. 
local function positionnavi(label)
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT);
	local vid = render_text(settings.colourtable.label_fontstr .. label);
	switch_default_texmode(TEX_CLAMP, TEX_CLAMP);

	new_item(vid, "navigator", label);
	customview.ci.tiled = true;
	customview.ci.width = VRESW * 0.3;
	customview.ci.height = VRESH * 0.7;
	customview.position_item(vid, save_item);
end

-- stretch to fit screen, only opa change allowed
local function positionbg(label)
	local tiled = false;
	local vid = load_image("backgrounds/" .. label);
	if (vid == BADID) then return; end

	customview.ci = {};
	customview.ci.tiled  = tiled;
	local props = image_surface_properties(vid);

	switch_default_texmode( TEX_REPEAT, TEX_REPEAT, vid );
	if (customview.ci.tiled) then
		local props = image_surface_initial_properties(imgvid);
		image_scale_txcos(imgvid, customview.ci.width / props.width, customview.ci.height / props.height);
	end
	
-- threshold for tiling rather than stretching
	if (props.width < VRESW / 2 or props.height < VRESH / 2) then
		customview.ci.tiled  = true;
	end

	customview.ci.width  = VRESW;
	customview.ci.height = VRESH;
	customview.ci.zv     = 0;
	customview.ci.x      = 0;
	customview.ci.y      = 0;
	customview.ci.opa    = 1.0;
	customview.ci.ang    = 0;
	customview.ci.kind   = "background";
	customview.ci.shader = customview.bgshader_label;
	customview.ci.res    = "backgrounds/" .. label;

	customview.position_item(vid, save_item_bg);
end

-- take the custom view and dump to a .lua config
local function save_config()
	open_rawresource("customview_cfg.lua");
	write_rawresource("local cview = {};\n");
	write_rawresource("cview.static = {};\n");
	write_rawresource("cview.dynamic = {};\n");
	write_rawresource("cview.dynamic_labels = {};\n");
	write_rawresource("cview.aspect = " .. tostring( VRESW / VRESH ) .. ";\n");
	
	for ind, val in ipairs(customview.itemlist) do
		write_rawresource("local item = {};\n");
		write_rawresource("item.x      = " .. tostring( val.x / VRESW ) .. ";\n");
		write_rawresource("item.y      = " .. tostring( val.y / VRESH ) .. ";\n");
		write_rawresource("item.order  = " .. val.zv .. ";\n");
		write_rawresource("item.opa    = " .. val.opa .. ";\n");
		write_rawresource("item.ang    = " .. val.ang .. ";\n");
		write_rawresource("item.width  = " .. tostring(val.width / VRESW ) .. ";\n");
		write_rawresource("item.height = " .. tostring(val.height / VRESH ) .. ";\n");
		write_rawresource("item.tiled  = " .. tostring(val.tiled == true) .. ";\n");
		
		if val.kind == "static_media" then
			write_rawresource("item.res    = \"" .. val.res .. "\";\n");
			write_rawresource("table.insert(cview.static, item);\n");

		elseif val.kind == "dynamic_media" then
			write_rawresource("item.res    = \"" .. val.res .. "\";\n");
			write_rawresource("table.insert(cview.dynamic, item);\n");

		elseif val.kind == "navigator" then
			write_rawresource("item.res    = \"" .. val.res .. "\";\n");
			write_rawresource("item.font   = [[\\ffonts/default.ttf,]];\n");
			write_rawresource("cview.navigator = item;\n");

		elseif val.kind == "label" then
			write_rawresource("item.res    = \"" .. val.res .. "\";\n");
			write_rawresource("item.font   = [[\\ffonts/default.ttf,]];\n");
			write_rawresource("table.insert(cview.dynamic_labels, item);\n");
			
		elseif val.kind == "background" then
			write_rawresource("item.res    = \"" .. val.res .."\";\n");
			if (val.shader) then
				write_rawresource("item.shader = \"" .. val.shader .. "\";\n");
			end
			
			write_rawresource("cview.background = item;\n");
		else
			print("[customview:save_config] warning, unknown kind: " .. val.kind);
		end
	end
	
	write_rawresource("return cview;\n");
	close_rawresource();
end

-- the configure dialog works in that the user first gets to select and position a navigator based on a grid 
-- calculated from the current window dimensions, then chose which media types that should be displayed and where.

-- if two media types share the exact same space, they are mutually exclusive and the order of placement (first->last)
-- determines priority, i.e. if one is found, the other won't be loaded.
local function show_config()
	customview_display = settings.iodispatch;
	settings.iodispatch = {};
	customview.itemlist = {};
	
	gridlemenu_defaultdispatch();
	local escape_menu = function(label, save, sound)
	
		if (current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
			if (sound == nil or sound == false) then 
				play_audio(soundmap["MENU_FADE"]); 
			end
		end
		
	end
	
	settings.iodispatch["MENU_LEFT"]   = escape_menu;
	settings.iodispatch["MENU_ESCAPE"] = escape_menu;
	
	local mainlbls = {};
	local mainptrs = {};

	add_submenu(mainlbls, mainptrs, "Backgrounds...", "ignore", build_globmenu("backgrounds/*.png", positionbg, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Background Effects...", "ignore", build_globmenu("customview/bgeffects/*.fShader", effecttrig, THEME_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Images...", "ignore", build_globmenu("images/*.png", positionfun, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Dynamic Media...", "ignore", gen_tbl_menu("ignore",	{"Screenshot", "Movie", "Bezel", "Marquee", "Flyer", "Boxart"}, positiondynamic));
	add_submenu(mainlbls, mainptrs, "Dynamic Labels...", "ignore", gen_tbl_menu("ignore", {"Title", "Year", "Players", "Target", "Genre", "Subgenre", "Setname", "Buttons", "Manufacturer", "System"}, positionlabel));
	add_submenu(mainlbls, mainptrs, "Navigators...", "ignore", gen_tbl_menu("ignore", {"list"}, positionnavi));
	
	table.insert(mainlbls, "---");
	table.insert(mainlbls, "Save/Finish");
	table.insert(mainlbls, "Cancel");
	
	mainptrs["Cancel"] = function(label, save)
		while current_menu ~= nil do
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
		
		play_audio(soundmap["MENU_FADE"]);
		settings.iodispatch = customview_display;
		pop_video_context();
		setup_gridview();
	end
	
	mainptrs["Save/Finish"] = save_config;
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;

	current_menu:show();
	move_image(current_menu.anchor, 10, VRESH * 0.1, settings.fadedelay);
end

local function place_item( vid, tbl )
	local x = math.floor(tbl.x * VRESW);
	local y = math.floor(tbl.y * VRESH);
	local w = math.floor(tbl.width * VRESW);
	local h = math.floor(tbl.height* VRESH);
	
	move_image(vid, x, y);
	rotate_image(vid, tbl.ang);
	resize_image(vid, w, h);
	order_image(vid, tbl.order);
	blend_image(vid, tbl.opa, 10);
end

local function update_dynamic(newtbl)
	if (newtbl == nil or newtbl == customview.lasttbl) then
		return;
	end

	customview.lasttbl = newtbl;
	toggle_led(newtbl.players, newtbl.buttons, "")	;
	
	for ind, val in ipairs(customview.temporary) do
		if (valid_vid(val)) then 
			expire_image(val, 10);
		end
	end

	customview.temporary = {};
	local restbl = resourcefinder_search( newtbl, true );
	if (restbl) then

		for ind, val in ipairs(customview.current.dynamic) do
			reskey = remaptbl[val.res];

			if (reskey and restbl[reskey] and #restbl[reskey] > 0) then
				if (reskey == "movies") then
					vid, aid = load_movie(restbl[reskey][1], FRAMESERVER_LOOP, function(source, status)
						place_item(source, val);
						play_movie(source);
					end)
					table.insert(customview.temporary, vid);	
				else
					vid = load_image_asynch(restbl[reskey][1], function(source, status)
						place_item(source, val);
					end);
					table.insert(customview.temporary, vid);
				end
	
			end
			
		end
		
		for ind, val in ipairs(customview.current.dynamic_labels) do
			if (newtbl[val.res] and string.len( newtbl[val.res] ) > 0) then
				vid = render_text(val.font .. math.floor( VRESH * val.height ) .. newtbl[val.res]); 
				place_item(vid, val);
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
		place_item( vid, val );
	end

-- load background effect 
	if (customview.current.background) then
		vid = load_image( customview.current.background.res );
		place_item(vid, customview.current.background);
		if (customview.current.background.shader) then
			local shdr    = load_shader("shaders/fullscreen/default.vShader", "customview/bgeffects/" .. customview.current.background.shader, "bgeffect", {});
			customview.bgshader = shdr;

			local props  = image_surface_properties(vid);
			local iprops = image_surface_initial_properties(vid);

			if (customview.current.background.tiled) then
				switch_default_texmode(TEX_REPEAT, TEX_REPEAT, vid);
				image_scale_txcos(vid, props.width / iprops.width, props.height / iprops.height);
			end

			shader_uniform(shdr, "display", "ff", PERSIST, props.width, props.height);
			image_shader(vid, shdr);
		end
	end

-- remap I/O functions to fit navigator
	olddispatch = settings.iodispatch;
	settings.iodispatch = {};
	
	if (customview.current.navigator) then
		customview.navigator = system_load("customview/" .. customview.current.navigator.res .. ".lua")();
		local navi = customview.navigator;
		local navitbl = customview.current.navigator;
		
-- dstvid is the clipping region, so shouldn't really shared order etc. as it is invisible
-- but when it is dropped, it can cascade to the members of the navigator 
		dstvid = navi:create(math.floor(navitbl.width * VRESW), math.floor(navitbl.height * VRESH));
		navi:update_list(settings.games);
		
-- order and opacity doesn't apply to anchor, just to drawable
		move_image(dstvid, math.floor(navitbl.x * VRESW), math.floor(navitbl.y * VRESH));
		rotate_image(dstvid, navitbl.ang);

		settings.iodispatch["MENU_UP"]   = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:up(1);
			navi_change(navi, navitbl);
		end

		settings.iodispatch["MENU_DOWN"] = function() 
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:down(1); 
			navi_change(navi, navitbl);
		end

		settings.iodispatch["MENU_LEFT"] = function() 
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:left(1);
			navi_change(navi, navitbl);
		end

		settings.iodispatch["MENU_TOGGLE"]  = function(iotbl) 
			play_audio(soundmap["MENU_TOGGLE"]);
			gridlemenu_settings( function() navi:update_list(settings.games); end, function() end); 
		end
		
		settings.iodispatch["MENU_RIGHT"] = function()
			play_audio(soundmap["GRIDCURSOR_MOVE"]);
			navi:right(1);
			navi_change(navi, navitbl);
		end

		settings.iodispatch["MENU_SELECT"] = function()
			local res = navi:trigger_selected();
			if (res ~= nil) then
				res.capabilities = launch_target_capabilities( res.target )
				launch(res);
			else
				navi_change(navi, navitbl);
			end
		end
		
		settings.iodispatch["MENU_ESCAPE"] = function()
			if ( navi:escape() ) then
				pop_video_context();
				settings.iodispatch = olddispatch;
				setup_gridview();
			else
				navi_change(navi, navitbl);
			end
		end

		customview.dispatchtbl = settings.iodispatch;
	end
	
end

function gridle_customview()
	local disptbl;
	
-- try to load a preexisting configuration file, if no one is found
-- launch in configuration mode -- to reset this procedure, delete any 
-- customview_cfg.lua and reset customview.in_config
	pop_video_context();

	if (resource("customview_cfg.lua")) then
		customview.current = system_load("customview_cfg.lua")();
		
		if (customview.current) then
			customview.in_config = false;
			pop_video_context();
			setup_customview();
		end
		
	else
		disptbl = show_config();
	end
	
end