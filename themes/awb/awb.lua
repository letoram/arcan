--
-- Arcan "Workbench" theme
-- "inspired" by certain older desktop / windowing UI
-- but mainly thought of as an experiment towards better 
-- networking features and testing out the API for more
-- desktop- kindof window management. 
--
wlist     = {
	windows = {};
};

settings = {
	mfact  = 0.2,
	mvol   = 1.0
};

sysicons   = {};
imagery    = {};
colortable = {};

groupicn    = "awbicons/drawer.png";
groupselicn = "awbicons/drawer_open.png";
deffont     = "fonts/topaz8.ttf";
deffont_sz  = 12;

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

-- shader function / model viewer
	system_load("scripts/3dsupport.lua")(); 

-- mouse abstraction layer (callbacks for click handlers,
-- motion events etc.)
	system_load("scripts/mouse.lua")();

	system_load("awbwnd.lua")();
	system_load("awbwman.lua")();

	settings.defwinw = math.floor(VRESW * 0.35);
	settings.defwinh = math.floor(VRESH * 0.35);

-- the imagery pool is used as a static data cache,
-- since the windowing subsystem need link_ calls to work
-- we can't use instancing, so instead we allocate a pool
-- and then share_storage
	imagery.cursor       = load_image("awbicons/mouse.png", ORDER_MOUSE);
	awbwman_init();	

-- 
-- look in resources/scripts/mouse.lua
-- for heaps more options (gestures, trails, autohide) 
--
	image_tracetag(imagery.cursor, "mouse cursor");
	mouse_setup(imagery.cursor, ORDER_MOUSE, 1);
	mouse_acceleration(0.5);

	spawn_boing();

--	for i=1,10 do
--		local tbl = spawn_boing();
--		move_image(tbl.anchor, math.random(VRESW), math.random(VRESH));
--	end

--	awb_desktop_setup();
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
		iconimg = render_text(string.format([[\f%s,%d\#dc2323 %s]], deffont,
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
	settings.mfact = settings.mfact +  (0.1 * direction);
	settings.mfact = settings.mfact >= 0.01 and settings.mfact or 0.0;
	settings.mfact = settings.mfact <   2.0 and settings.mfact or 2.0;

	local mwidth = deffont_sz * 12 + 10;
	mwidth = (VRESW*0.3) > mwidth and math.floor(VRESW * 0.3) or mwidth;
	progress_notify("Acceleration", 20, mwidth, settings.mfact / 2.0);

	mouse_acceleration(settings.mfact);
end

--
-- A little hommage to the original, shader is from rendertoy
--
function spawn_boing(caption)
	local int oval = math.random(1,100);
	local a = awbwman_spawn("BOING!");

	a.name = "boingwnd" .. tostring(oval);
	
	local boing = load_shader("shaders/fullscreen/default.vShader", 
		"shaders/boing.fShader", "boing" .. oval, {});
		
	local props = image_surface_properties(a.canvas.vid);
	a.canvas.resize = function(self, neww, newh)
		shader_uniform(boing, "display", "ff", PERSIST, neww, newh); 
		shader_uniform(boing, "offset", "i", PERSIST, oval);
		resize_image(self.vid, neww, newh);
	end

	image_shader(a.canvas.vid, boing);
	a.canvas:resize(props.width, props.height);
	return a;
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
	self.parent.parent:destroy(15);
end

function resizewnd(self, vid, x, y)
	self.parent:resize(self.parent.width + x, self.parent.height + y);
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
