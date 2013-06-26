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

function menulbl(text)
	return render_text(string.format("\\#0055a9\\f%s,%d %s", 
		deffont, 10, text));
end

function awb()
	settings.colourtable = system_load("scripts/colourtable.lua")();
	symtable = system_load("scripts/symtable.lua")();
	system_load("scripts/calltrace.lua")();
	system_load("scripts/3dsupport.lua")();
	system_load("scripts/mouse.lua")();

	system_load("awb_window.lua")();

--
-- the other icons are just referenced by string since they're managed by 
-- their respective windows
--
	imagery.cursor = load_image("awbicons/mouse.png", ORDER_MOUSE);
	image_tracetag(imagery.cursor, "mouse cursor");
	move_image(imagery.cursor, math.floor(VRESW * 0.5), math.floor(VRESW * 0.5));
	show_image(imagery.cursor);
	mouse_setup(imagery.cursor, ORDER_MOUSE, 1);
	mouse_acceleration(0.5);
	spawn_boing();
	spawn_boing();
	awb_desktop_setup();
end

function awb_desktop_setup()
	rootwnd = awbwnd_create({
		fullscreen = true,
		border     = false,
		borderw    = 2,
		mode       = "iconview",
		iconalign  = "right"
	});

	rootwnd:add_icon("Systems",  groupicn, groupselicn, deffont, deffont_sz, sysgrp);
	rootwnd:add_icon("Saves",    groupicn, groupselicn, deffont, deffont_sz, sfn);
	rootwnd:add_icon("Programs", groupicn, groupselicn, deffont, deffont_sz, prggrp);
	rootwnd:add_icon("Videos",   groupicn, groupselicn, deffont, deffont_sz, vidgrp);	

	local wbarcb = function() return fill_surface(VRESW, 24, 210, 210, 210); end
	local topbar = rootwnd:add_bar("top", wbarcb, wbarcb, 20);
	local tbl = topbar:add_icon(menulbl("Arcan Workbench"), "left", nil);
	tbl.yofs = 6;
	tbl.xofs = 6;
	tbl.stretch = false;	

	rootwnd:refresh_icons();
	rootwnd:show();
end

function prggrp(caller)
	prggrp_window = spawn_window("iconview", "left")
	prggrp_window:add_icon("Boing", "awbicons/boing.png", 
		"awbicons/boing.png", deffont, deffont_sz, spawn_boing);
	prggrp_window:refresh_icons();
end

function attrstr(self)
	return self.title;
end

function sysgame(caller)
	local gamelist = list_games({target = caller.name});
	local gametbl = gamelist[math.random(1, #gamelist)];
	local gamewin = spawn_window("container_managed");

	gamewin.active_vid = launch_target(gametbl.gameid, LAUNCH_INTERNAL, 
		function(source, status)
		if (status.kind == "resized") then
			gamewin:update_canvas(source);
		end
	end);

--	syslist = spawn_window("listview");
--	if (#gamelist) then
--		for ind, val in ipairs(gamelist) do
--			val.caption = attrstr;	
--		end

--		syslist:update_list(gamelist, gametoggle);
--		syslist.target = launch_target(LAUNCH_INTERNAL, gamefsrv_status);
--	end
end

function gametoggle(caller)
		
end

function sysvid(caller)
	local vidwin = spawn_window("container_managed");
	vidwin.active_vid =	load_movie("videos/" .. caller.res, 
		FRAMESERVER_NOLOOP, function(source, status) 
		if (status.kind == "resized") then
			vidwin.vid, vidwin.aid = play_movie(source);
			vidwin:update_canvas(source);
		end

	end);
end

function vidgrp(caller)
	local res = glob_resource("videos/*", THEME_RESOURCE);
	if (res and #res > 0) then
		local newvid = spawn_window("iconview", "left");

		for ind, val in ipairs(res) do
			local ent = newvid:add_icon(val, "awbicons/floppy.png", 
				"awbicons/floppysel.png", deffont, deffont_sz, sysvid);

			ent.res = val;
		end

		newvid:refresh_icons();
	end	
end

function sysgrp(caller)
	sysgroup_window = spawn_window("iconview", "left");
	local tgtlist = list_targets();

	for ind, val in ipairs(tgtlist) do
		local caps = launch_target_capabilities(val);
		if (caps and caps.internal_launch) then

			local resa = "images/systems/" .. val .. ".png";
			local resb = "icons/" .. val .. ".ico";
			
			if (resource(resa)) then
				sysgroup_window:add_icon(val, resa, resa, deffont, deffont_sz, sysgame);
			elseif (resource(resb)) then
				sysgroup_window:add_icon(val, resb, resb, deffont, deffont_sz, sysgame);
			else -- FIXME defaulticon
				local active = fill_surface(80, 20, 255, 0, 0);
				local inactive = fill_surface(80, 20, 0, 255, 0);
				sysgroup_window:add_icon(val, "awbicons/floppy.png", 
					"awbicons/floppysel.png", deffont, deffont_sz, sysgame);
			end
		end
	end

	sysgroup_window:refresh_icons();
end

--
-- A little hommage to the original, shader is from rendertoy
--
function spawn_boing()
	local int oval = math.random(1,100);
	local a = spawn_window("container", "left", "BOING!");
	a.name = "boingwnd" .. tostring(oval);
	local boing = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/boing.fShader", "boing" .. oval, {}); 
	local props = image_surface_properties(a.canvas);
	shader_uniform(boing, "display", "ff", PERSIST, props.width, props.height); 
	shader_uniform(boing, "offset", "i", PERSIST, oval); 

	image_shader(a.canvas, boing);
end

function focus_window(wnd)
	print("focus:", wnd);

	if (wnd == rootwnd or wnd == wlist.focus) then
		return;
	end

	if (wlist.focus) then
		print("wlist focus deactive?");

		wlist.focus:active(false);
		if (wlist.focus.iconsoff) then
			wlist.focus:iconsoff();
		end
		wlist.focus:reorder(ORDER_WDW);
	end

	print("wnd:", wnd, "focus:", wlist.focus);

	wlist.focus = wnd;
	wlist.focus:active(true);
end

function closewin(self)
	for ind, val in ipairs(wlist.windows) do
		if (val == self.parent.parent) then
			table.remove(wlist.windows, ind);
			if (wlist.focus == val) then
				wlist.focus = nil;
			end
			break;
		end

	end

	mouse_droplistener(self);
	self.parent.parent:destroy();
end

--
-- Allocate, Setup, Register and Position a new Window
-- These always start out focused
--
function spawn_window(wtype, ialign, caption)
	wcont = awbwnd_create({
		mode = wtype,
		iconalign = ialign,
		fullscreen = false,
		border  = true,
		borderw = 2,
		width   = 320,
		height  = 200,
		name = caption,
		x    = x_spawnpos,
		y    = y_spawnpos
	});

-- overload destroy to deregister mouse handler
	local tmpfun = wcont.destroy;
	local function wdestroy(self) 
		mouse_droplistener(self);
		tmpfun(self);
	end

	local bar = wcont:add_bar("top", "awbicons/border.png", 
		"awbicons/border_inactive.png", 16);
	bar:add_icon("awbicons/close.png",   "left",  closewin);

	if (caption) then	
		local captxt = menulbl(caption);
		local props  = image_surface_properties(captxt);
		local bg = fill_surface(math.floor(props.width * 0.1) + props.width, 
			16, 230, 230, 230);
		link_image(captxt, bg);
		image_inherit_order(captxt, true);
		order_image(captxt, 1);
		image_tracetag(bg, "capbg");
		image_mask_set(bg, MASK_UNPICKABLE);
		show_image({captxt, bg});
		blend_image(bg, 0.5);
		move_image(captxt, 4, 4);
		image_tracetag(captxt, "captxt");
-- don't want thee to interfere with bar drag 
		image_mask_set(captxt, MASK_UNPICKABLE);
		bar:add_icon(bg, "left", nil);
	end

	bar.drag = function(self, vid, x, y)
		local props = image_surface_resolve_properties(self.root);
		focus_window(self.parent);
		self.parent:move(props.x + x, props.y + y);
		print("drag:", props.x + x, props.y + y);
	end
 
	bar.dblclick = function(self, vid, x, y)
		print(self.parent.name, "doubleclick");
	end

	bar.click = function(self, vid, x, y)
		print(self.parent.name, "click");
		focus_window(self.parent);
	end

	local canvaseh = {};
	canvaseh.own = function(self, vid)
		return vid == wcont.canvas;
	end

	canvaseh.click = function(self, vid, x, y)
		focus_window(wcont);
	end

	mouse_addlistener(bar, {"drag", "click", "dblclick"});
	mouse_addlistener(canvaseh, {"click"});

	bar:add_icon("awbicons/enlarge.png", "right", maximize);
	bar:add_icon("awbicons/shrink.png",  "right", sendtoback);
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

minputtbl = {false, false, false};
function awb_input(iotbl)
	if (iotbl.kind == "analog" and iotbl.source == "mouse") then
		mouse_input(iotbl.subid == 0 and iotbl.samples[2] or 0, 
			iotbl.subid == 1 and iotbl.samples[2] or 0, minputtbl);

	elseif (iotbl.kind == "digital" and iotbl.source == "mouse") then
		if (iotbl.subid > 0 and iotbl.subid <= 3) then
			minputtbl[iotbl.subid] = iotbl.active;
			mouse_input(0, 0, minputtbl);
		end
	
	elseif (iotbl.kind == "digital" and iotbl.active and iotbl.translated) then
		if (symtable[iotbl.keysym] == "LCTRL") then
			toggle_mouse_grab();
		elseif (symtable[iotbl.keysym] == "ESCAPE") then
			shutdown();
		end	
	elseif (wlist.focus) then
		a = 1
	end
end

function awb_clock_pulse(stamp, nticks)
	mouse_tick(1);
end
