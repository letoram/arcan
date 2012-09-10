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

-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end


local function position_toggle()
	
end

local function update_position(markervid, imgvid)
	move_image(markervid, customview.marker_x, customview.marker_y);

	if (customview.ci.ul) then
		resize_image(imgvid, customview.marker_x - customview.ci.ul.x + 1, customview.marker_y - customview.ci.ul.y + 1);
		move_image(imgvid, customview.ci.ul.x, customview.ci.ul.y);
		blend_image(imgvid, 0.6);
	end
	
end

local function position_item( key, vid, trigger )
	customview.marker = fill_surface(8,8, 255, 0, 0);
	
	show_image(customview.marker);
	hide_image(current_menu.anchor);
	customview.ci = {};
	
	kbd_repeat(20);
	customview.marker_x = VRESW * 0.5;
	customview.marker_y = VRESH * 0.5;
	update_position(customview.marker, vid);
	
	position_dispatch = settings.iodispatch;
	settings.iodispatch = {};

	settings.iodispatch["MENU_LEFT"]   = function()
		if (customview.ci.ul == nil or customview.ci.ul.x < customview.marker_x - grid_stepx) then
			customview.marker_x = customview.marker_x - grid_stepx;
		end

		update_position(customview.marker, vid);
	end
	
	settings.iodispatch["MENU_RIGHT"]  = function() 
		customview.marker_x = customview.marker_x + grid_stepx;
		update_position(customview.marker, vid);
	end

	settings.iodispatch["MENU_UP"]     = function()
		if (customview.ci.ul == nil or customview.ci.ul.y < customview.marker_y - grid_stepy) then
			customview.marker_y = customview.marker_y - grid_stepy;
		end

		update_position(customview.marker, vid)		
	end
	
	settings.iodispatch["MENU_DOWN"]   = function() 
		customview.marker_y = customview.marker_y + grid_stepy;

		update_position(customview.marker, vid);
	end
	
	settings.iodispatch["MENU_ESCAPE"] = function() 
		delete_image(customview.marker);
		delete_image(vid);
		trigger(false);
	end

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

-- the configure dialog works in that the user first gets to select and position a navigator based on a grid 
-- calculated from the current window dimensions, then chose which media types that should be displayed and where.

-- if two media types share the exact same space, they are mutually exclusive and the order of placement (first->last)
-- determines priority, i.e. if one is found, the other won't be loaded.

local function show_config()
	customview_display = settings.iodispatch;
	settings.iodispatch = {};
	settings.iodispatch["MENU_ESCAPE"] = function()
		pop_video_context();
		settings.iodispatch = customview_display;
	end

	gridlemenu_defaultdispatch();
	
	local mainlbls = {
		"List Navigator",
		"Category Navigator"
	};

	local mainptrs = {};
	mainptrs["List Navigator"] = function() position_item( "navigator", fill_surface(8, 8, 255, 0, 0), navigator_toggle); end
	mainptrs["Category Navigator"] = function() position_item( "navigator", fill_surface(8, 8, 255, 0, 0), navigator_toggle); end
	
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
