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
	activeres   = "awbicons/border.png",
	inactiveres = "awbicons/border_inactive.png",
	ttactiveres = "awbicons/tt_border.png",
	ttinactvres = "awbicons/tt_border.png",
	alphares    = "awbicons/alpha.png",
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

		awb_cfg.focus:inactive();
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

local function awbwman_close(wcont)
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
	
	wcont:destroy(awb_cfg.animspeed);
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

  mouse_addlistener(bar, {"drag", "drop", "click", "dblclick"});
end

local function awbwman_addcaption(bar, caption)
	local props  = image_surface_properties(caption);
	local bgsurf = color_surface(10, 10, 230, 230, 230);
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
	if (awb_cfg.modal) then
		return;
	end

	drop_popup();

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

local function next_iconspawn()
	local oldx = awb_cfg.icnroot_x;
	local oldy = awb_cfg.icnroot_y;

	awb_cfg.icnroot_y = awb_cfg.icnroot_y + awb_cfg.icnroot_stepy;

	if (awb_cfg.icnroot_y > awb_cfg.icnroot_maxy) then
		awb_cfg.icnroot_x = awb_cfg.icnroot_x + awb_cfg.icnroot_stepx;
		awb_cfg.icnroot_y = awb_cfg.starty;
	end

	return oldx, oldy;
end

function awbwman_iconwnd(caption, selfun, options)
	local wnd = awbwman_spawn(caption, options);

	awbwnd_iconview(wnd, 64, 48, 32, selfun, 
		fill_surface(32, 32, 
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		fill_surface(32, 32, 
			awb_col.dialog_sbar.r, awb_col.dialog_sbar.g, awb_col.dialog_sbar.b),
			"r"
	);

	return wnd;
end

function awbwman_mediawnd(caption, kind, source, options)
	local wnd = awbwman_spawn(caption, options);
	return wnd, awbwnd_media(wnd, kind, source, 
		awb_cfg.ttactiveres, awb_cfg.ttinactvres);
end

function awbwman_targetwnd(caption, options)
	local wnd = awbwman_spawn(caption, options);
	wnd:add_bar("tt", awb_cfg.ttactiveres, awb_cfg.ttinactvres, wnd.dir.t.rsize,
		wnd.dir.t.bsize);
	return wnd, awbwnd_target(wnd);
end

function awbwman_activepopup()
	return awb_cfg.popup_active ~= nil;
end

function awbwman_listwnd(caption, lineh, linespace, 
	colopts, selfun, renderfun, options)
	local wnd = awbwman_spawn(caption, options);

	opts = {
		rowhicol = {awb_col.bgcolor.r * 1.2, 
			awb_col.bgcolor.g * 1.2, awb_col.bgcolor.b * 1.2}
	};

	awbwnd_listview(wnd, lineh, linespace, colopts, selfun, renderfun, 
		fill_surface(32, 32, 
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		fill_surface(32, 32, 
			awb_col.dialog_sbar.r, awb_col.dialog_sbar.g,awb_col.dialog_sbar.b),
		fill_surface(32, 32,
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		"r", opts);

	return wnd;
end

--
-- Caption is a prerendered information string
-- Buttons is a itable of {caption, trigger}
-- Trying to close the window via other means uses buttons[cancelind] trigger
-- Modal prevents other actions until response has been provided 
--
function awbwman_dialog(caption, buttons, options, modal)
	if (options == nil) then
		options = {};
	end

	if (awb_cfg.focus_locked) then
		awbwman_shadow_nonfocus();
	end
	
	options.nocaption  = true;
	options.noicons    = true;
	options.noresize   = true;
	options.nominimize = true;

	image_tracetag(caption, "awbwman_dialog(caption)");
	local wnd = awbwman_spawn(caption, options); 
	image_tracetag(wnd.anchor, "awbwman_dialog.anchor");
	local tmptbl = {};

--
-- Size the new buttons after the biggest supplied one
--
	local maxw = 0;
	local maxh = 0;

	for i, v in ipairs(buttons) do
		local bprop = image_surface_properties(v.caption);
		maxw = bprop.width > maxw and bprop.width or maxw;
		maxh = bprop.height > maxh and bprop.height or maxh;
	end

-- Fit dialog to size of contents and center
	local bwidth  = math.floor(maxw * 1.2);
	local bheight = math.floor(maxh * 1.1);
	local capp    = image_surface_properties(caption);
	local wwidth  = (bwidth * #buttons + 20) > capp.width and 
		(bwidth * #buttons + 20) or capp.width;
	local wheight = bheight + capp.height + wnd.dir.t.size;

	wnd:resize(math.floor(wwidth * 1.2), math.floor(wheight * 2));
	move_image(wnd.anchor, math.floor(0.5 * (VRESW - wnd.w)),
		math.floor(0.5 * (VRESH - wnd.h)));

-- Link caption to window area, center (taking buttons into account)
	link_image(caption, wnd.canvas.vid);
	image_inherit_order(caption, true);
	show_image(caption);

	local wndprop = image_surface_properties(wnd.canvas.vid);
	move_image(caption, math.floor(0.5 * (wndprop.width - capp.width)),
		math.floor(0.5 * ((wndprop.height - bheight) - capp.height)) );

-- Generate buttons and link lifetime to parent (but track
-- mouse handlers separately)
	for i, v in ipairs(buttons) do
		local dlgc = awb_col.dialog_border;
		local bgc  = awb_col.bgcolor;
		local ccol = awb_col.dialog_caret;

		local border = color_surface(bwidth, bheight, dlgc.r, dlgc.g, dlgc.b);
		local button = color_surface(bwidth-2, bheight-2, bgc.r, bgc.g, bgc.b);

		image_tracetag(border, "awbwnd_dialog.border(" .. tostring(i) .. ")");
		image_tracetag(button, "awbwnd_dialog.button(" .. tostring(i) .. ")");
		link_image(border, wnd.canvas.vid);
		link_image(button, border);
		link_image(v.caption, button);
		image_inherit_order(button, true);
		image_inherit_order(border, true);
		image_inherit_order(v.caption, true);
		order_image(button, 1);
		order_image(v.caption, 2);
		image_mask_set(border, MASK_UNPICKABLE);
		image_mask_set(v.caption, MASK_UNPICKABLE);
		image_mask_set(caption, MASK_UNPICKABLE);

		local bevent = {
			own   = function(self, vid) return vid == button; end,
			click = function() v.trigger(wnd); awbwman_close(wnd); end,
			over  = function() image_color(button, ccol.r, ccol.g, ccol.b); end, 
			out   = function() image_color(button, bgc.r, bgc.g, bgc.b); end,
		};

		local capp = image_surface_properties(v.caption);
		show_image({button, border, v.caption});
		move_image(button, 1, 1);
		move_image(border, wndprop.width - i * (bwidth + 10), wndprop.height - 
			bheight - 10);
		move_image(v.caption, math.floor(0.5 * (bwidth - capp.width)),
			math.floor(0.5 * (bheight - (capp.height - 4) )));

		bevent.name = "awbdialog_button(" .. tostring(i) .. ")";
		mouse_addlistener(bevent, {"over", "out", "click"});
		table.insert(tmptbl, bevent);
	end

--
-- Add an invisible surface just beneath the dialog that grabs all input
--
	if (modal) then
		awb_cfg.modal = true;
		a = color_surface(VRESW, VRESH, 0, 0, 0);
		blend_image(a, 0.5);
		image_tracetag(a, "modal_block");
		order_image(a, image_surface_properties(wnd.anchor).order - 1);
		link_image(a, wnd.canvas.vid);
		image_mask_clear(a, MASK_POSITION);
	end

	wnd.on_destroy = function()
		for i, v in ipairs(tmptbl) do
			mouse_droplistener(v);
		end

		if (modal) then
			awb_cfg.modal = nil;
		end
	end

	return wnd;
end

function awbwman_cursortag()
	return awb_cfg.cursor_tag;
end

function cursortag_drop()
	resize_image(awb_cfg.cursor_tag.vid, 1, 1, awb_cfg.animspeed);
	blend_image(awb_cfg.cursor_tag.vid, 0.0, awb_cfg.animspeed);
	expire_image(awb_cfg.cursor_tag.vid, awb_cfg.animspeed);
	awb_cfg.cursor_tag = nil;
end

function cursortag_hint(on)
	local tvid = awb_cfg.cursor_tag.vid;

	if (on) then
		instant_image_transform(tvid);

		local props  = image_surface_initial_properties(tvid);
		local cprops = image_surface_properties(mouse_cursor());
		
		move_image(tvid, cprops.width - 5, cprops.height -5);
		blend_image(tvid, 1.0, awb_cfg.animspeed);
		image_transform_cycle(tvid, 1);
		resize_image(tvid,props.width * 1.1, props.height * 1.1, awb_cfg.animspeed);
		resize_image(tvid,props.width * 0.9, props.height * 0.9, awb_cfg.animspeed);
	else
		image_transform_cycle(awb_cfg.cursor_tag.vid, 0);
		instant_image_transform(awb_cfg.cursor_tag.vid);
		blend_image(awb_cfg.cursor_tag.vid, 0.3, awb_cfg.animspeed);
	end
end

--
-- Similar to a regular spawn, but will always have order group 0,
-- canvas click only sets group etc. somewhat simpler than the 
-- awbicon window type as we don't care about resize or rapidly 
-- changing dynamic sets of lots of icons
--
function awbwman_rootwnd()
	local wcont = awbwnd_create({
		x      = 0,
		y      = 0,
		w      = VRESW,
		h      = VRESH
	});

	local r = awb_col.bgcolor.r;
	local g = awb_col.bgcolor.g;
	local b = awb_col.bgcolor.b;
	local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
	wcont:update_canvas(canvas, true);

	local tbar = wcont:add_bar("t", "awbicons/topbar.png", 
		"awbicons/topbar.png", awb_cfg.topbar_sz, awb_cfg.topbar_sz);
	order_image(tbar.vid, ORDER_MOUSE - 5);

	tbar.rzfun = awbbaricn_rectresize;
	local cap = awb_cfg.mnurndfun("Arcan");
	local icn = tbar:add_icon("l", cap, function(self) end);
	delete_image(cap);

	icn.xofs = 4;
	icn.yofs = 2;

	cap = awb_cfg.mnurndfun("Windows");
	icn = tbar:add_icon("l", awb_cfg.mnurndfun("Windows"), function(self)
	end);
	icn.xofs = 4;
	icn.yofs = 2;

	wcont.set_mvol = function(self, val) awb_cfg.global_vol = val; end
	local icn = tbar:add_icon("r", awb_cfg.bordericns["volume_top"], function(self)
		awbwman_popupslider(0.01, awb_cfg.global_vol, 1.0, function(val)
			wcont:set_mvol(val);
		end, {ref = self.vid});
	end);

	image_mask_set(tbar.vid, MASK_UNPICKABLE);

	blend_image(wcont.dir.t.vid, 0.8);
	move_image(wcont.canvas, 0, -awb_cfg.topbar_sz);

	hide_image(wcont.anchor);
	blend_image(wcont.anchor, 1.0, awb_cfg.animspeed);

--
-- Most of the time, do nothing, 
-- when we have an item to drag and drop,
-- oscillate back and forth until they click
--
	local dndh = {
		own = function(self, vid)
			return vid == canvas; 
		end,

		out = function(self, vid)
			if (awb_cfg.cursor_tag) then
				awb_cfg.cursor_tag.hint(false);
			end
		end,

		over = function(self, vid)
			if (awb_cfg.cursor_tag) then
				awb_cfg.cursor_tag.hint(true);
			end
		end,

		click = function(self, vid)
			if (awb_cfg.cursor_tag and awb_cfg.on_rootdnd) then
				awb_cfg.on_rootdnd(awb_cfg.cursor_tag);
				awb_cfg.cursor_tag:drop();
			end
		end
	};

	mouse_addlistener(tbar, {"click"});
	mouse_addlistener(dndh, {"out", "over", "click"});
	awb_cfg.root = wcont;
end

function awbwman_cancel()
	if (close_dlg ~= nil) then
		return;
	end

	if (awb_cfg.cursor_tag) then
		awb_cfg.cursor_tag.drop();

	elseif (awb_cfg.popup_active) then
		drop_popup();
	else
	local btntbl = {
			{
				caption = awb_cfg.defrndfun("No"),
				trigger = function(owner) 
					close_dlg = nil;
				end
			},
			{
				caption = awb_cfg.defrndfun("Yes");
				trigger = function(owner) 
					awbwman_shutdown();
					close_dlg = nil;
				end
			}
	};

		awbwman_dialog( awb_cfg.defrndfun("Shutdown?"), btntbl, {}, true);
		close_dlg = true;
	end
end

function awb_clock_pulse(stamp, nticks)
	mouse_tick(1);
end

--
-- Window, border, position, event hook and basic destructor
--
local function awbwman_popupbase(props, options)
	if (options and options.ref and awb_cfg.popup_active and
		awb_cfg.popup_active.ref == options.ref) then
		return;
	end
	drop_popup();

	local mx, my;
	options = options ~= nil and options or {};

	if (options.x ~= nil) then
		mx = options.x;
		my = options.y;

	elseif (options.ref) then
		local props = image_surface_resolve_properties(options.ref);
		mx = props.x;
		my = props.y + props.height;
		image_shader(options.ref, "awb_selected");

	else
		mx, my = mouse_xy();
	end

	if (mx + props.width > VRESW) then
		mx = VRESW - props.width;
	end

	if (my + props.height > VRESH) then
		my = VRESH - props.height;
	end

	props.width  = props.width + 10;
	props.height = props.height + 10;

	local dlgc = awb_col.dialog_border;
	local border = color_surface(1, 1, dlgc.r, dlgc.g, dlgc.b); 
	local wnd    = color_surface(1, 1,
		awb_col.bgcolor.r,awb_col.bgcolor.g, awb_col.bgcolor.b);
	
	image_mask_set(border,    MASK_UNPICKABLE);

	order_image(border, max_current_image_order() - 5);
	image_inherit_order(wnd,       true);
	image_clip_on(wnd,       CLIP_SHALLOW);

	link_image(wnd, border);
	show_image({border, wnd});
	move_image(border, math.floor(mx), math.floor(my));
	move_image(wnd, 1, 1);

	resize_image(border, props.width+2, props.height+2, awb_cfg.animspeed);
	resize_image(wnd, props.width, props.height, awb_cfg.animspeed);

	return border, wnd, options;
end

--
-- Simple popup window ordered just below the mouse cursor 
--
function awbwman_popup(rendervid, lineheights, callbacks, options)
	local props = image_surface_properties(rendervid);
	local border, wnd, options = awbwman_popupbase(props, options);

	if (border == nil) then
		return;
	end

	local res = {
		name = "popuplist." .. tostring(rendervid),
		vid = wnd
	};

	local cc   = awb_col.dialog_caret;
	local cursor = color_surface(props.width, 10, cc.r, cc.g, cc.b); 

	link_image(rendervid, wnd);
	link_image(cursor, border);

	image_mask_set(rendervid, MASK_UNPICKABLE);
	image_mask_set(cursor,    MASK_UNPICKABLE);

	image_inherit_order(cursor,    true);
	image_inherit_order(rendervid, true);
	
	image_clip_on(cursor,    CLIP_SHALLOW);
	image_clip_on(rendervid, CLIP_SHALLOW);

	order_image(cursor,    1);
	order_image(rendervid, 2);

	show_image({rendervid, cursor});
	move_image({rendervid, cursor}, 1, 1);

	local line_y = function(yv, lheight)
-- find the matching pair and pick the closest one
		for i=1,#lheight-1 do
			local dy1 = lheight[i];
			local dy2 = lheight[i+1];

			if (dy1 <= yv and dy2 >= yv) then
				return dy1, i, (dy2 - dy1);
			end
		end

		return lheight[#lheight], #lheight, 10;
	end

	res.own = function(self, vid) 
		return vid == wnd; 
	end
	
	res.destroy = function()
		if (res.ref) then
			image_shader(res.ref, "DEFAULT");
		end

		expire_image(border, awb_cfg.animspeed);
		blend_image(border, 0, awb_cfg.animspeed);
		resize_image(border, 1, 1, awb_cfg.animspeed);
		resize_image(wnd, 1, 1, awb_cfg.animspeed);
		mouse_droplistener(res);
	end

	res.click = function(self, vid, x, y)
		local yofs, ind, hght = line_y(y - 
			image_surface_resolve_properties(wnd).y, lineheights);
			awb_cfg.popup_active:destroy();

			if (type(callbacks) == "function") then
				callbacks(ind);
			else
				callbacks[ind]();
			end
	end

	res.motion = function(self, vid, x, y)
		local yofs, ind, hght  = line_y(y - 
			image_surface_resolve_properties(wnd).y, lineheights);

		resize_image(cursor, props.width, hght);
		move_image(cursor, 1, yofs + 1);
	end
	
	res.ref = options.ref;
	awb_cfg.popup_active = res;
	mouse_addlistener(res, {"click", "motion"});
end

function awbwman_popupslider(min, val, max, updatefun, options)
	local cc     = awb_col.dialog_caret;
	local wc     = awb_col.bgcolor;
	local res    = {};

-- push these options into a fake prop table to fit popupbase()
	local props  = {}; 
	props.width  = (options and options.width ~= nil) and options.width or 15;
	props.height = (options and options.height ~= nil) and
		options.height or math.floor(VRESH * 0.1);

	local border, wnd, options = awbwman_popupbase(props, options);
	if (border == nil) then
		return;
	end
	
	local caret  = color_surface(1, 1, cc.r, cc.g, cc.b);
	if (caret == BADID) then
		delete_image(border);
		return;
	end

	local w = props.width;
	local h = props.height;

	res.step = math.ceil((h - 2) / (max - min));

	image_tracetag(border, "popupslider.border");
	image_tracetag(wnd,    "popupslider.wnd");
	image_tracetag(caret,  "popuslider.caret");

	link_image(caret, border);

	image_mask_set(caret, MASK_UNPICKABLE);
	image_inherit_order(caret, true);
	resize_image(caret, w - 2, res.step * (val - min));
	image_clip_on(caret, CLIP_SHALLOW);
	order_image(caret,1);
	show_image(caret);
	move_image(caret, 2, 2);

	res.vid = wnd;
	res.own = function(self, vid) return vid == wnd; end

	res.destroy = function()
		if (res.ref) then
			image_shader(res.ref, "DEFAULT");
		end

		expire_image(border, awb_cfg.animspeed);
		blend_image(border, 0.0, awb_cfg.animspeed);
		resize_image(border, 1,1, awb_cfg.animspeed);
		mouse_droplistener(res);
	end

-- increment or decrement (click on scrollbar vs. wnd)
	res.click = function(self, vid, x, y)
		local props = image_surface_resolve_properties(wnd);
		resize_image(caret, w - 2, y - props.y); 
		if (updatefun) then
			updatefun(((y - props.y) > 0 and (y - props.y) or 0.001)
				/ (h - 2) * (max - min) + min);
		end
	end

	res.drag = function(self, vid, x, y)
		x, y = mouse_xy();
		local wp = image_surface_resolve_properties(wnd);
		local yv = (y - wp.y) > (h - 2)
			and (h - 2) or (y - wp.y);

		yv = yv <= 0 and 0.001 or yv;
		resize_image(caret, w - 2, yv);

		if (updatefun) then
			updatefun(yv / (h - 2) * (max - min) + min);
		end
	end

	mouse_addlistener(res, {"click", "drag"});

	res.ref = options.ref;
	awb_cfg.popup_active = res;

	return res;
end

function awbwman_setup_cursortag(icon)
	drop_popup();
	if (awb_cfg.cursor_tag) then
		awb_cfg.cursor_tag:drop();
	end

	local icn_props = image_surface_properties(icon);

	local res = {
		vid    = null_surface(icn_props.width, icn_props.height),
		drop   = cursortag_drop,
		hint   = cursortag_hint,
		kind   = "unknown" 
	};

	local curs = mouse_cursor();
	icn_props = image_surface_properties(curs);
	image_mask_set(res.vid, MASK_UNPICKABLE);

	image_sharestorage(icon, res.vid); 
	link_image(res.vid, mouse_cursor());
	blend_image(res.vid, 0.8, awb_cfg.animspeed);
	move_image(res.vid, math.floor(icn_props.width * 0.5),
		math.floor(icn_props.height * 0.5));
	image_inherit_order(res.vid, true);

	awb_cfg.cursor_tag = res;
	return res;
end

function awbwman_minimize(wnd, icon)
-- have wnd generate iconic representation, 
-- we add a border and then set as rootwndicon with
-- the trigger set to restore
	wnd:hide(100, 0);
end

function awbwman_rootaddicon(name, captionvid, 
	iconvid, iconselvid, trig, icntbl)

	if (icntbl == nil) then
		icntbl = {};
	end
	
	icntbl.caption  = captionvid;
	icntbl.selected = false;
	icntbl.trigger  = trig;
	icntbl.name     = name;

	local val = get_key("rooticn_" .. name);
	if (val ~= nil and val.nostore == nil) then
		a = string.split(val, ",");
		icntbl.x = tostring(a[1]);
		icntbl.y = tostring(a[2]);
	end

	icntbl.toggle = function(val)
		if (val == nil) then
			icntbl.selected = not icntbl.selected;
		else
			icntbl.selected = val;
		end

		image_sharestorage(icntbl.selected and 
			iconselvid or iconvid, icntbl.vid);
	end

-- create containers (anchor, mainvid)
-- transfer icon storage to mainvid and position icon + canvas
	local props = image_surface_properties(iconvid);
	if (icntbl.x == nil) then
		icntbl.x, icntbl.y = next_iconspawn();
	end

	icntbl.anchor = null_surface(awb_cfg.rootcell_w, awb_cfg.rootcell_h);
	icntbl.vid    = null_surface(props.width, props.height); 
	image_sharestorage(iconvid, icntbl.vid);

	link_image(icntbl.vid, icntbl.anchor);
	link_image(icntbl.caption, icntbl.anchor);
	move_image(icntbl.caption, math.floor( 0.5 * (awb_cfg.rootcell_w - 
		image_surface_properties(captionvid).width)), props.height + 5);

	image_mask_set(icntbl.anchor, MASK_UNPICKABLE);
-- default mouse handlers (double-click -> trigger(), 
-- free drag / reposition, single click marks as active/inactive
	local ctable = {};
		ctable.own = function(self, vid)
		return vid == icntbl.vid or vid == icntbl.caption;
	end

	ctable.click = function(self, vid)
		drop_popup();

		for k,v in ipairs(awb_cfg.rooticns) do
			if (v ~= icntbl) then
				v.toggle(false);
			end
		end
		icntbl.toggle();
	end

	ctable.dblclick = function(self, vid)
		for k, v in ipairs(awb_cfg.rooticns) do
			v.toggle(false);
		end
		icntbl:trigger();
	end

	ctable.drop = function(self, vid, dx, dy)
		icntbl.x = math.floor(icntbl.x);
		icntbl.y = math.floor(icntbl.y);
		move_image(icntbl.anchor, icntbl.x, icntbl.y);
	end

	ctable.drag = function(self, vid, dx, dy)
		icntbl.x = icntbl.x + dx;
		icntbl.y = icntbl.y + dy;
		move_image(icntbl.anchor, icntbl.x, icntbl.y);
-- nudge windows so the region is free
	end

	order_image({icntbl.caption, icntbl.vid}, 5);
	blend_image({icntbl.anchor, icntbl.vid, icntbl.caption}, 
		1.0, awb_cfg.animspeed);
	move_image(icntbl.anchor, icntbl.x, icntbl.y);
	ctable.name = "rootwindow_button(" .. name .. ")";
	mouse_addlistener(ctable, {"drag", "drop", "click", "dblclick"});
	table.insert(awb_cfg.rooticns, icntbl);

	return icntbl;
end

local wndbase = math.random(1000);
function awbwman_spawn(caption, options)
	if (options == nil) then
		options = {};
	end
	
	if (options.refid ~= nil) then
		local kv = get_key(options.refid);
		if (kv ~= nil) then
			kv = tostring(kv);
			local strtbl = string.split(kv, ",");
			for i, j in ipairs(strtbl) do
				local arg = string.split(j, "=");
				options[arg[1]] = tonumber(arg[2]);
			end
		end
	end

-- load pos, size from there and update
-- the key in destroy
	if (options.x == nil) then
		options.x, options.y = awbwman_next_spawnpos();
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

		if (options.refid) then
			local key = string.format("w=%d,h=%d,x=%d,y=%d",
			wcont.w, wcont.h, wcont.x, wcont.y);
			store_key(options.refid, key);
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

		if (options.nocaption == nil) then
			awbwman_addcaption(tbar, caption);
		end

	if (options.noicons == nil) then
		tbar:add_icon("l", awb_cfg.bordericns["close"], function()
			awbwman_close(wcont);
		end);

		tbar:add_icon("r", awb_cfg.bordericns["toback"], function()
			awbwman_pushback(wcont);
			awbwman_updateorder();
		end);
	end

	if (options.nominimize == nil) then
		tbar:add_icon("r", awb_cfg.bordericns["minimize"], function()
			awbwman_minimize(wcont, true);
		end);
	end

-- "normal" right bar (no scrolling) is mostly transparent and 
-- lies above the canvas area. The resize button needs a separate 
-- mouse handler
	if (options.noresize == nil) then
		local rbar = wcont:add_bar("r", awb_cfg.alphares,
			awb_cfg.alphares, awb_cfg.topbar_sz - 2, 0);
		image_mask_set(rbar.vid, MASK_UNPICKABLE);
		local icn = rbar:add_icon("r", awb_cfg.bordericns["resize"]);
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
	wcont.focused = function(self) return self == awb_cfg.focus; end

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
	for i, v in ipairs(awb_cfg.rooticns) do
		local val = string.format("%d,%d", v.x, v.y);
		store_key("rooticn_" .. v.name, val);
	end
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

	awb_cfg.bordericns["minus"]    = load_image("awbicons/minus.png");
	awb_cfg.bordericns["plus"]     = load_image("awbicons/plus.png");
	awb_cfg.bordericns["clone"]    = load_image("awbicons/clone.png");
	awb_cfg.bordericns["r1"]       = load_image("awbicons/r1.png");
	awb_cfg.bordericns["g1"]       = load_image("awbicons/g1.png");
	awb_cfg.bordericns["b1"]       = load_image("awbicons/b1.png");
	awb_cfg.bordericns["close"]    = load_image("awbicons/close.png");
	awb_cfg.bordericns["resize"]   = load_image("awbicons/resize.png");
	awb_cfg.bordericns["toback"]   = load_image("awbicons/toback.png");
	awb_cfg.bordericns["minimize"] = load_image("awbicons/minus.png", 16, 16);
	awb_cfg.bordericns["play"]     = load_image("awbicons/play.png");
	awb_cfg.bordericns["pause"]    = load_image("awbicons/pause.png");
	awb_cfg.bordericns["input"]    = load_image("awbicons/joystick.png");
	awb_cfg.bordericns["volume"]   = load_image("awbicons/speaker.png");
	awb_cfg.bordericns["save"]     = load_image("awbicons/save.png");
	awb_cfg.bordericns["load"]     = load_image("awbicons/load.png");

	awb_cfg.bordericns["fastforward"] = load_image("awbicons/fastforward.png");
	awb_cfg.bordericns["volume_top"]  = load_image("awbicons/topbar_speaker.png");

	build_shader(nil, awbwnd_invsh, "awb_selected");

	awbwman_rootwnd();
end
