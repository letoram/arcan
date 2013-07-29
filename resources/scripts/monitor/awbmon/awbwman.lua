--
-- AWBMon Window Manager
-- Just copied / edited down version of what's in the AWB theme 
-- dropped everything that has to do with popups, dialogs,
-- specialized window subtypes, rootwindow.
--
local awb_wtable = {};
local awb_col = {};
local awb_cfg = {
-- window management
	wlimit      = 10,
	focus_locked = false,
	activeres   = "scripts/monitor/awbmon/border.png",
	inactiveres = "scripts/monitor/awbmon/border_inactive.png",
	alphares    = "scripts/monitor/awbmon/alpha.png",
	topbar_sz   = 16,
	spawnx      = 20,
	spawny      = 20,
	animspeed   = 10,
	meta = {},
};

local function awbwman_findind(val)
	for i,v in ipairs(awb_wtable) do
		if (v == val) then
			return i;
		end
	end
end

local function awbwman_updateorder()
	for i,v in ipairs(awb_wtable) do
		if (v.anchor ~= nil) then
			order_image(v.anchor, i * 10);
		end
	end
end

local function awbwman_pushback(wnd)
	if (awb_cfg.focus == wnd) then
		awb_cfg.focus = nil;
	end

	local ind = awbwman_findind(wnd);
	if (ind ~= nil and ind > 1) then
		table.remove(awb_wtable, ind);
		table.insert(awb_wtable, ind - 1, wnd);
	end

	wnd:inactive();
end

function awbwman_meta(lbl, active)
	if (lbl ~= "shift") then
		return;
	end

	awb_cfg.meta.shift = active;
end

local function awbwman_focus(wnd)
	if (awb_cfg.focus) then
		if (awb_cfg.focus == wnd or awb_cfg.focus_locked) then
			return;
		end
		
		awbwman_pushback(awb_cfg.focus);
	end

	wnd:active();
	awb_cfg.focus = wnd;
	local tbl = table.remove(awb_wtable, awbwman_findind(wnd));
	table.insert(awb_wtable, tbl);
	awbwman_updateorder();
end

function awbwman_shadow_nonfocus()
	if (awb_cfg.focus_locked == false and awb_cfg.focus == nil) then
		return;
	end

	awb_cfg.focus_locked = not awb_cfg.focus_locked;

	if (awb_cfg.focus_locked)  then
		local order = image_surface_properties(awb_cfg.focus.anchor).order;
		order_image(awb_cfg.shadowimg, order - 1);
		blend_image(awb_cfg.shadowimg, 0.8, awb_cfg.animspeed);
	else
		blend_image(awb_cfg.shadowimg, 0.0, awb_cfg.animspeed); 
	end
end

local function awbwman_close(wcont)
	for i=1,#awb_wtable do
		if (awb_wtable[i] == wcont) then
			table.remove(awb_wtable, i);
			break;
		end
	end

	if (awb_cfg.focus == wcont) then
		awb_cfg.focus = nil;
		if (awb_cfg.focus_locked) then
			awbwman_shadow_nonfocus();
		end

		if (#awb_wtable > 0) then
			awbwman_focus(awb_wtable[#awb_wtable]);
		end
	end
	
	wcont:destroy(awb_cfg.animspeed);
end

local function awbwman_regwnd(wcont)
	table.insert(awb_wtable, wcont);
	awbwman_focus(wcont);
end

local function lineobj(src, x1, y1, x2, y2)
	local dx  = x2 - x1 + 1;
	local dy  = y2 - y1 + 1;
	local len = math.sqrt(dx * dx + dy * dy);

	resize_image(src, len, 2);

	show_image(src);
	rotate_image(src, math.deg( math.atan2(dy, dx) ) );
	move_image(src, x1, y1);
	image_origo_offset(src, -1 * (0.5 * len), -0.5);

	return line;
end

local function awbwnd_fling(wnd, fx, fy, bar)
	local len  = math.sqrt(fx * fx + fy * fy);
	local wlen = 0.5 * math.sqrt(VRESW * VRESW + VRESH * VRESH);
	local fact = 1 / (len / wlen);
	local time = (10 * fact > 20) and 20 or (10 * fact);

-- just some magnification + stop against screen edges
	local dx = wnd.x + fx * 8;
	local dy = wnd.y + fy * 8;
	dx = dx >= 0 and dx or 0;
	dy = dy >= 0 and dy or 0;
	dx = (dx + wnd.w > VRESW) and (VRESW - wnd.w) or dx;
	dy = (dy + wnd.h > VRESH) and (VRESH - wnd.h) or dy;

	wnd:move(dx, dy, 10 * fact);
end

local function awbman_mhandlers(wnd, bar)
--
-- for the drag and drop case, "fling" the window 
-- if shiftstate is set 
--
	bar.drag = function(self, vid, x, y)
		reset_image_transform(self.parent.anchor);
		local mx, my = mouse_xy();
		awbwman_focus(self.parent);

		if (awb_cfg.meta.shift) then	
			if (self.line_beg ~= nil) then
				lineobj(self.lineobj, self.line_beg[1], self.line_beg[2], mx, my);
				order_image(self.lineobj, ORDER_MOUSE - 1);
			else
				self.line_beg = {mx, my};
				self.lineobj = color_surface(1, 1, 225, 225, 225); 
			end
		else
			props = image_surface_resolve_properties(self.parent.anchor);
			self.line_beg = nil;
			wnd:move(props.x + x, props.y + y);
		end
	end
 
	bar.dblclick = function(self, vid, x, y)
		awbwman_focus(self.parent);

--
-- Note; change this into a real "maximize / fullscreen window" thing
-- where the top-bar becomes self-hiding, the own window bar is hidden
-- and any submenus added gets moved to the top-bar
--
		if (self.maximized) then
			wnd:move(self.oldx, self.oldy);
			wnd:resize(self.oldw, self.oldh);
			self.maximized = false;
		else
			self.maximized = true;
			self.oldx = wnd.x;
			self.oldy = wnd.y;
			self.oldw = wnd.w;
			self.oldh = wnd.h;
			wnd:move(0, 20);
			wnd:resize(VRESW, VRESH - 20);
		end
	end

	bar.drop = function(self, vid, x, y)
		awbwman_focus(self.parent);
		if (self.line_beg) then
			local mx, my = mouse_xy();
			local dx = mx - self.line_beg[1];
			local dy = my - self.line_beg[2];
			local ang = math.deg( math.atan2(dy, dx) );
			awbwnd_fling(wnd, dx, dy, ang);
			self.line_beg = nil;
			delete_image(self.lineobj);
			self.lineobj = nil;
		else
			props = image_surface_resolve_properties(self.parent.anchor);
			self.line_beg = nil;
			wnd:move(math.floor(props.x), math.floor(props.y));
		end
	end

	bar.click = function(self, vid, x, y)
		awbwman_focus(self.parent);
	end

  mouse_addlistener(bar, {"drag", "drop", "click", "dblclick"});
end

local function awbwman_addcaption(bar, caption)
	local props  = image_surface_properties(caption);
	local bgsurf = color_surface(10, 10, 220, 220, 220);
	local icn = bar:add_icon("fill", bgsurf);
	delete_image(icn.vid);

	if (props.height > (bar.size - 2)) then
		resize_image(caption, 0, bar.size);
		props = image_surface_properties(caption);
	end

	icn.maxsz = 3 + props.width * 1.1; 
	icn.vid = bgsurf;

	link_image(icn.vid, bar.vid);
	show_image(icn.vid);
	image_inherit_order(icn.vid, true);
	order_image(icn.vid, 0);
	image_mask_set(icn.vid, MASK_UNPICKABLE);

	link_image(caption, bgsurf);
	image_clip_on(caption);
	show_image(caption);
	image_inherit_order(caption, true);
	order_image(caption, 1);
	image_mask_set(caption, MASK_UNPICKABLE);
	move_image(caption, 2, 2 + math.floor(0.5 * (bar.size - props.height)));
end

function awbwman_gather_scatter()
	if (awb_cfg.focus_locked) then
		awbwman_shadow_nonfocus();
	end

	if (awb_cfg.scattered) then
		for ind, val	in ipairs(awb_wtable) do
			if (val.pos_memory) then
				move_image(val.anchor, val.pos_memory[1], 
					val.pos_memory[2], awb_cfg.animspeed);
					blend_image(val.anchor, 1.0, awb_cfg.animspeed);
			end
		end

		awb_cfg.scattered = nil;
	else
		for ind, val in ipairs(awb_wtable) do
			val.pos_memory = {val.x, val.y};

			if ( ( val.x + val.w * 0.5) < 0.5 * VRESW) then
				move_image(val.anchor,  -val.w, val.y, awb_cfg.animspeed);
				blend_image(val.anchor, 1.0, 9);
				blend_image(val.anchor, 0.0, 1);
			else
				move_image(val.anchor,  VRESW, val.y, awb_cfg.animspeed);
				blend_image(val.anchor, 1.0, 9);
				blend_image(val.anchor, 0.0, 1);
			end
		end
	
		awb_cfg.scattered = true;
	end
end

--
-- desired spawning behavior might change (i.e. 
-- best fit, random, centered, at cursor, incremental pos, ...)
--
local function awbwman_next_spawnpos()
	local oldx = awb_cfg.spawnx;
	local oldy = awb_cfg.spawny;
	
	awb_cfg.spawnx = awb_cfg.spawnx + awb_cfg.topbar_sz;
	awb_cfg.spawny = awb_cfg.spawny + awb_cfg.topbar_sz;

	if (awb_cfg.spawnx > VRESW * 0.75) then
		awb_cfg.spawnx = 0;
	end

	if (awb_cfg.spawny > VRESH * 0.75) then
		awb_cfg.spawny = 0;
	end

	return oldx, oldy;
end

function awbmon_clock_pulse(stamp, nticks)
	mouse_tick(1);
end

function awbwman_spawn(caption)
	local xp, yp = awbwman_next_spawnpos();

	local wcont  = awbwnd_create({	
		x = xp,
		y = yp
	});
	local mhands = {};
	local tmpfun = wcont.destroy;

-- default drag, click, double click etc.
	wcont.destroy = function(self, time)
		mouse_droplistener(self);
		mouse_droplistener(self.rhandle);
		mouse_droplistener(self.top);
		for i,v in ipairs(mhands) do
			mouse_droplistener(v);
		end

		tmpfun(self, time);
	end

-- single color canvas (but treated as textured)
-- for shader or replacement 
	local r = awb_col.bgcolor.r;
	local g = awb_col.bgcolor.g;
	local b = awb_col.bgcolor.b;

-- separate click handler for the canvas area
-- as more advanced windows types (selection etc.) may need 
-- to override
	local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
	wcont:update_canvas(canvas, true);
	local chandle = {};
	chandle.click = function(vid, x, y)
		awbwman_focus(wcont);
	end
	chandle.own = function(self,vid)
		return vid == canvas; 
	end
	chandle.vid = canvas;
	chandle.name = "awbwnd_canvas";
	mouse_addlistener(chandle, {"click"});
	table.insert(mhands, chandle);

-- top windowbar
	local tbar = wcont:add_bar("t", awb_cfg.activeres,
		awb_cfg.inactiveres, awb_cfg.topbar_sz, awb_cfg.topbar_sz);

		awbwman_addcaption(tbar, caption);

	tbar:add_icon("l", awb_cfg.bordericns["close"], function()
		awbwman_close(wcont);
	end);

	tbar:add_icon("r", awb_cfg.bordericns["toback"], function()
		awbwman_pushback(wcont);
		awbwman_updateorder();
	end);

-- "normal" right bar (no scrolling) is mostly transparent and 
-- lies above the canvas area. The resize button needs a separate 
-- mouse handler
	local rbar = wcont:add_bar("r", awb_cfg.alphares,
		awb_cfg.alphares, awb_cfg.topbar_sz - 2, 0);
	image_mask_set(rbar.vid, MASK_UNPICKABLE);
	local icn = rbar:add_icon("r", awb_cfg.bordericns["resize"]);
	local rhandle = {};
	rhandle.drag = function(self, vid, x, y)
		awbwman_focus(wcont);
		wcont:resize(wcont.w + x, wcont.h + y);
	end
	rhandle.own = function(self, vid)
		return vid == icn.vid;
	end
	rhandle.name = "awbwindow_resizebtn";
	mouse_addlistener(rhandle, {"drag"});
	wcont.rhandle = rhandle; -- for deregistration

-- register, push to front etc.
  awbman_mhandlers(wcont, tbar);
	awbwman_regwnd(wcont);

	wcont:set_border(1, awb_col.dialog_border.r, 
		awb_col.dialog_border.g, awb_col.dialog_border.b);

	hide_image(wcont.anchor);
	blend_image(wcont.anchor, 1.0, awb_cfg.animspeed);
	wcont:resize(wcont.w, wcont.h);
	
	return wcont;
end

--
-- Forced indirection to monitor configuration changes,
-- shouldn't happen outside support scripts
--
function awbwman_cfg()
	return awb_cfg;
end

function awbwman_input(iotbl, keysym)
	if (awb_cfg.focus and 
			awb_cfg.focus.input ~= nil) then
		awb_cfg.focus:input(iotbl, keysym);
	end
end

function awbwman_init(defrndr, mnurndr)
	awb_cfg.meta       = {};
	awb_cfg.bordericns = {};
	awb_cfg.rooticns   = {};
	awb_cfg.defrndfun  = defrndr;
	awb_cfg.mnurndfun  = mnurndr;

	awb_col = system_load("scripts/colourtable.lua")();
	awb_col.bgcolor = {r = 0, g = 85, b = 169, a = 1.0};
	awb_col.dialog_border = {r = 255, g = 255, b = 255, a = 1.0};

	awb_cfg.bordericns["close"] =load_image("/scripts/monitor/awbmon/close.png");
	awb_cfg.bordericns["resize"]=load_image("/scripts/monitor/awbmon/resize.png");
	awb_cfg.bordericns["toback"]=load_image("/scripts/monitor/awbmon/toback.png");
	awb_cfg.shadowimg = color_surface(VRESW, VRESH, 0, 0, 0);
end
