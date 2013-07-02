--
-- Amiga Workbench- Lookalike Theme
-- Conceived in a "how far can you get in 24 hours" hackathon
-- (wildly re-uses stuff from gridle to get that done however)
--
wlist    = {
	windows = {};
};

settings = {
	mfact = 0.2,
	mvol  = 1.0
};
sysicons = {};
imagery  = {};
colortable = {};

groupicn = "awbicons/drawer.png";
groupselicn = "awbicons/drawer_open.png";
deffont = "fonts/topaz8.ttf";
deffont_sz = 12;

colortable.bgcolor = {0, 85, 169};

x_spawnpos = 20;
y_spawnpos = 20;

ORDER_BGLAYER   = 1;
ORDER_ICONLAYER = 2;
ORDER_WDW       = 10;
ORDER_FOCUSWDW  = 30;
ORDER_OVERLAY   = 50;
ORDER_MOUSE     = 255;

kbdbinds = {};
kbdbinds["LCTRL"]  = toggle_mouse_grab;
kbdbinds["ESCAPE"] = shutdown;
kbdbinds["F11"]    = function() mouse_accellstep(-1); end
kbdbinds["F12"]    = function() mouse_accellstep(1);  end
kbdbinds["F9"]     = function() volume_step(-1);      end
kbdbinds["F10"]    = function() volume_step(1);       end

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

	settings.defwinw = math.floor(VRESW * 0.25);
	settings.defwinh = math.floor(VRESH * 0.25);
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

	rootwnd:add_icon("Systems",  groupicn, groupselicn, deffont, 
		deffont_sz, sysgrp);
	rootwnd:add_icon("Saves",    groupicn, groupselicn, deffont, 
		deffont_sz, sfn);
	rootwnd:add_icon("Programs", groupicn, groupselicn, deffont, 
		deffont_sz, prggrp);
	rootwnd:add_icon("Videos",   groupicn, groupselicn, deffont, 
		deffont_sz, vidgrp);	
	rootwnd:add_icon("Models",   groupicn, groupselicn, deffont,
		deffont_sz, modelgrp);

	local wbarcb = function() return fill_surface(VRESW, 24, 210, 210, 210); end
	local topbar = rootwnd:add_bar("top", wbarcb, wbarcb, 20);
	local tbl = topbar:add_icon(menulbl("Arcan Workbench"), "left", nil);
	tbl.yofs = 6;
	tbl.xofs = 6;
	tbl.stretch = false;	

	rootwnd.click = function(self, vid, x, y)
		local tbl = self:own(vid);
		if (tbl) then
			tbl:toggle();
		end
	end

	mouse_addlistener(rootwnd, {"click", "dblclick"});

	rootwnd:refresh_icons();
	rootwnd:show();
end

function prggrp(caller)
	prggrp_window = spawn_window("iconview", "left")
	prggrp_window:add_icon("Boing", "awbicons/boing.png", 
		"awbicons/boingsel.png", deffont, deffont_sz, spawn_boing);
	prggrp_window:refresh_icons();

	prggrp_window.click = function(self, vid, x, y)
		local icn = self:own(vid);
		if (icn) then
			icn:toggle();
		end
	end

	mouse_addlistener(prggrp_window, {"click"});
end

function attrstr(self)
	return self.title;
end

--
-- Spawn an overlay dialog that quickly expires,
-- used for presenting a numeric value (0..1) relative
-- to an icon or label 
-- 
function progress_notify(msg, rowheight, bwidth, level)
	if (lastnotify ~= nil and
		lastnotify ~= msg) then
		delete_image(infodlg);
	end

	if (valid_vid(infodlg)) then
		show_image(infodlg);
	else
		infodlg = fill_surface(bwidth, rowheight + deffont_sz + 10, 40, 40, 40);
		infobar = fill_surface(bwidth - 10, rowheight, 80, 80, 80);
		progbar = fill_surface(1, 1, 220, 35, 35);
		iconimg = render_text(string.format([[\ffonts/topaz8.ttf,%d\#dc2323 %s]],
			deffont_sz, msg));
		lastnotify = msg;
		move_image(infodlg, math.floor(VRESW * 0.5 - 0.5 * bwidth),
			math.floor(VRESH * 0.5 - 0.5 * rowheight));

		order_image(infodlg, ORDER_OVERLAY);
		order_image(iconimg, ORDER_OVERLAY);
		order_image(infobar, ORDER_OVERLAY);
		order_image(progbar, ORDER_OVERLAY);

		move_image(infobar, 5, deffont_sz + 5);
		move_image(iconimg, 5, 5);

		link_image(infobar, infodlg);
		link_image(progbar, infobar);
		link_image(iconimg, infodlg);

		show_image({infodlg, infobar, progbar, iconimg});
	end

-- reset timer, change the progress value
	expire_image(infodlg, 60);
	blend_image(infodlg, 1.0, 50);
	blend_image(infodlg, 0.0, 10);
	local props = image_surface_properties(infobar);
	if (level < 0.001) then
		hide_image(progbar);
	else
		show_image(progbar);
		resize_image(progbar, math.floor(props.width * level), props.height);
	end
end

function volume_step(direction)
	settings.mvol = settings.mvol + (0.1 * direction);
	settings.mvol = settings.mvol >= 0.01 and settings.mvol or 0.0;
	settings.mvol = settings.mvol <  1.0  and settings.mvol or 1.0;

	local mwidth = deffont_sz * 13 + 10;
	mwidth = (VRESW*0.3) > mwidth and math.floor(VRESW * 0.3) or mwidth;
	progress_notify("Master Volume", 20, mwidth, settings.mvol);

-- 
-- calculate how this affects the individual audio sources and
-- change accordingly? (or expand the interface to cover listener vol)
--
end

function mouse_accellstep(direction)
	settings.mfact = settings.mfact + (0.1 * direction);
	settings.mfact = settings.mfact >= 0.01 and settings.mfact or 0.0;
	settings.mfact = settings.mfact <   2.0 and settings.mfact or 2.0;

	local mwidth = deffont_sz * 12 + 10;
	mwidth = (VRESW*0.3) > mwidth and math.floor(VRESW * 0.3) or mwidth;
	progress_notify("Acceleration", 20, mwidth, settings.mfact / 2.0);

	mouse_acceleration(settings.mfact);
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
	if (wnd == rootwnd or wnd == wlist.focus) then
		return;
	end

	if (wlist.focus) then
		wlist.focus:active(false, ORDER_WDW);
		if (wlist.focus.iconsoff) then
			wlist.focus:iconsoff();
		end
	end

	wlist.focus = wnd;
	wlist.focus:active(true, ORDER_FOCUSWDW);
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
-- Generate default action handlers for the window titlebar
--
function wbar_ahandlers(wnd, bar)
	bar.drag = function(self, vid, x, y)
		local props = image_surface_resolve_properties(self.root);
		focus_window(wnd);
		wnd:move(props.x + x, props.y + y);
	end
 
	bar.dblclick = function(self, vid, x, y)
		if (self.maximized) then
			wnd:move(self.oldx, self.oldy);
			wnd:resize(self.oldw, self.oldh);
			self.maximized = false;
		else
			self.maximized = true;
			self.oldx = wnd.x;
			self.oldy = wnd.y;
			self.oldw = wnd.width;
			self.oldh = wnd.height;
			wnd:move(0, 20);
			wnd:resize(VRESW, VRESH - 20);
		end
	end

	bar.drop = function(self, vid, x, y)
		local props = image_surface_resolve_properties(self.root);
		wnd:move(math.floor(props.x), math.floor(props.y));
	end

	bar.click = function(self, vid, x, y)
		print(self.parent.name, "click");
		focus_window(wnd);
	end

	mouse_addlistener(bar, {"drag", "drop", "click", "dblclick"});
end

--
-- Allocate, Setup, Register and Position a new Window
-- These always start out focused
--
function spawn_window(wtype, ialign, caption)
	local wcont  = awbwnd_create({
		iconalign  = ialign,
		fullscreen = false,
		border  = true,
		borderw = 2,
		mode    = wtype,
		width   = settings.defwinw,
		height  = settings.defwinh,
		name = caption,
		x    = x_spawnpos,
		y    = y_spawnpos
	});

-- overload destroy to deregister mouse handler
	local tmpfun = wcont.destroy;
	local function wdestroy(self)
		mouse_droplistener(self);
		mouse_droplistener(self.top);
		tmpfun(self);
	end

-- for windows without a scrollbar (say canvas / stretch)
-- and no fullscreen, we add the resize button as linked to the border
	local rzimg = load_image("awbicons/resize.png");
	local props = image_surface_properties(rzimg);
	link_image(rzimg, wcont.bordert);
	image_inherit_order(rzimg, true);
	order_image(rzimg, 2);
	image_tracetag(rzimg, "resizebtn");

-- overload resize to cover the resize button
	local rzfun = wcont.resize;
	wcont.resize = function(self, newx, newy)
		rzfun(self, newx, newy);
		local bprops = image_surface_properties(self.canvas);
		move_image(rzimg, bprops.width - props.width + 2, bprops.height); 
		show_image(rzimg);
	end

	local bar = wcont:add_bar("top", "awbicons/border.png", 
		"awbicons/border_inactive.png", 16);
	bar:add_icon("awbicons/close.png",   "left",  closewin);

	if (caption) then	
		local captxt = menulbl(caption);
		image_tracetag(captxt, "captxt(" ..caption .. ")");
	
		local props  = image_surface_properties(captxt);
		local bg = fill_surface(math.floor(props.width * 0.1) + props.width, 
			16, 230, 230, 230);
		image_tracetag(bg, "capbg");

		link_image(captxt, bg);
		image_inherit_order(captxt, true);
		image_mask_set(bg, MASK_UNPICKABLE);
		show_image({captxt, bg});
		blend_image(bg, 0.5);
		move_image(captxt, 4, 4);

		order_image(captxt, 1);
-- don't want thee to interfere with bar drag 
		image_mask_set(captxt, MASK_UNPICKABLE);
		bar:add_icon(bg, "left", nil);
	end

	local canvaseh = {};
	canvaseh.own = function(self, vid)
		return vid == wcont.canvas;
	end

	canvaseh.click = function(self, vid, x, y)
		focus_window(wcont);
	end

	mouse_addlistener(canvaseh, {"click"});

	bar:add_icon("awbicons/enlarge.png", "right", maximize);
	bar:add_icon("awbicons/shrink.png",  "right", sendtoback);
	wcont:show();
		
	wbar_ahandlers(wcont, bar);

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
	
	elseif (iotbl.kind == "digital" and iotbl.active 
	 and iotbl.translated and kbdbinds[ symtable[iotbl.keysym] ]) then
	 	kbdbinds[ symtable[iotbl.keysym] ]();
	elseif (wlist.focus) then
		a = 1
	end
end

function awb_clock_pulse(stamp, nticks)
	mouse_tick(1);
end
