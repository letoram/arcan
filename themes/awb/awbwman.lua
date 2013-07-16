--
-- AWB Window Manager,
-- More advanced windows from the (awbwnd.lua) base
-- tracking ordering, creation / destruction /etc.
--

--
-- Spawn a normal class window with optional caption
--

-- #attic for now
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
-- /#attic

local awb_wtable = {};
local awb_cfg = {
	wlimit      = 10,
	activeres   = "awbicons/border.png",
	inactiveres = "awbicons/border_inactive.png",
	alphares    = "awbicons/alpha.png",
	topbar_sz   = 16,
	spawnx      = 0,
	spawny      = 0  
};

local function awbwman_findind(val)
	for i,v in ipairs(awb_wtable) do
		if (v == val) then
			return i;
		end
	end
end

local function awbwman_updateorder()
	local count = 0; 

	for i,v in ipairs(awb_wtable) do
		order_image(v.anchor, i * 10);
		count = count + 1;
	end
end

local function awbwman_pushback(wnd)
	if (awb_cfg.focus == wnd) then
		awb_cfg.focus = nil;
	end

	local ind = awbwman_findind(wnd);
	if (ind ~= nil and ind > 1) then
		table.remove(awb_wtable, ind);
		table.insert(awb_wtable, 1, wnd);
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
		if (awb_cfg.focus == wnd) then
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

local function awbwman_close(wcont)
	for i=1,#awb_wtable do
		if (awb_wtable[i] == wcont) then
			table.remove(awb_wtable, i);
			break;
		end
	end

	if (awb_cfg.focus == wcont) then
		awb_cfg.focus = nil;
		if (#awb_wtable > 0) then
			awbwman_focus(awb_wtable[#awb_wtable]);
		end
	end
	
	wcont:destroy(15);
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
	local mfact = (wnd.width * wnd.height) / (VRESW * VRESH);

-- just some magnification + stop against screen edges
	local dx = wnd.x + fx * 4;
	local dy = wnd.y + fy * 4;
	dx = dx >= 0 and dx or 0;
	dy = dy >= 0 and dy or 0;
	dx = (dx + wnd.width > VRESW) and (VRESW - wnd.width) or dx;
	dy = (dy + wnd.height > VRESH) and (VRESH - wnd.height) or dy;

	wnd:move(dx, dy, 10);
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
		mouse_droplistener(self.top);
		for i,v in ipairs(mhands) do
			mouse_droplistener(v);
		end

		tmpfun(self, time);
	end

-- single color canvas (but treated as textured)
-- for shader or replacement 
	local r = colortable.bgcolor[1];
	local g = colortable.bgcolor[2];
	local b = colortable.bgcolor[3];

-- separate click handler for the canvas area
-- as more advanced windows types (selection etc.) may need 
-- to override
	local canvas = fill_surface(wcont.width, wcont.height, r, g, b);
	wcont:update_canvas(canvas, true);
	local chandle = {};
	chandle.click = function(vid, x, y)
		awbwman_focus(wcont);
	end
	chandle.own = function(self,vid)
		return vid == canvas; 
	end
	chandle.vid = canvas;
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
		awb_cfg.alphares, awb_cfg.topbar_sz, 0);
	image_mask_set(rbar.vid, MASK_UNPICKABLE);
	local icn = rbar:add_icon("r", awb_cfg.bordericns["resize"]);
	local rhandle = {};
	rhandle.drag = function(self, vid, x, y)
		awbwman_focus(wcont);
		wcont:resize(wcont.width + x, wcont.height + y);
	end
	rhandle.own = function(self, vid)
		return vid == icn.vid;
	end
	mouse_addlistener(rhandle, {"drag"});

-- register, push to front etc.
  awbman_mhandlers(wcont, tbar);
	awbwman_regwnd(wcont);

	hide_image(wcont.anchor);
	blend_image(wcont.anchor, 1.0, 15);

	return wcont;
end

--
-- Load / Store default settings for window behavior etc.
--
function awbwman_init()
	awb_cfg.bordericns = {};
	awb_cfg.bordericns["close"]    = load_image("awbicons/close.png");
	awb_cfg.bordericns["resize"]   = load_image("awbicons/resize.png");
	awb_cfg.bordericns["toback"]   = load_image("awbicons/toback.png");
	awb_cfg.meta = {};
end
