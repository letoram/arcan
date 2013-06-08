--
-- Amiga Workbench- Lookalike Theme
-- Conceived in a "how far can you get in 24 hours" hackathon
-- (wildly re-uses stuff from gridle to get that done however)
--
wlist    = {
	windows = {};
};

settings = {};
sysicons = {};
imagery  = {};
colortable = {};

groupicn = "awbicons/drawer.png";
groupselicn = "awbicons/drawer_open.png";
deffont = "fonts/topaz8.ttf";
deffont_sz = 12;
mfact = 0.2;

colortable.bgcolor = {0, 85, 169};

x_spawnpos = 20;
y_spawnpos = 20;

ORDER_BGLAYER   = 1;
ORDER_ICONLAYER = 2;
ORDER_WDW       = 10;
ORDER_FOCUSWDW  = 30;
ORDER_MOUSE     = 255;

--  window (focus, minimize, maximize, close)
--  border (always visible, content (when not drag))

--  launch_window
-- console_window
--   group_window

function awb()
	symtable = system_load("scripts/symtable.lua")();
	system_load("scripts/3dsupport.lua")();
-- note; colourtable in this theme overrides the one in the global namespace 
	settings.colourtable = system_load("scripts/colourtable.lua")();
	system_load("awb_window.lua")();

--
-- the other icons are just referenced by string since they're managed by 
-- their respective windows
-- 
	imagery.background = fill_surface(VRESW, VRESH, 0, 0, 0);
	imagery.cursor = load_image("awbicons/mouse.png", ORDER_MOUSE);

	move_image(imagery.cursor, math.floor(VRESW * 0.5), math.floor(VRESW * 0.5));
	show_image(imagery.cursor);

	rootwnd = awbwnd_create({
		fullscreen = true,
		border = false,
		borderw = 0,
		mode = "iconview",
		iconalign = "right"
	});

	rootwnd:add_bar("top", function() return fill_surface(1,1, 230, 230, 230);
		end, nil, 24);
	rootwnd:add_icon("Systems",   groupicn, groupselicn, deffont, deffont_sz, sfn);
	rootwnd:add_icon("Games",     groupicn, groupselicn, deffont, deffont_sz, sfn);
	rootwnd:add_icon("History",   groupicn, groupselicn, deffont, deffont_sz, sfn);
	rootwnd:add_icon("Favorites", groupicn, groupselicn, deffont, deffont_sz, sfn);
	rootwnd:show();
	spawn_boing();
	spawn_boing();
	a = spawn_window();
--b = spawn_window();
end

--
-- A little hommage to the original, shader is from rendertoy
--
function spawn_boing()
	local a = spawn_window();
	local boing = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/boing.fShader", "boing", {}); 
	local props = image_surface_properties(a.canvas);
	shader_uniform(boing, "display", "ff", PERSIST, props.width, props.height); 
	image_shader(a.canvas, boing); 
end

function focus_window(wnd)
	if (wnd == rootwnd or wnd == wlist.focus) then
		return;
	end

	if (wlist.focus) then
		wlist.focus:active(false);
		wlist.focus:reorder(ORDER_WDW);
	end

	wlist.focus = wnd;
	wnd:reorder(ORDER_FOCUSWDW);
end

--
-- Allocate, Setup, Register and Position a new Window
-- These always start out focused
--
function spawn_window(wtype)
	wcont = awbwnd_create({
		mode = "container",

		fullscreen = false,
		border  = true,
		borderw = 2,

		width   = 320,
		height  = 200,
		x    = x_spawnpos,
		y    = y_spawnpos
	});

	wcont.cursor_input = function() end
	wcont.table_input  = function() end

	wcont:add_bar("top", "awbicons/border.png", nil, 16);
	wcont:show();
		
	x_spawnpos = x_spawnpos + 20;
	y_spawnpos = y_spawnpos + 20;
	
	wcont.window = demownd;
	focus_window(wcont);

	wlist.focus = wcont;
	wcont:reorder(ORDER_FOCUSWDW);
	table.insert(wlist.windows, wcont);

	return wcont;
end

--
-- Prevent moving the mouse-cursor too far off screen
--
local function clamp_cursor()
	local props = image_surface_properties(imagery.cursor);
	local x = props.x < 0 and 0 or props.x;
	local y = props.y < 0 and 0 or props.y;
	
	x = props.x > VRESW and VRESW-1 or x; 
	y = props.y > VRESH and VRESH-1 or y; 

	move_image(imagery.cursor, x, y);

	if (cursor_drag) then
		cursor_drag:move(x - cursor_drag.pxofs, y - cursor_drag.pyofs);
	end
end

local function hit_handler(window, label, vid, buttonind)
-- always focus
	focus_window(window);

-- dragging action
	if (buttonind == 1 and label == "top") then
		cursor_drag = window;
		local props = image_surface_resolve_properties(
			window.directions["top"].activeid);
		local mprops = image_surface_properties(imagery.cursor);
		cursor_drag.pxofs = mprops.x - props.x;
		cursor_drag.pyofs = mprops.y - props.y;
	else
		print("hit handler", vid, label, buttonind);
	end
end

--
-- Handle this separately from awb_input as there's several cases that
-- should be covered (dragging, pressing buttons, context menus etc.)
--
local function cursor_mouseinput(active, buttonind)
	local props = image_surface_properties(imagery.cursor);

-- special case, stop dragging when the first button is released 
	if (buttonind == 1) then
		if (active == false) then
			if (cursor_drag) then
				cursor_drag = nil;
				return;
			end
		end
	end

--
-- else sweep the windows and (lastly) the root window 
-- for the topmost triggered item
-- 
	local items = pick_items(props.x, props.y, 5, 1); 
		for ind, val in ipairs(items) do
			for wind, wval in ipairs(wlist.windows) do
				local rv = wval:own(val);
				if (rv) then
					return hit_handler(wval, rv, val, buttonind);
				end
			end
			
			local rv = rootwnd:own(val);
			if (rv) then
				return hit_handler(rootwnd, rv, val, buttonind);
		end
	end
end

function awb_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		iotbl.samples[2] = iotbl.samples[2] * mfact;
		if (iotbl.subid == 1) then
			nudge_image(imagery.cursor, 0, iotbl.samples[2]);
			clamp_cursor();
		elseif (iotbl.subid == 0) then
			nudge_image(imagery.cursor, iotbl.samples[2], 0);
			clamp_cursor();
		else
			a = a;
		end
	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		cursor_mouseinput(iotbl.active, iotbl.subid);
	
	elseif (iotbl.kind == "digital" and iotbl.active and iotbl.translated) then
		if (symtable[iotbl.keysym] == "LCTRL") then
			toggle_mouse_grab();
		end
	elseif (wlist.focus) then
		wlist.focus:table_input(iotbl);
	end
end

function awb_clock_pulse(stamp, nticks)
end
