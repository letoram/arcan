--
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
-- the contents of the config data is just a 'label' and a bounding area (x1,y1,x2,y2)
-- stored as relative of the display-size.
--
--
local grid_stepx = 2;
local grid_stepy = 2;

local stepleft, stepup, stepdown, stepright, show_config, setup_customview;

local customview = {};

customview.in_config = true;
customview.marker_x = VRESW * 0.5;
customview.marker_y = VRESH * 0.5;

customview.position_modes  = {"position", "orientation", "opacity", "order"};
customview.position_marker = 1;

-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end

local function position_toggle()
-- don't allow any other mode to be used except position until we have an upper left boundary
	if (customview.marker.ul == nil) then 
		customview.position_marker = 1; 
	else
		customview.position_marker = (customview.position_marker + 1 > #customview.position_modes) and 1 or (customview.position_marker + 1);
	end
	
-- FIXME have a label / something that shows WHERE we are
end

local function update_position(markervid, imgvid)
	move_image(markervid, customview.marker_x, customview.marker_y);

	if (customview.ci.ul) then
		resize_image(imgvid, customview.marker_x - customview.ci.ul.x + 1, customview.marker_y - customview.ci.ul.y + 1);
		move_image(imgvid, customview.ci.ul.x, customview.ci.ul.y);
		blend_image(imgvid, 0.6);
	end
	
end

local function cursor_step(x, y)
	customview.marker_x = customview.marker_x + x;
	customview.marker_y = customview.marker_y + y;

	if (customview.ci.ul and customview.ci.ul.x > customview.marker_x) then
		customview.marker_x = customview.ci.ul.x;
	end
		
	if (customview.ci.ul and customview.ci.ul.y > customview.marker_y) then
		customview.marker_y = customview.ci.ul.y;
	end
	
	update_position(customview.marker, vid);
end

local function orientation_rotate(ang, align)
	
end

local function order_increment(ang, align)
end

local function opacity_increment(byval)
	
end

local function position_item( key, vid, trigger )
	kbd_repeat(20);

	position_dispatch = settings.iodispatch;
	settings.iodispatch = {};

	settings.iodispatch["MENU_LEFT"]   = function()
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "position")    then cursor_step(vid, grid_stepx * -1, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid, -2, true);
		elseif (lbl == "opacity")     then opacity_increment(vid, 1, true); end
	end
	
	settings.iodispatch["MENU_RIGHT"]  = function() 
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "position")    then cursor_step(grid_stepx, 0);
		elseif (lbl == "orientation") then orientation_rotate(vid, 2, true);
		elseif (lbl == "opacity")     then opacity_increment(vid, -1, true); end
	end

	settings.iodispatch["MENU_UP"]     = function()
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "position")    then cursor_step(vid, 0, grid_stepy * -1);
		elseif (lbl == "orientation") then orientation_rotate(vid, 45, false);
		elseif (lbl == "opacity")     then order_increment(vid, 1); end
	end
	
	settings.iodispatch["MENU_DOWN"]   = function() 
		local lbl = customview.position_modes[customview.position_marker];
		if     (lbl == "position")    then cursor_step(vid, 0, grid_stepy);
		elseif (lbl == "orientation") then orientation_rotate(vid, 45, false);
		elseif (lbl == "opacity")     then order_increment(vid, -1); end
	end
	
	settings.iodispatch["MENU_ESCAPE"] = function() 
		delete_image(customview.marker);
		delete_image(vid);
		trigger(false);
	end

-- cycle through position modes in order to re-use the same keys etc. for changing multiple variable
	settings.iodispatch["LIST_VIEW"] = function() position_toggle(); end
	
	settings.iodispatch["MENU_SELECT"] = function()
		if (customview.ci.ul == nil) then
			customview.ci.ul = {};
			customview.ci.ul.x = customview.marker_x;
			customview.ci.ul.y = customview.marker_y;
		else
			hide_image(customview.marker);
			trigger(true, customview.ci.ul.x, customview.ci.ul.y, customview.marker_x, customview.marker_y);
		end
	end
end

local function gen_contents_menu()
	customview.marker_x = VRESW * 0.5;
	customview.marker_y = VRESH * 0.5;
	update_position(customview.marker, vid);
end

local function navigator_toggle(status, x1, y1, x2, y2)
	if (status == true) then
-- setup and show new menu
		current_menu:destroy();
		lbls, ptrs = gen_contents_menu();
		current_menu = listview_create(lbls, VRESH * 0.9, VRESW / 3);
		current_menu.ptrs = ptrs;
		current_menu.parent = nil;

		current_menu:show();
		move_image(current_menu.anchor, 10, 120, settings.fadedelay);
	else 
		show_image(current_menu.anchor);
		settings.iodispatch = position_dispatch;
	end
end

local function positionfun(label)
	vid = load_image(label);

	if (vid ~= BADID) then
		customview.marker = fill_surface(8,8, 255, 0, 0);
	
		show_image(customview.marker);
		hide_image(current_menu.anchor);
		customview.ci = {};
	end
		
end

-- stretch to fit screen, only opa change allowed
local function positionbg(label)
	local vid = load_image(label)
	
	if (vid ~= BADID) then
		resize_image(vid, 0,0, VRESW, VRESH);
		show_image(vid);
		hide_image(current_menu.anchor);
		
		customview.ci = {};
		customview.ci.ul = {};
		customview.ci.ul.x = 0;
		customview.ci.ul.y = 0;
		customview.marker_x = VRESW;
		customview.marker_y = VRESH;
	
		customview.position_marker = 1;
		customview.position_modes = {"opacity"};
	end
	
end

-- the configure dialog works in that the user first gets to select and position a navigator based on a grid 
-- calculated from the current window dimensions, then chose which media types that should be displayed and where.

-- if two media types share the exact same space, they are mutually exclusive and the order of placement (first->last)
-- determines priority, i.e. if one is found, the other won't be loaded.
local function show_config()
	customview_display = settings.iodispatch;
	settings.iodispatch = {};

	gridlemenu_defaultdispatch();
	local escape_menu = function()
		if (current_menu.parent ~= nil) then
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
	end
	
	settings.iodispatch["MENU_LEFT"]   = escape_menu;
	settings.iodispatch["MENU_ESCAPE"] = escape_menu;
	
	local mainlbls = {};
	local mainptrs = {};

	add_submenu(mainlbls, mainptrs, "Backgrounds...", "ignore", build_globmenu("backgrounds/*.png", positionbg, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Images...", "ignore", build_globmenu("images/*.png", positionfun, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Dynamic Media...", "ignore", gen_tbl_menu("ignore",	{"Screenshot", "Movie", "Bezel", "Marquee"}, positiondynamic));

	add_submenu(mainlbls, mainptrs, "Navigators...", "ignore", gen_tbl_menu("ignore", {"List"}, positionfun));
	
	table.insert(mainlbls, "---");
	table.insert(mainlbls, "Save/Finish");
	table.insert(mainlbls, "Quit");
	
	mainptrs["Quit"] = function(label, save)
		while current_menu ~= nil do
			current_menu:destroy();
			current_menu = current_menu.parent;
		end
		
		play_audio(soundmap["MENU_FADE"]);
		settings.iodispatch = customview_display;
		pop_video_context();
	end
	
	current_menu = listview_create(mainlbls, VRESH * 0.9, VRESW / 3);
	current_menu.ptrs = mainptrs;
	current_menu.parent = nil;

	current_menu:show();
	move_image(current_menu.anchor, 10, 120, settings.fadedelay);
end

local function setup_customview()
end

function gridle_customview()
	local disptbl;

-- try to load a preexisting configuration file, if no one is found
-- launch in configuration mode -- to reset this procedure, delete any 
-- customview_cfg.lua and reset customview.in_config
	
	if (customview.in_config and resource("customview_cfg.lua")) then
		local cconf = system_load("customview_cfg.lua")();
		if (cconf and cconf.navigation ~= nil and 
				type(cconf.list) == "table") then
			customview.in_config = false;
			gridle_customview();
			return;
		end

	elseif (customview.in_config) then
		push_video_context();
		disptbl = show_config();
	else
		push_video_context();
		disptbl = setup_customview();
	end
	
end
