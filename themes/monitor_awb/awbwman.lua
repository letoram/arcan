--
-- AWB Window Manager,
-- More advanced windows from the (awbwnd.lua) base
-- tracking ordering, creation / destruction /etc.
--
-- Todolist:
--   -> Auto-hide occluded windows to limit overdraw
--   -> Tab- cycle focus window with out of focus shadowed
--   -> Fullscreen mode for window
--   -> Autohide for top menu bar on fullscreen
--   -> Drag and Drop for windows
--   -> Remember icon / window positions and sizes
--   -> Keyboard input for all windows
--   -> Animated resize effect

--
-- mapped up as "default_inverted", needed by some subclasses
-- (e.g. awbwnd_icon etc.)
--
local awbwnd_invsh = [[
uniform sampler2D map_diffuse;
uniform float obj_opacity;

varying vec2 texco;

void main(){
	vec4 col = texture2D(map_diffuse, texco);
	gl_FragColor = vec4(1.0 - col.r,
		1.0 - col.g, 
		1.0 - col.b,
		col.a * obj_opacity);
}
]];

local awb_wtable = {};
local awb_col = {};

local awb_cfg = {
-- window management
	wlimit      = 10,
	focus_locked = false,
	topbar_sz   = 16,
	spawnx      = 20,
	spawny      = 20,
	animspeed   = 10,
	meta        = {},
	hidden      = {},

-- root window icon management
	rootcell_w  = 80,
	rootcell_h  = 60,
	icnroot_startx = 0,
	icnroot_starty = 0,
	icnroot_stepx  = -40,
	icnroot_stepy  = 80,
	icnroot_maxy   = VRESH - 100,
	icnroot_x      = VRESW - 100,
	icnroot_y      = 30,

	global_vol = 1.0
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

function string.split(instr, delim)
	local res = {};
	local strt = 1;
	local delim_pos, delim_stp = string.find(instr, delim, strt);
	
	while delim_pos do
		table.insert(res, string.sub(instr, strt, delim_pos-1));
		strt = delim_stp + 1;
		delim_pos, delim_stp = string.find(instr, delim, strt);
	end
	
	table.insert(res, string.sub(instr, strt));
	return res;
end

local function drop_popup()
	if (awb_cfg.popup_active ~= nil) then
		awb_cfg.popup_active:destroy(awb_cfg.animspeed);
		awb_cfg.popup_active = nil;
	end
end

local function awbwman_focus(wnd, nodrop)
	if (nodrop == nil or nodrop == false) then
		drop_popup();
	end

	if (awb_cfg.focus) then
		if (awb_cfg.focus == wnd or awb_cfg.focus_locked) then
			return;
		end
		
-- only inactivate a window that hasn't been destroyed
		if (awb_cfg.focus.inactive) then
			awb_cfg.focus:inactive();
		else
			awb_cfg.focus = nil;
		end
	end

	wnd:active();
	awb_cfg.focus = wnd;
	local tbl = table.remove(awb_wtable, awbwman_findind(wnd));
	table.insert(awb_wtable, tbl);
	awbwman_updateorder();
end

function awbwman_ispopup(vid)
	return awb_cfg.popup_active and awb_cfg.popup_active.ref == vid;
end

function awbwman_shadow_nonfocus()
	if (awb_cfg.focus_locked == false and awb_cfg.focus == nil or
		awb_cfg.modal) then
		return;
	end

	awb_cfg.focus_locked = not awb_cfg.focus_locked;

	if (awb_cfg.focus_locked)  then
		local order = image_surface_properties(awb_cfg.focus.anchor).order;
		awb_cfg.shadowimg = color_surface(VRESW, VRESH, 0, 0, 0); 
		order_image(awb_cfg.shadowimg, order - 1);
		blend_image(awb_cfg.shadowimg, 0.5, awb_cfg.animspeed);
	else
		expire_image(awb_cfg.shadowimg, awb_cfg.animspeed);
		blend_image(awb_cfg.shadowimg, 0.0, awb_cfg.animspeed); 
	end
end

local function awbwman_dereg(wcont)
	for i=1,#awb_wtable do
		if (awb_wtable[i] == wcont) then
			table.remove(awb_wtable, i);
			break;
		end
	end
end

local function awbwman_close(wcont, nodest)
	drop_popup();
	awbwman_dereg(wcont);

	if (awb_cfg.focus == wcont) then
		awb_cfg.focus = nil;
		if (awb_cfg.focus_locked) then
			awbwman_shadow_nonfocus();
		end

		if (#awb_wtable > 0) then
			awbwman_focus(awb_wtable[#awb_wtable]);
		end
	end
end

local function awbwman_regwnd(wcont)
	drop_popup();

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
			wnd:move(math.floor(wnd.x), math.floor(wnd.y));
		end
	end

	bar.click = function(self, vid, x, y)
		awbwman_focus(self.parent);
	end

	bar.name = "awbwnd_default_tbarh";
  mouse_addlistener(bar, {"drag", "drop", "click", "dblclick"});
	table.insert(wnd.handlers, bar);
end

function awbwman_minimize_drop()
end

local function awbwman_addcaption(bar, caption)
	local props  = image_surface_properties(caption);
	local bgsurf = color_surface(10, 10, 230, 230, 230);
	local icn = bar:add_icon("caption", "fill", bgsurf);
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
	show_image(caption);
	image_inherit_order(caption, true);
	order_image(caption, 1);
	image_mask_set(caption, MASK_UNPICKABLE);
	move_image(caption, 2, 2 + math.floor(0.5 * (bar.size - props.height)));
end

function awbwman_activepopup()
	return awb_cfg.popup_active ~= nil;
end

function awbwman_cursortag()
	return awb_cfg.cursor_tag;
end

function cursortag_drop()
end

function cursortag_hint(on)
end

function awbwman_cancel()
end

function awb_clock_pulse(stamp, nticks)
	mouse_tick(1);
end

local wndbase = 1000;
function awbwman_spawn(caption, options)
	if (options == nil) then
		options = {};
	end
	
	options.animspeed = awb_cfg.animspeed;

-- load pos, size from there and update
-- the key in destroy
	if (options.x == nil) then
		local lx, ly = mouse_xy();
		options.x = math.floor(lx) - 60;
		options.y = math.floor(ly);
	end
	local wcont  = awbwnd_create(options);

	local mhands = {};
	local tmpfun = wcont.destroy;

	wcont.wndid = wndbase;
	wndbase = wndbase + 1;

-- default drag, click, double click etc.
	wcont.destroy = function(self, time)
		mouse_droplistener(self);
		mouse_droplistener(self.rhandle);
		mouse_droplistener(self.top);

		for i,v in ipairs(mhands) do
			mouse_droplistener(v);
		end

		awbwman_close(self);
		tmpfun(self, time);
	end

-- single color canvas (but treated as textured) for shader or replacement 
	local r = 0;
	local g = 0;
	local b = 100;

-- separate click handler for the canvas area
-- as more advanced windows types (selection etc.) may need 
-- to override
	local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
	wcont:update_canvas(canvas);

-- top windowbar
	local tbar = wcont:add_bar("t", awb_cfg.activeres,
		awb_cfg.inactiveres, awb_cfg.topbar_sz, awb_cfg.topbar_sz);

		if (options.nocaption == nil) then
			awbwman_addcaption(tbar, caption);
		end

	if (options.noicons == nil) then
		tbar:add_icon("cap", "l", awb_cfg.bordericns["close"], function()
			wcont:destroy(awb_cfg.animspeed);	
		end);

		tbar:add_icon("cap", "r", awb_cfg.bordericns["toback"], function()
			awbwman_pushback(wcont);
			awbwman_updateorder();
		end);
	end

-- "normal" right bar (no scrolling) is mostly transparent and 
-- lies above the canvas area. The resize button needs a separate 
-- mouse handler
	if (options.noresize == nil) then
		local rbar = wcont:add_bar("b", awb_cfg.alphares,
			awb_cfg.alphares, awb_cfg.topbar_sz - 2, awb_cfg.topbar_sz - 2); 

		image_mask_set(rbar.vid, MASK_UNPICKABLE);
		local icn = rbar:add_icon("resize", "r", awb_cfg.bordericns["resize"]);
		local rhandle = {};
		rhandle.drag = function(self, vid, x, y)
			awbwman_focus(wcont);
			if (awb_cfg.meta.shift) then
				if (math.abs(x) > math.abs(y)) then
					wcont:resize(wcont.w + x, 0);
				else
					wcont:resize(0, wcont.h + y);
				end
			else
				wcont:resize(wcont.w + x, wcont.h + y);
			end
		end
		rhandle.own = function(self, vid)
			return vid == icn.vid;
		end
		rhandle.name = "awbwindow_resizebtn";
		mouse_addlistener(rhandle, {"drag"});
		wcont.rhandle = rhandle; -- for deregistration
	end	

-- register, push to front etc.
  awbman_mhandlers(wcont, tbar);
	awbwman_regwnd(wcont);

	if (options.noborder == nil) then
		wcont:set_border(1, awb_col.dialog_border.r, 
			awb_col.dialog_border.g, awb_col.dialog_border.b);
	end

	hide_image(wcont.anchor);
	blend_image(wcont.anchor, 1.0, awb_cfg.animspeed);
	wcont:resize(wcont.w, wcont.h);
	wcont.focus = awbwman_focus;
	wcont.focused = function(self) 
		return self == awb_cfg.focus; 
	end

	return wcont;
end

--
-- Forced indirection to monitor configuration changes,
-- shouldn't happen outside support scripts
--
function awbwman_cfg()
	return awb_cfg;
end

--
-- While some input (e.g. whatever is passed as input 
-- to mouse_handler) gets treated elsewhere, as is meta state modifier,
-- the purpose of this function is to forward to the current 
-- focuswnd (if needed) or manipulate whatever is in the popup-slot,
-- and secondarily, pass through the active input layout and push
-- to the broadcast domain.
--
function awbwman_input(iotbl, keysym)

-- match configured from global?
-- else forward raw input 
	if (awb_cfg.popup_active and awb_cfg.popup_active.input ~= nil) then
		awb_cfg.popup_active:input(iotbl);
	
	elseif (awb_cfg.focus and 
			awb_cfg.focus.input ~= nil) then
		awb_cfg.focus:input(iotbl);
	end
end

function awbwman_shutdown()
	shutdown();
end

--
-- Load / Store default settings for window behavior etc.
--
function awbwman_init(defrndr, mnurndr)
	awb_cfg.meta       = {};
	awb_cfg.bordericns = {};
	awb_cfg.rooticns   = {};
	awb_cfg.defrndfun  = defrndr;
	awb_cfg.mnurndfun  = mnurndr;

	awb_col = system_load("scripts/colourtable.lua")();

	awb_cfg.activeres   = load_image("border.png");
	awb_cfg.inactiveres = load_image("border_inactive.png");
	awb_cfg.ttactiveres = load_image("tt_border.png");
	awb_cfg.ttinactvres = load_image("tt_border.png");
	awb_cfg.alphares    = fill_surface(32, 32, 50, 50, 200); 
	
	awb_cfg.bordericns["close"]    = load_image("close.png");
	awb_cfg.bordericns["resize"]   = load_image("resize.png");
	awb_cfg.bordericns["toback"]   = load_image("toback.png");

	build_shader(nil, awbwnd_invsh, "awb_selected");
end
