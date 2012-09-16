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

-- list of the currently allowed modes (size, position, opacity, orientation)
customview.position_modes  = {"position", "size", "opacity", "orientation"};
customview.position_marker = 1;
customview.orderind = 1;

-- populated with data on each added "item" used to build the final customview lualu
customview.itemlist = {};

-- set "step size" for moving markers in configuration based on
-- the dimensions of the display
while (VRESW / grid_stepx > 100) do
	grid_stepx = grid_stepx + 2;
end

while (VRESH / grid_stepy > 100) do
	 grid_stepy = grid_stepy + 2;
end

local function cascade_visibility(menu, val)
	if (menu.parent) then
		cascade_visibility(menu.parent, val);
	end

	blend_image(menu.anchor, val);
	menu:push_to_front();
end

local function position_toggle()
-- don't allow any other mode to be used except position until we have an upper left boundary
	customview.position_marker = (customview.position_marker + 1 > #customview.position_modes) and 1 or (customview.position_marker + 1);
	
-- FIXME have a label / something that shows WHERE we are
end

local function update_object(imgvid)
	resize_image(imgvid, customview.ci.width, customview.ci.height);
	move_image(imgvid, customview.ci.x, customview.ci.y);
	blend_image(imgvid, customview.ci.opa);
	rotate_image(imgvid, customview.ci.ang);
	order_image(imgvid, customview.ci.zv);
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
	
--	if(customview.ci.ang > 360) then
--		customview.ci.ang = customview.ci.ang - 360;
--	end
	
--	if (customview.ci.ang < -360) then
--		customview.ci.ang = customview.ci.ang + 360;
--	end

	update_object(vid);
end

local function order_increment(vid, val)
	customview.ci.zv = customview.ci.zv + val;
	if (customview.ci.zv < 1) then customview.ci.zv = 1; end

	update_object(vid);
end

local function opacity_increment(vid, byval)
	customview.ci.opa = customview.ci.opa + byval;
	
	if (customview.ci.opa < 0.0) then customview.ci.opa = 0.0; end
	if (customview.ci.opa > 1.0) then customview.ci.opa = 1.0; end
	
	update_object(vid);
end

local function position_item( key, vid, trigger )
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
	settings.iodispatch["LIST_VIEW"]   = function() position_toggle();   end
	settings.iodispatch["MENU_SELECT"] = function() trigger(true, vid);  end
end

local function new_item(vid)
	local props = image_surface_properties(vid);

	customview.ci = {};
	customview.ci.width = (props.width > VRESW * 0.5) and VRESW * 0.5 or props.width;
	customview.ci.height= (props.height > VRESH * 0.5) and VRESH * 0.5 or props.height;
	customview.ci.x     = 0.5 * (VRESW - customview.ci.width);
	customview.ci.y     = 0.5 * (VRESH - customview.ci.height);
	customview.ci.opa   = 1.0;
	customview.ci.ang   = 0;

	customview.ci.zv    = customview.orderind;
	customview.orderind = customview.orderind + 1;
end

local function save_item(state, vid)
	if (state) then
		table.insert(customview.itemlist, customview.ci);
	else
		delete_image(vid);
	end
	
	customview.ci = nil;
	settings.iodispatch = position_dispatch;
	settings.iodispatch["MENU_ESCAPE"]("", false, false);
	cascade_visibility(current_menu, 1.0);
end

local function navigator_toggle(status, x1, y1, x2, y2)
	if (status == true) then
-- setup and show new menu
		current_menu:destroy();
		lbls, ptrs = gen_contents_menu();
--		current_menu = listview_create(lbls, VRESH * 0.9, VRESW / 3);
--		current_menu.ptrs = ptrs;
--		current_menu.parent = nil;

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
		new_item(vid);
		position_item(nil, vid, save_item);
	end
end

local function positiondynamic(label)
	resvid = fill_surface(VRESW * 0.3, VRESH * 0.3, 0, 255, 0);

	new_item(resvid);
	position_item(nil, resvid, save_item); 
end

-- only one navigator allowed, boring list, iconed list etc. use static preview- image. 
local function positionnavi(label)
	local vid = render_text(settings.colourtable.label_fontstr .. label);
	new_item(vid);
	customview.ci.tiled = true;
	position_item(label, vid);
end

-- stretch to fit screen, only opa change allowed
local function positionbg(label)
	local vid = load_image("backgrounds/" .. label)
	
	if (vid ~= BADID) then
		customview.ci = {};
		customview.ci.tiled  = false;
		local props = image_surface_properties(vid);

-- threshold for tiling rather than stretching
		if (props.width < VRESW / 2 or props.height < VRESH / 2) then
			customview.ci.tiled  = true;
		end

		customview.ci.width  = VRESW;
		customview.ci.height = VRESH;
		customview.ci.zv     = 1;
		customview.ci.x      = 0;
		customview.ci.y      = 0;
		customview.ci.opa    = 1.0;
		customview.ci.ang    = 0;
		position_item(label, vid, save_item); 
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
	add_submenu(mainlbls, mainptrs, "Images...", "ignore", build_globmenu("images/*.png", positionfun, ALL_RESOURCES));
	add_submenu(mainlbls, mainptrs, "Dynamic Media...", "ignore", gen_tbl_menu("ignore",	{"Screenshot", "Movie", "Bezel", "Marquee"}, positiondynamic));
	add_submenu(mainlbls, mainptrs, "Navigators...", "ignore", gen_tbl_menu("ignore", {"List"}, positionnavi));
	
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
