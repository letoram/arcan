--
-- AWB Window Manager,
-- More advanced windows from the (awbwnd.lua) base
-- tracking ordering, creation / destruction /etc.
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
	focus_locked = false,
	fullscreen  = nil,
	topbar_sz   = 16,
	spawnx      = 20,
	spawny      = 20,
	animspeed   = 10,
	bgopa       = 0.8,
	meta        = {},
	hidden      = {},
	global_input= {},
	amap        = {},

	spawn_method = "mouse",
-- the whole "cell allocation + nextspawn" strategy should
-- be entirely reworked, this is just crazy
	rootcell_w  = 80,
	rootcell_h  = 60,
	icnroot_startx = 0,
	icnroot_starty = 30,
	icnroot_stepx  = -80,
	icnroot_stepy  = 80,
	icnroot_maxy   = VRESH - 100,
	icnroot_x      = VRESW - 100,
	icnroot_y      = 30,
	tabicn_base = 32,
	global_vol = 1.0
};

local function awbwman_findind(val, tbl)
	if (tbl == nil) then
		tbl = awb_wtable;
	end

	for i,v in ipairs(tbl) do
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
	if (lbl ~= nil) then
		if (lbl == "alt") then
			awb_cfg.meta.alt = active;
		elseif (lbl ~= "shift") then
			return "";
		else
			awb_cfg.meta.shift = active;
			if (active == false) then
				awbwman_tablist_toggle(false);
			end
		end
	end

	local rkey = "";
	if (awb_cfg.meta.shift) then
		rkey = rkey .. "SHIFT";
	end


	if (awb_cfg.meta.alt) then
		rkey = rkey .. "ALT";
	end

	return rkey;
end

local function drop_popup()
	if (awb_cfg.popup_active ~= nil) then
		awb_cfg.popup_active:destroy(awb_cfg.animspeed);
		awb_cfg.popup_active = nil;
	end
end

--
-- Will receive mouse input events and cursor while be 
-- disabled while this state is active
--
function awbwman_mousefocus(wnd)
	blend_image( mouse_cursor(), 0.0, awb_cfg.animspeed );
	awb_cfg.mouse_focus = wnd;
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

function awbwman_fullscreen(wnd)
	awbwman_focus(wnd);
	if (awb_cfg.shadowimg ~= nil) then
		expire_image(awb_cfg.shadowimg, awb_cfg.animspeed);
		blend_image(awb_cfg.shadowimg, 0.0, awb_cfg.animspeed);
		awb_cfg.shadowimg = nil;
	end

	blend_image(mouse_cursor(), 0.0, awb_cfg.animspeed);

-- hide root window (will cascade and hide everything else)
	blend_image(awb_cfg.root.anchor, 0.0, awb_cfg.animspeed);
	for k, v in ipairs(awb_wtable) do
		blend_image(v.anchor, 0.0, awb_cfg.animspeed);
	end

	awb_cfg.mouse_focus = wnd;
	awb_cfg.fullscreen = {};

	local cprops = {
		width = wnd.w,  
		height = wnd.h 
	};

	local iprops = wnd:canvas_iprops();
	local ar = iprops.width / iprops.height;
	local wr = iprops.width / VRESW;
	local hr = iprops.height / VRESH;
	local dw, dh;

	if (hr > wr) then
		dw = math.floor(VRESH * ar);
		dh = VRESH;
	else
		dw = VRESW;
		dh = math.floor(VRESW / ar);
	end

	awb_cfg.focus:resize(dw, dh, true);

	local xp = math.floor(0.5 * (VRESW - dw));
	local yp = math.floor(0.5 * (VRESH - dh));

-- setup intermediate representation
	local vid = null_surface(dw, dh);
	image_sharestorage(awb_cfg.focus.canvas.vid, vid);
	blend_image(vid, 1.0, awb_cfg.animspeed);
	move_image(vid, xp, yp);
	show_image(vid);
	order_image(vid, max_current_image_order());
	if (wnd.on_fullscreen) then
		wnd:on_fullscreen(vid, true);
	end

-- store values for restoring
	awb_cfg.fullscreen.vid = vid;
	awb_cfg.fullscreen.props = cprops;
	awb_cfg.fullscreen.wnd = wnd;
	
-- force focus lock for mouse input etc.
	awb_cfg.focus_locked = true;
end

function awbwman_dropfullscreen()
-- reattach canvas to window
	blend_image(mouse_cursor(), 1.0, awb_cfg.animspeed);

 	for k, v in ipairs(awb_wtable) do
		blend_image(v.anchor, 1.0, awb_cfg.animspeed);
	end
	blend_image(awb_cfg.root.anchor, 1.0, awb_cfg.animspeed);

	local w = awb_cfg.fullscreen.props.width;
	local h = awb_cfg.fullscreen.props.height;

	awb_cfg.focus:resize(w, h, true);
		
	if (awb_cfg.fullscreen.wnd.on_fullscreen) then
		awb_cfg.fullscreen.wnd:on_fullscreen(vid, false);
	end

	delete_image(awb_cfg.fullscreen.vid);

	awb_cfg.mouse_focus = nil;
	awb_cfg.focus_locked = false;
	awb_cfg.fullscreen = nil;
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
		awb_cfg.shadowimg = nil;
	end
end

local function awbwman_dereg(tbl, wcont)
	for i=1,#tbl do
		if (tbl[i] == wcont) then
			table.remove(tbl, i);
			return true;
		end
	end

	return false;
end

local function awbwman_close(wcont, nodest)
	drop_popup();
	awbwman_dereg(awb_wtable, wcont);
	awbwman_dereg(awb_cfg.global_input, wcont);

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

-- quickfix to bug in origo_offset with -1 > n < 1 degrees
	local deg = math.deg( math.atan2(dy, dx) );
	if ( deg > -1.0 and deg < 1.0) then
		deg = deg < 0.0 and -1.0 or 1.0;
	end

	rotate_image(src, math.deg( math.atan2(dy, dx) ) );
	move_image(src, x1 + (dx * 0.5), y1 + (dy * 0.5)); 
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
	dy = dy >= awb_cfg.topbar_sz and dy or awb_cfg.topbar_sz;
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
		if (wnd.resizable == false) then
			return;
		end
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
			wnd:resize(VRESW, VRESH - 20, true);
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

local function awbwman_addcaption(bar, caption)
	if (bar.update_caption == nil) then
		bar.update_caption = awbwman_addcaption;
	else
		image_sharestorage(caption, bar.capvid);
		local props = image_surface_properties(caption);
		delete_image(caption);
		resize_image(bar.capvid, props.width, props.height);
		resize_image(bar.bgvid, 3 + props.width * 1.1, bar.size);
		return;
	end

	bar.update_caption = awbwman_addcaption;
--	bar.noresize_fill = false;
	local props  = image_surface_properties(caption);
	local bgsurf = fill_surface(10, 10, 230, 230, 230);
	local icn = bar:add_icon("caption", "fill", bgsurf);
	delete_image(bgsurf);	

	if (props.height > (bar.size - 2)) then
		resize_image(caption, 0, bar.size);
		props = image_surface_properties(caption);
	end

	icn.maxsz = math.floor(3 + props.width * 1.1);
	resize_image(icn.vid, icn.maxsz, bar.size);

	link_image(caption, icn.vid);
	show_image(caption);
	image_inherit_order(caption, true);
	order_image(caption, 1);
	image_mask_set(caption, MASK_UNPICKABLE);
	image_mask_set(icn.vid, MASK_UNPICKABLE);
	move_image(caption, 2, 2 + math.floor(0.5 * (bar.size - props.height)));
	image_clip_on(caption, CLIP_SHALLOW);
	bar.capvid = caption;
	bar.bgvid = icn.vid;
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
			if (not val.minimized and val.pos_memory) then
				move_image(val.anchor, val.pos_memory[1], 
					val.pos_memory[2], awb_cfg.animspeed);
					blend_image(val.anchor, 1.0, awb_cfg.animspeed);
			end
		end

		awb_cfg.scattered = nil;
	else
		for ind, val in ipairs(awb_wtable) do
			if (not val.minimized) then
				val.pos_memory = {val.x, val.y};
				if (val.w == nil) then
					val.w = 64;
					val.h = 32;
				end

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
		end
	
		awb_cfg.scattered = true;
	end
end

--
-- desired spawning behavior might change (i.e. 
-- best fit, random, centered, at cursor, incremental pos, ...)
--
local function awbwman_next_spawnpos(wnd)
	local oldx = awb_cfg.spawnx;
	local oldy = awb_cfg.spawny;

	if (awb_cfg.spawn_method == "mouse") then
		local x, y = mouse_xy();
		x = x - 16;

		if (wnd.canvasw + x > VRESW) then
			x = VRESW - wnd.canvasw;
		end

		if (wnd.canvash + y > VRESH) then
			y = VRESH - wnd.canvash;
		end

		if (y < awb_cfg.topbar_sz) then
			 y = awb_cfg.topbar_sz;
		end

		return x, y;

	else
		awb_cfg.spawnx = awb_cfg.spawnx + awb_cfg.topbar_sz;
		awb_cfg.spawny = awb_cfg.spawny + awb_cfg.topbar_sz;

		if (awb_cfg.spawnx > VRESW * 0.75) then
			awb_cfg.spawnx = 0;
		end

		if (awb_cfg.spawny > VRESH * 0.75) then
			awb_cfg.spawny = 0;
		end
	end

	return oldx, oldy;
end

local function next_iconspawn()
	local oldx = awb_cfg.icnroot_x;
	local oldy = awb_cfg.icnroot_y;

	awb_cfg.icnroot_y = awb_cfg.icnroot_y + awb_cfg.icnroot_stepy;

	if (awb_cfg.icnroot_y > awb_cfg.icnroot_maxy) then
		awb_cfg.icnroot_x = awb_cfg.icnroot_x + awb_cfg.icnroot_stepx; 
		awb_cfg.icnroot_y = awb_cfg.icnroot_starty;
	end

	return oldx, oldy;
end

function awbwman_iconwnd(caption, selfun, options)
	local wnd = awbwman_spawn(caption, options);
	wnd.kind = "icon";

	awbwnd_iconview(wnd, 64, 48, 32, selfun, 
		fill_surface(32, 32, 
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		fill_surface(32, 32, 
			awb_col.dialog_sbar.r, awb_col.dialog_sbar.g, awb_col.dialog_sbar.b),
			"r"
	);
	blend_image(wnd.canvas.vid, awb_cfg.bgopa);

	return wnd;
end

local function wsetup(subkind, subdescr, caption, source, options)
	if (options == nil) then
		options = {};
	end

	options.fullscreen = true;
	local wnd = awbwman_spawn(caption, options);
	wnd.kind = subdescr;
	wnd.ttbar_bg = awb_cfg.ttactiveres;

	if (subkind ~= nil) then
		local res = subkind(wnd, source, options);
		return wnd, res;
	end

	return wnd;
end

function awbwman_customwnd(fun, caption, source, options)
	return wsetup(fun, "custom", caption, source, options);
end

function awbwman_aplayer(caption, source, options)
	return wsetup(awbwnd_aplayer, "aplayer", caption, source, options);
end

function awbwman_modelwnd(caption, source, options)
	return wsetup(awbwnd_modelview, "3dmodel", caption, source, options);
end

function awbwman_mediawnd(caption, source, options)
	return wsetup(awbwnd_media, "frameserver", caption, source, options);
end

function awbwman_imagewnd(caption, source, options)
	return wsetup(awbwnd_media, "static", caption, source, options);
end

function awbwman_capwnd(caption, source, options)
	return wsetup(awbwnd_media, "capture", caption, source, options);
end

function awbwman_targetwnd(caption, options, capabilities)
	if (options == nil) then
		options = {};
	end

	options.fullscreen = true;
	local wnd = awbwman_spawn(caption, options);

	wnd.kind = "target";

	wnd:add_bar("tt", awb_cfg.ttactiveres, 
		awb_cfg.ttinactvres, wnd.dir.t.rsize, wnd.dir.t.bsize);
	return wnd, awbwnd_target(wnd, capabilities, options.factsrc);
end

function awbwman_activepopup()
	return awb_cfg.popup_active ~= nil;
end

function awbwman_inputattach(dst, lblfun, options)
--
-- Override to fit current global settings / skin 
--
	options.bgr = awb_col.bgcolor.r;
	options.bgg = awb_col.bgcolor.g;
	options.bgb = awb_col.bgcolor.b;

	local dlgc = awb_col.dialog_border;
	options.borderr = dlgc.r;
	options.borderg = dlgc.g;
	options.borderb = dlgc.b;

	options.borderw = 1;

	options.caretr = awb_col.dialog_caret.r;
	options.caretg = awb_col.dialog_caret.g;
	options.caretb = awb_col.dialog_caret.b;

	return awbwnd_subwin_input(dst, lblfun, options);
end

function awbwman_listwnd(caption, lineh, linespace, 
	colopts, selfun, renderfun, options)
	if (options == nil) then
		options = {};
	end

	local wnd = awbwman_spawn(caption, options);
	wnd.kind = "list";

	local opts = {
		rowhicol = {awb_col.bgcolor.r * 1.2, 
			awb_col.bgcolor.g * 1.2, awb_col.bgcolor.b * 1.2},
		double_single = options.double_single
	};

	awbwnd_listview(wnd, lineh, linespace, colopts, selfun, renderfun, 
		fill_surface(32, 32, 
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		fill_surface(32, 32, 
			awb_col.dialog_sbar.r, awb_col.dialog_sbar.g,awb_col.dialog_sbar.b),
		fill_surface(32, 32,
			awb_col.dialog_caret.r, awb_col.dialog_caret.g, awb_col.dialog_caret.b),
		"r", opts);

	blend_image(wnd.canvas.vid, awb_cfg.bgopa); 
	return wnd;
end

function awbwman_reqglobal(wnd)
	local res = awbwman_dereg(awb_cfg.global_input, wnd);

	if (not res and wnd.input ~= nil) then
		table.insert(awb_cfg.global_input, wnd);
		return true;
	end

	return false;
end

function awbwman_notice(msg)
end

function awbwman_alert(msg)
end

function awbwman_warning(msg)
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
	wnd.dlg_caption = caption;

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

-- Fit dialog to size of contents
	local capp = image_surface_properties(caption);
	local cpyofs = 0;
	local bwidth  = math.floor(maxw * 1.2);
	local bheight = math.floor(maxh * 1.1);
	local wwidth  = (bwidth * #buttons + 20) > capp.width and 
		(bwidth * #buttons + 20) or capp.width;
	local wheight = bheight + capp.height + wnd.dir.t.size;
	
-- attach input field if requested
	if (options.input) then
		options.input.owner = caption;
		options.input.noborder = false;
		options.input.borderw = 1;

		if (not options.input.w) then
			options.input.w = 128;
		end

		wwidth  = options.input.w > wwidth and options.input.w or wwidth;
		wheight = wheight + 20;
		cpyofs  = -20;

		wnd.inputfield = awbwman_inputattach( function(self) wnd.msg = self.msg; end,
		desktoplbl, options.input );
		wnd.input  = function(self, tbl) wnd.inputfield:input(tbl); end
		wnd.inputfield.accept = function(self)
			buttons[options.input.accept].trigger(wnd);
			wnd:destroy(awb_cfg.animspeed);
		end

		move_image(wnd.inputfield.anchor, 
			math.floor( 0.5 * (capp.width - options.input.w)), capp.height + 5);
	end

-- center
	wnd:resize(math.floor(wwidth * 1.2), math.floor(wheight * 2));

	if (not options.nocenter) then
		move_image(wnd.anchor, math.floor(0.5 * (VRESW - wnd.w)),
			math.floor(0.5 * (VRESH - wnd.h)));
	end

-- Link caption to window area, center (taking buttons into account)
	link_image(caption, wnd.canvas.vid);
	image_inherit_order(caption, true);
	show_image(caption);

	wnd.update_caption = function(self, capvid)
		delete_image(self.dlg_caption);
		self.dlg_caption = capvid;
		local props = image_surface_properties(capvid);
		local cprop = image_surface_properties(self.canvas.vid);

		move_image(capvid, math.floor(0.5 * (cprop.width - props.width)),
			math.floor(0.5 * ( (cprop.height - bheight - 10) - props.height)));
	
		image_mask_set(caption, MASK_UNPICKABLE);
		link_image(capvid, self.canvas.vid);
		image_inherit_order(capvid, true);
		order_image(capvid, 2);
		show_image(capvid);
	end

	local wndprop = image_surface_properties(wnd.canvas.vid);
	move_image(caption, math.floor(0.5 * (wndprop.width - capp.width)),
		math.floor(0.5 * ((wndprop.height - bheight) - capp.height)) + cpyofs );

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
		blend_image(wnd.canvas.vid, awb_cfg.bgopa);

		local bevent = {
			own   = function(self, vid) return vid == button; end,
			click = function() if (v.trigger(wnd) == nil) then
				wnd:destroy(awb_cfg.animspeed); end end,
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
		table.insert(wnd.handlers, bevent);
	end

--
-- Add an invisible surface just beneath the dialog that grabs all input
--
	if (modal) then
		awb_cfg.modal = true;
		local a = color_surface(VRESW, VRESH, 0, 0, 0);
		blend_image(a, 0.5);
		image_tracetag(a, "modal_block");
		order_image(a, image_surface_properties(wnd.anchor).order - 1);
		link_image(a, wnd.canvas.vid);
		image_mask_clear(a, MASK_POSITION);
	end

--
-- Need to be first in the on_destroy chain to manage a. modal dialogs,
-- b. windows that need some kind of confirmation before being destroyed
-- as there might be unsaved state that will be lost
--
	wnd.on_destroy = function()
		if (wnd.confirm_destroy ~= nil) then
			awbwman_confirm_dialog(wnd.confirm_destroy, 
				wnd.wndid, function() wnd.confirm_destroy = nil; wnd:destroy(); end);
			return true;
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

function awbwman_minimize_drop(wnd)
	awbwman_dereg(awb_cfg.hidden, wnd);	
end

function awbwman_restore(ind)
	drop_popup();

	if (type(ind) == "table") then
		ind = awbwman_findind(ind, awb_cfg.hidden);
		if (ind == nil) then
			return;
		end
	end
	
	local wnd = awb_cfg.hidden[ind];
	wnd.minimized = false;
	table.remove(awb_cfg.hidden, ind);
	table.insert(awb_wtable, wnd);
	awbwman_focus(wnd);
	wnd:show();
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

	wcont.kind = "root";

	local r = awb_col.bgcolor.r;
	local g = awb_col.bgcolor.g;
	local b = awb_col.bgcolor.b;
	local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
	wcont:update_canvas(canvas);

	local tbar = wcont:add_bar("t", load_image("awbicons/topbar.png"), 
		load_image("awbicons/topbar.png"), awb_cfg.topbar_sz, awb_cfg.topbar_sz,
		{mouse_nodefault = true});
	order_image(tbar.vid, ORDER_MOUSE - 5);

	tbar.name = "rootwnd_topbar";
	tbar.rzfun = awbbaricn_rectresize;
	local cap = menulbl("AWB ");

	local awblist = {
		"Reset Background",
		"Help...",
		"Quit"
	};

	local ftbl = {
		function() 
			local r = awb_col.bgcolor.r;
			local g = awb_col.bgcolor.g;
			local b = awb_col.bgcolor.b;
			local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
			image_sharestorage(canvas, wcont.canvas.vid);
			delete_image(canvas);
			zap_resource("background.png");
		end,
		function()
			show_help(); 
		end,
		function()
			awbwman_shutdown();
		end
	};

	local icn = tbar:add_icon("cap", "l", cap, function(self) 
		local vid, list = awb_cfg.defrndfun(table.concat(awblist, [[\n\r]]));
		awbwman_popup(vid, list, ftbl ,{ref = self.vid} )
	end);
	delete_image(cap);

	icn.xofs = 2;
	icn.yofs = 2;

	cap = awb_cfg.mnurndfun(MESSAGE["ROOT_WINDOW"]);
	icn = tbar:add_icon("windows", "l", awb_cfg.mnurndfun("Windows"), function(self)
		if (#awb_cfg.hidden == 0) then
			return;
		end

		local lst = {};
		for i,v in ipairs(awb_cfg.hidden) do
			table.insert(lst, v.name);
		end

		local vid, list = awb_cfg.defrndfun(table.concat(lst, [[\n\r]]));
		awbwman_popup(vid, list, function(ind)
			if (ind ~= -1) then
				awbwman_restore(ind);
			end
		end, {ref = self.vid} );
	end);
	icn.xofs = 12;
	icn.yofs = 2;

	wcont.set_mvol = function(self, val)
		awb_cfg.global_vol = val; 
-- propagate new settings
		for i, v in ipairs(awb_cfg.hidden) do
			if (v.set_mvol ~= nil) then
				v:set_mvol(v.mediavol);
			end
		end

		for i, v in ipairs(awb_wtable) do
			if (v.set_mvol ~= nil) then
				v:set_mvol(v.mediavol);
			end
		end
	end

	local vicn = tbar:add_icon("vol", "r",awb_cfg.bordericns["volume_top"],
		function(self)
			awbwman_popupslider(0.01, awb_cfg.global_vol, 1.0, function(val)
				wcont:set_mvol(val);
			end, {ref = self.vid});
		end);

	awb_cfg.mouseicn = tbar:add_icon("mouse", "r", awb_cfg.bordericns["mouse"],
		function(self)
			awbwman_mousepop(self.vid);
		end);

	awb_cfg.minimize_x = image_surface_properties(icn.vid).x;

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
		name = "rootwnd_drag_n_droph",
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
			for k,v in ipairs(awb_cfg.rooticns) do
				if (v ~= icntbl) then
					v.toggle(false);
				end
			end

			if (awb_cfg.cursor_tag) then
				if (awb_cfg.on_rootdnd) then
					awb_cfg.on_rootdnd(awb_cfg.cursor_tag);
				end
				awb_cfg.cursor_tag:drop();
			else
				drop_popup();
			end
		end
	};

	wcont.click_h = function()
		drop_popup();
		if (awb_cfg.focus) then
			awb_cfg.focus:inactive();
			awb_cfg.focus = nil;
		end
	end

	mouse_addlistener(tbar, {"click"});
	mouse_addlistener(dndh, {"out", "over", "click"});
	awb_cfg.root = wcont;
end

local confirmtbl = {};
function awbwman_confirm_dialog(msg, id, trigfun, modal)
	if (confirmtbl[id] == true) then
		return;
	end

	local btntbl = {
	{
		caption = awb_cfg.defrndfun("No"),
		trigger = function(owner) 
			confirmtbl[id] = nil;
		end
	},
	{
		caption = awb_cfg.defrndfun("Yes");
		trigger = function(owner) 
			confirmtbl[id] = nil;
			trigfun();
		end
	}
	};

	awbwman_dialog(awb_cfg.defrndfun(msg), btntbl, {}, modal);
	confirmtbl[id] = true;
end

function awbwman_cancel()
	if (awb_cfg.fullscreen ~= nil) then
		awbwman_dropfullscreen();
		return true;
	end

	if (awb_cfg.mouse_focus) then
		blend_image(mouse_cursor(), 1.0, awb_cfg.animspeed);
		awb_cfg.mouse_focus = nil;
		return true;
	end

	if (awb_cfg.cursor_tag) then
		awb_cfg.cursor_tag.drop();

	elseif (awb_cfg.popup_active) then
		drop_popup();
	else
		awbwman_confirm_dialog("Shutdown?", "shutdowndlg", shutdown, true);
	end
end

function awb_clock_pulse(stamp, nticks)
	mouse_tick(1); -- hovers etc.

 -- chain to windows that need clock
	for i,v in ipairs(awb_wtable) do 
		if (v.clock_pulse) then
			v:clock_pulse(stamp, nticks);
		end
	end

	if (DEBUGLEVEL > 0) then
		local a, b = current_context_usage();

		if (valid_vid(DEBUG_usage)) then
			delete_image(DEBUG_usage);
		end

		DEBUG_usage = desktoplbl(string.format("%d/%d", a, b));
		show_image(DEBUG_usage);
		order_image(DEBUG_usage, max_current_image_order());
		move_image(DEBUG_usage, 0, 
			VRESH - image_surface_properties(DEBUG_usage).height);
	end
end


--
-- Window, border, position, event hook and basic destructor
--
local function awbwman_popupbase(props, options)
	if (options and options.ref and awb_cfg.popup_active and
		awb_cfg.popup_active.ref == options.ref) then
		drop_popup();
		return nil;
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
		image_shader(options.ref, options.sel_shader ~= nil and
			options.sel_shader or "awb_selected");

	else
		mx, my = mouse_xy();
	end

	props.width  = props.width + 10;
	props.height = props.height + 10;

	if (mx + props.width > VRESW) then
		mx = VRESW - props.width;
	end

	if (my + props.height > VRESH) then
		my = VRESH - props.height;
	end

-- re-use the border function from awbwnd
	local dlgc = awb_col.dialog_border;
	local border = {};

	border.resize = function(self, neww, newh, completed, dt)
		self.w = neww;
		self.h = newh;
		resize_image(self.anchor, neww, newh, dt);
	end

	border.anchor = null_surface(1, 1);
	border.w = props.width;
	border.h = props.height;

	awbwnd_set_border(border, 1, dlgc.r, dlgc.g, dlgc.b);

	local wnd = fill_surface(1, 1, 
		awb_col.bgcolor.r,awb_col.bgcolor.g, awb_col.bgcolor.b);
	
	order_image(border.anchor, max_current_image_order() - 4);
	image_inherit_order(wnd, true);
	image_clip_on(wnd, CLIP_SHALLOW);

	link_image(wnd, border.anchor);
	blend_image(border.anchor, 1.0, awb_cfg.animspeed);
	blend_image(wnd, awb_cfg.bgopa);

	move_image(border.anchor, math.floor(mx), math.floor(my));
	move_image(wnd, 1, 1);

	props.width = (options.minw and options.minw > props.width) and 
		options.minw or props.width;

	props.height = (options.minh and options.minh > props.height) and
		options.minh or props.height;

	border:resize(props.width, props.height, true, awb_cfg.animspeed); 
	resize_image(wnd, props.width, props.height, awb_cfg.animspeed);

	return border, wnd, options;
end

--
-- Simple popup window ordered just below the mouse cursor or
-- other points of reference.
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
	res.cursor = cursor;
	
	res.border = border;
	link_image(rendervid, border.anchor);
	link_image(cursor, border.anchor);

	image_mask_set(rendervid, MASK_UNPICKABLE);
	image_mask_set(cursor,    MASK_UNPICKABLE);

	image_inherit_order(cursor,    true);
	image_inherit_order(rendervid, true);
	
	image_clip_on(cursor);    
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

		expire_image(border.anchor, awb_cfg.animspeed);
		blend_image(border.anchor, 0, awb_cfg.animspeed);
		border.w = 1;
		border.h = 1;
		border:resize(1, 1, true, awb_cfg.animspeed);
		resize_image(wnd, 1, 1, awb_cfg.animspeed);

		mouse_droplistener(res);
		awb_cfg.popup_active = nil;
	end

	local btnh = function(self, vid, x, y, left)
		local yofs, ind, hght = line_y(y - 
			image_surface_resolve_properties(wnd).y, lineheights);

		if (awb_cfg.popup_active) then
			awb_cfg.popup_active:destroy(awb_cfg.animspeed);
		end
		awb_cfg.popup_active = nil;

		if (type(callbacks) == "function") then
			callbacks(ind, left);
		else
			callbacks[ind](left);
		end
	end

	res.click = function(self, vid, x, y) btnh(self, vid, x, y, true); end
	res.rclick = function(self, vid, x, y) btnh(self, vid, x, y, false); end

	res.motion = function(self, vid, x, y)
		local yofs, ind, hght  = line_y(y - 
		image_surface_resolve_properties(wnd).y, lineheights);

		resize_image(cursor, props.width, hght);
		move_image(cursor, 1, yofs + 1);
	end
					
	res.ref = options.ref;
	awb_cfg.popup_active = res;
	res.name = "awbwman_popup";
	mouse_addlistener(res, {"click", "rclick", "motion"});

	return res;
end

function awbwman_popupslider(min, val, max, updatefun, options)
	if (options.ref and awbwman_ispopup(options.ref)) then
		drop_popup();
		return;
	end

	if (options.win) then
		options.win:focus();
	end

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

	image_tracetag(border.anchor, "popupslider.border");
	image_tracetag(wnd,    "popupslider.wnd");
	image_tracetag(caret,  "popupslider.caret");

	link_image(caret, border.anchor);

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

		expire_image(border.anchor, awb_cfg.animspeed);
		blend_image(border.anchor, 0.0, awb_cfg.animspeed);
		border:resize(1, 1, true, awb_cfg.animspeed);
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

	res.name = "awbwman_popupslider";
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
	drop_popup();
	wnd:hide(awb_cfg.minimize_x, 0);
	wnd.minimized = true;
	table.remove(awb_wtable, awbwman_findind(awb_wtable, wnd));
	table.insert(awb_cfg.hidden, wnd);
end

function awbwman_rootgeticon(name)
	for i,j in ipairs(awb_cfg.rooticns) do
		if (j.name == name) then
			return name;
		end
	end
end

function awbwman_rootaddicon(name, captionvid, 
	iconvid, iconselvid, trig, rtrigger, icntbl)

	if (icntbl == nil) then
		icntbl = {};
	end

	icntbl.selected = false;
	icntbl.trigger  = trig;
	icntbl.rtrigger = rtrigger;
	icntbl.name     = name;
	
	local props = image_surface_properties(iconvid);
	if (icntbl.w == nil) then
		icntbl.w = props.width; 
	end

	if (icntbl.h == nil) then
		icntbl.h = props.height; 
	end

	local val = get_key("rooticn_" .. name);
	if (val ~= nil and val.nostore == nil) then
		local a = string.split(val, ":");
		icntbl.x = math.floor(VRESW * tonumber_rdx(a[1]));
		icntbl.y = math.floor(VRESH * tonumber_rdx(a[2]));
	end

	icntbl.toggle = function(val)
		if (val == nil) then
			icntbl.selected = not icntbl.selected;
		else
			icntbl.selected = val;
		end

		if (iconselvid == iconvid) then
			image_shader(icntbl.vid, icntbl.selected 
				and "awb_selected" or "DEFAULT");
		else
			image_sharestorage(icntbl.selected and 
				iconselvid or iconvid, icntbl.vid);
		end
	end

	icntbl.destroy = function(self)
		table.remove(awb_cfg.rooticns, awbwman_findind(self, awb_cfg.rooticns));
		delete_image(self.anchor);
		mouse_droplistener(self.mhandler);
		for i,v in pairs(self) do
			self[i] = nil;
		end
	end

-- create containers (anchor, mainvid)
-- transfer icon storage to mainvid and position icon + canvas
	if (icntbl.x == nil) then
		icntbl.x, icntbl.y = next_iconspawn();
	end

	icntbl.anchor = null_surface(awb_cfg.rootcell_w, awb_cfg.rootcell_h);
	link_image(icntbl.anchor, awb_cfg.root.anchor);

	icntbl.vid    = null_surface(icntbl.w, icntbl.h);
	move_image(icntbl.vid, math.floor(0.5 * (awb_cfg.rootcell_w - icntbl.w)));	

	image_sharestorage(iconvid, icntbl.vid);
	resize_image(icntbl.vid, icntbl.w, icntbl.h);

	link_image(icntbl.vid, icntbl.anchor);

	icntbl.set_caption = function(self, newvid)
		local newopa = 0.0;

		if (icntbl.caption) then
			delete_image(icntbl.caption);
			newopa = 1.0;
		end

		icntbl.caption = newvid;
		blend_image(icntbl.caption, newopa);
		link_image(icntbl.caption, icntbl.anchor);
		move_image(icntbl.caption, math.floor( 0.5 * (awb_cfg.rootcell_w - 
			image_surface_properties(icntbl.caption).width)), icntbl.h + 5);
		order_image(icntbl.caption, 5);
		blend_image(icntbl.caption, 1.0, awb_cfg.animspeed);
	end

	icntbl:set_caption(captionvid);
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

	ctable.rclick = function(self, vid)
		ctable.click(self, vid);
		if (icntbl.rtrigger) then
			icntbl:rtrigger();
		end
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

	ctable.hover = function(self, vid, dx, dy, state)
		if (state and icntbl.helper) then
			awbwman_hoverhint(icntbl.helper);
		else
			awbwman_drophover();
		end
	end

	order_image(icntbl.vid, 5);
	blend_image({icntbl.anchor, icntbl.vid}, 
		1.0, awb_cfg.animspeed);
	move_image(icntbl.anchor, icntbl.x, icntbl.y);
	ctable.name = "rootwindow_button(" .. name .. ")";
	mouse_addlistener(ctable, {"drag", "drop", 
		"click", "rclick", "dblclick", "hover"});
	table.insert(awb_cfg.rooticns, icntbl);
	icntbl.mhandler = ctable;
	return icntbl;
end

local wndbase = math.random(1000);
function awbwman_spawn(caption, options)
	if (options == nil) then
		options = {};
	end
	
	options.animspeed = awb_cfg.animspeed;

	if (options.refid ~= nil) then
		local kv = get_key(options.refid);
		if (kv ~= nil) then
			kv = tostring(kv);
			local strtbl = string.split(kv, ":");
			for i, j in ipairs(strtbl) do
				local arg = string.split(j, "=");
				options[arg[1]] = tonumber_rdx(arg[2]);
				if (options[arg[1]] ~= nil) then
				if (arg[1] == "x" or arg[1] == "w") then
					options[arg[1]] = math.floor(VRESW * options[arg[1]]);
				elseif (arg[1] == "y" or arg[1] == "h") then
					options[arg[1]] = math.floor(VRESH * options[arg[1]]);
				end
				end
			end
		end
	end

-- load pos, size from there and update
-- the key in destroy
	local wcont  = awbwnd_create(options);
	if (wcont == nil) then
		return;
	end

	wcont.kind   = "window";

	local mhands = {};
	local tmpfun = wcont.destroy;

	wcont.wndid = wndbase;
	wndbase = wndbase + 1;

-- default drag, click, double click etc.
	wcont.destroy = function(self, time)
		if (time == nil) then
			time = awb_cfg.animspeed;
		end

		mouse_droplistener(self);
		mouse_droplistener(self.rhandle);
		mouse_droplistener(self.top);

		for i,v in ipairs(mhands) do
			mouse_droplistener(v);
		end

		if (options.refid) then
			local key = string.format("w=%s:h=%s:x=%s:y=%s",
			tostring_rdx(wcont.w / VRESW), 
			tostring_rdx(wcont.h / VRESH),
			tostring_rdx(wcont.x / VRESW),
			tostring_rdx(wcont.y / VRESH));

			store_key(options.refid, key);
		end

		awbwman_close(self);
		tmpfun(self, time);
	end

-- single color canvas (but treated as textured) for shader or replacement 
	local r = awb_col.bgcolor.r;
	local g = awb_col.bgcolor.g;
	local b = awb_col.bgcolor.b;

-- separate click handler for the canvas area
-- as more advanced windows types (selection etc.) may need 
-- to override
	local canvas = fill_surface(wcont.w, wcont.h, r, g, b);
	wcont:update_canvas(canvas);

-- top windowbar
	local tbar = wcont:add_bar("t", awb_cfg.activeres,
		awb_cfg.inactiveres, awb_cfg.topbar_sz, 
		awb_cfg.topbar_sz, {mouse_nodefault = true});

		if (options.nocaption == nil) then
			awbwman_addcaption(tbar, caption);
		end

	if (options.noicons == nil) then
		tbar:add_icon("close", "l", awb_cfg.bordericns["close"], function()
			wcont:destroy(awb_cfg.animspeed);	
		end);

		tbar:add_icon("toback", "r", awb_cfg.bordericns["toback"], function()
			awbwman_pushback(wcont);
			awbwman_updateorder();
		end);
	end

	if (options.nominimize == nil) then
		tbar:add_icon("minimize", "r", awb_cfg.bordericns["minimize"], function()
			awbwman_minimize(wcont, true);
		end);
	end

	wcont.resizable = options.noresize == nil;
-- "normal" right bar (no scrolling) is mostly transparent and 
-- lies above the canvas area. The resize button needs a separate 
-- mouse handler
	if (options.noresize == nil) then
		local rbar = wcont:add_bar("r", awb_cfg.alphares,
			awb_cfg.alphares, awb_cfg.topbar_sz - 2, 0, {mouse_nodefault = true});
		image_mask_set(rbar.vid, MASK_UNPICKABLE);
		local icn = rbar:add_icon("resize", "r", awb_cfg.bordericns["resize"]);
		local rhandle = {};

		rhandle.drag = function(self, vid, x, y)
			awbwman_focus(wcont);
			if (awb_cfg.meta.shift) then
				if (math.abs(x) > math.abs(y)) then
					wcont:resize(wcont.w + x, 0, false);
				else
					wcont:resize(0, wcont.h + y, false);
				end
			else
				wcont:resize(wcont.w + x, wcont.h + y, false);
			end
		end

		rhandle.drop = function(self, vid)
			wcont:resize(math.floor(wcont.w), math.floor(wcont.h), true);
		end

		rhandle.own = function(self, vid)
			return vid == icn.vid;
		end

		rhandle.click = function() 
			wcont:focus(); 
		end

		rhandle.rclick = function(self, vid)
			awbwman_focus(wcont);
			if (options.fullscreen) then
				local lbls = {"Fullscreen"};
				local tbl = {function() awbwman_fullscreen(wcont); end};

				if (wcont.kind == "media" or wcont.kind == "target") then
					table.insert(lbls, "Original Size");
					table.insert(tbl, function()
						local did = wcont.controlid ~= nil 
							and wcont.controlid or wcont.canvas.vid;

						local props = wcont:canvas_iprops();
						wcont:resize(props.width, props.height, true);
					end);

					table.insert(lbls, "/2 align");
					table.insert(tbl, function()
						local props = image_surface_properties(wcont.canvas.vid);
						wcont:resize( props.width - math.fmod(props.width, 2), 
							props.height - math.fmod(props.height, 2), true);
					end);
				end

				local vid, lines = desktoplbl(table.concat(lbls, "\\n\\r"));
				awbwman_popup(vid, lines, tbl);
			end
		end

		rhandle.name = "awbwindow_resizebtn";
		mouse_addlistener(rhandle, {"click", "drag", "drop", "rclick"});
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

	if (options.x == nil) then
		options.x, options.y = awbwman_next_spawnpos(wcont);
		wcont:move(options.x, options.y);
	else
		wcont:move(options.x, options.y);
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

function awbwman_mousepop(reficn)
	local lst = {
		"Acceleration",
		"Acceleration (X)",
		"Acceleration (Y)",
		"Double-Click"
	};

	local vid, lines = desktoplbl(table.concat(lst, "\\n\\r"));
	local resfun = {};
	resfun[1] = function()
		awbwman_popupslider(0.1, mouse_acceleration(), 5.0, function(val)
			mouse_acceleration(val);
		end, {ref = reficn});
	end

	resfun[2] = function()
		local x, y = mouse_acceleration();
		awbwman_popupslider(0.1, x, 5.0, function(val)
			mouse_acceleration(val, y);
		end, {ref = reficn});
	end

	resfun[3] = function()
		local x, y = mouse_acceleration();
		awbwman_popupslider(0.1, y, 5.0, function(val)
			mouse_acceleration(x, val);
		end, {ref = reficn});
	end

	resfun[4] = function()
		awbwman_popupslider(4, mouse_dblclickrate(), 20, function(val)
			mouse_dblclickrate(val);
		end, {ref = reficn});
	end

	awbwman_popup(vid, lines, resfun, {ref = reficn});
end

function awbwman_toggle_mousegrab()
	local state = toggle_mouse_grab();
	if (state) then
		image_sharestorage(awb_cfg.bordericns["mouselock"], awb_cfg.mouseicn.vid);	
	else
		image_sharestorage(awb_cfg.bordericns["mouse"], awb_cfg.mouseicn.vid);
	end
end

-- want to re-use when we cycle the transform
local function tablist_allocslot(i, wnd)
	local tbl  = awb_cfg.tablist_toggle;
	local b    = awb_cfg.tabicn_base;
	local dwin = wnd; 
	local cont = null_surface(b, b);

	tbl.slots[i] = {
		vid = cont,
		wnd = dwin
	};

	image_mask_set(cont, MASK_UNPICKABLE);
	link_image(cont, tbl.anchor);
	image_inherit_order(cont, true);
	blend_image(cont, 1.0, awb_cfg.animspeed);
	move_image(cont, (i-1) * (b + 4), b, awb_cfg.animspeed);

	if (type(awb_cfg.tabicns[dwin.kind]) == "number") then
		image_sharestorage(awb_cfg.tabicns[dwin.kind], cont);

	elseif (type(dwin.kind) == "number" and
		valid_vid(dwin.kind)) then
		image_sharestorage(dwin.kind, cont);

	elseif (valid_vid(dwin.canvas.vid)) then
		image_sharestorage(dwin.canvas.vid, cont);
	end
end

local function tablist_updatetag(msg)
	local tbl = awb_cfg.tablist_toggle;
	if (tbl.lbl) then
		expire_image(tbl.lbl, awb_cfg.animspeed);
		blend_image(tbl.lbl, 0.0, awb_cfg.animspeed);
		tbl.lbl = nil;
	end

	if (msg) then
		local props = image_surface_properties(mouse_cursor());
		tbl.lbl = desktoplbl(msg);
		image_mask_set(tbl.lbl, MASK_UNPICKABLE);
		link_image(tbl.lbl, tbl.anchor);
		blend_image(tbl.lbl, 1.0, awb_cfg.animspeed);
		image_inherit_order(tbl.lbl, true);
		move_image(tbl.lbl, props.width, props.height - 
			image_surface_properties(tbl.lbl).height);  
	end
end

function awbwman_tablist_toggle(active, group)
	local tbl = awb_cfg.tablist_toggle;
	local b = awb_cfg.tabicn_base;

	if (active == false) then
		if (tbl ~= nil) then
			expire_image(tbl.anchor, awb_cfg.animspeed);
			blend_image(tbl.anchor, 0.0, awb_cfg.animspeed);

			if (tbl.lbl) then
				expire_image(tbl.lbl, awb_cfg.animspeed);
				blend_image(tbl.lbl, 0.0, awb_cfg.animspeed);
			end

			for k, v in ipairs(awb_cfg.tablist_toggle.slots) do
				move_image(v, 0, 0, awb_cfg.animspeed);
			end

			local wnd = awb_cfg.tablist_toggle.slots[1].wnd;
			if (wnd.minimized) then
				local ind = awbwman_findind(wnd, awb_cfg.hidden);
				local speed = wnd.animspeed;
				wnd.animspeed = 0;
				awbwman_restore(ind);
				wnd.animspeed = speed;
			end

			if (wnd.active) then
				awbwman_focus(wnd, false);
				local dx, dy = mouse_xy();
				wnd:move(math.floor(dx), math.floor(dy), awb_cfg.animspeed);
			end			

			awb_cfg.tablist_toggle = nil;
		end
		return;
	end

--
-- spawn, cycle a user-defined window- reference list if necessary
-- (to add more advanced forms, like ALT-TAB between most recently used etc.)
--
	group = "all";
	if (awb_cfg.tablist_toggle == nil and active) then
		if (group == nil) then
			awb_tablist= awb_wtable;

		elseif (type(group) == "string") then
			awb_tablist = {};

			if (group == "hidden") then
			awb_tablist = awb_cfg.hidden;	

			elseif (group == "all") then
				for i,v in ipairs(awb_cfg.hidden) do
					table.insert(awb_tablist, v);
				end

				for i,v in ipairs(awb_wtable) do
					table.insert(awb_tablist, v);
				end
			end
		else
			awb_tablist = group;
		end

		if (#awb_tablist <= 1) then
			return;
		end

		tbl = {
			slots = {}
		};

		tbl.ulim = #awb_tablist > 5 and 5 or #awb_tablist;
		tbl.ofs  = tbl.ulim + 1;
		awb_cfg.tablist_toggle = tbl;

		local msglen = "";
		for i=1,#awb_tablist do
			if (string.len(awb_tablist[i].name) > string.len(msglen)) then
				msglen = awb_tablist[i].name;
			end
		end

		local vid = desktoplbl(msglen);
		local msgw = (3 * b) + image_surface_properties(vid).width;
		delete_image(vid);

		tbl.anchor = null_surface(1, 1);
		image_mask_set(tbl.anchor, MASK_UNPICKABLE);
		link_image(tbl.anchor, mouse_cursor());
		image_inherit_order(tbl.anchor, true);
		show_image(tbl.anchor);

		tbl.minbw = (b + 6) * (tbl.ulim + 3);
		tbl.minbw = tbl.minbw < msgw and msgw or tbl.minbw; 
		tbl.bg = color_surface(tbl.minbw, 5 * b, 0, 0, 0);
		move_image(tbl.bg, -2 * b - 4, -2 * b - 4);
		link_image(tbl.bg, tbl.anchor);
		image_inherit_order(tbl.bg, true);
		blend_image(tbl.bg, 0.5);

		for i=1,tbl.ulim do
			tablist_allocslot(i, awb_tablist[i]);
		end

		reset_image_transform(tbl.slots[1].vid);
		blend_image(tbl.slots[1].vid, 1.0, awb_cfg.animspeed);
		move_image(tbl.slots[1].vid, -2 * b, -2 * b, awb_cfg.animspeed);
		resize_image(tbl.slots[1].vid, b + b, b + b, awb_cfg.animspeed);

		tablist_updatetag(tbl.slots[1].wnd.name);
		return;

	else
-- already got a session running, just cycle the transform	
		if (#awb_tablist > tbl.ulim) then
			expire_image(tbl.slots[1].vid, awb_cfg.animspeed);
		end

		local tmp = tbl.slots[1];
		for i=1,tbl.ulim-1 do
			tbl.slots[i] = tbl.slots[i+1];
		end
		tbl.slots[tbl.ulim] = tmp;

		for i=1,tbl.ulim do
			move_image(tbl.slots[i].vid, (i-1) * (b + 4), b, awb_cfg.animspeed);
			resize_image(tbl.slots[i].vid, b, b, awb_cfg.animspeed);
		end

-- need to rotate in a new one, since the first now is the last
		if (#awb_tablist > tbl.ulim) then
			local tbl = awb_cfg.tablist_toggle;
			reset_image_transform(tbl.slots[tbl.ulim].vid);
			move_image(tbl.slots[tbl.ulim].vid, 0, 0, awb_cfg.animspeed);
			expire_image(tbl.slots[tbl.ulim].vid, awb_cfg.animspeed);
			blend_image(tbl.slots[tbl.ulim].vid, 0, awb_cfg.animspeed);

-- allocate a new that takes the offset in consideration
			tablist_allocslot(tbl.ulim, awb_tablist[tbl.ofs]);
			tbl.slots[tbl.ulim].wnd = awb_tablist[tbl.ofs];
			tbl.ofs = (tbl.ofs + 1) > #awb_tablist and 1 or (tbl.ofs + 1);
		end
	end

	reset_image_transform(tbl.slots[1].vid);
	move_image(tbl.slots[1].vid, -2 * b, -2 * b, awb_cfg.animspeed);
	resize_image(tbl.slots[1].vid, b + b, b + b, awb_cfg.animspeed);
	tablist_updatetag(tbl.slots[1].wnd.name);
end

--
-- To override regular mouse events, this functions returns true
-- on forward and false when the chain should be dropped
--
function awbwman_minput(iotbl)
	if (awb_cfg.mouse_focus ~= nil and
		awb_cfg.focus and awb_cfg.focus.minput) then
		awb_cfg.focus:minput(iotbl, true);
		return false;
	else
		return true;
	end
end

--
-- While some input (e.g. whatever is passed as input 
-- to mouse_handler) gets treated elsewhere, as is meta state modifier,
-- the purpose of this function is to forward to the current 
-- focuswnd (if needed) or manipulate whatever is in the popup-slot,
-- and secondarily, pass through the active input layout and push
-- to the broadcast domain.
--
local tablist_active = nil;
function awbwman_ainput(iotbl)
	if (awb_cfg.popup_active and awb_cfg.popup_active.ainput ~= nil) then
		awb_cfg.popup_active:ainput(iotbl);
		return;
	end

-- invert axis value in beforehand
	if (awb_cfg.amap[iotbl.devid]) then
		local a = awb_cfg.amap[iotbl.devid][iotbl.subid];
		if (a ~= nil and a ~= false) then
			iotbl.samples[1] = -1 * iotbl.samples[1];
		end
	end

	local focus_done = false;
	for i,v in ipairs(awb_cfg.global_input) do
		if (v.ainput) then
			v:ainput(iotbl);
			if (v == awb_cfg.focus) then
				focus_done = true;
			end
		end
	end

	if (focus_done == false and awb_cfg.focus and 
		awb_cfg.focus.ainput) then
		awb_cfg.focus:ainput(iotbl);
	end
end

function awbwman_flipaxis(dev, sub, qry)
	if (awb_cfg.amap[dev] == nil) then
		awb_cfg.amap[dev] = {};
	end

	if (qry) then
		return awb_cfg.amap[dev][sub];
	end

	if (awb_cfg.amap[dev][sub] == nil) then
		awb_cfg.amap[dev][sub] = true;
	else
		awb_cfg.amap[dev][sub] = not awb_cfg.amap[dev][sub];
	end

	return awb_cfg.amap[dev][sub];
end

function awbwman_input(iotbl, keysym)
	if (keysym == "SHIFTTAB" and awb_cfg.modal == nil) then
		if (iotbl.active) then
			awbwman_tablist_toggle(true);
		end
		return;
	end

	if (keysym == "SHIFTF4") then
		if (awb_cfg.focus and 
			awb_cfg.modal ~= true and iotbl.active) then
			awb_cfg.focus:destroy();
		end
		return;
	end

	if (awb_cfg.popup_active and awb_cfg.popup_active.input ~= nil) then
		awb_cfg.popup_active:input(iotbl);
	
	else
		focus_done = false;
		for i,v in ipairs(awb_cfg.global_input) do
			v:input(iotbl);
			if (v == awb_cfg.focus) then
				focus_done = true;
			end
		end
	
		if (focus_done == false and 
			awb_cfg.focus and awb_cfg.focus.input ~= nil) then
				awb_cfg.focus:input(iotbl);
		end
	end
end

function awbwman_hoverhint(msg)
	local lbl = desktoplbl(msg);
	local props = image_surface_properties(lbl);
	local bg = color_surface(props.width + 4, props.height + 4, 0, 0, 0);
	local anchor = null_surface(1, 1);

	local cattach = mouse_cursor();
	local cprops = image_surface_properties(cattach);

	link_image(anchor, cattach);
	link_image(bg, anchor);
	link_image(lbl, anchor);

	image_mask_set(anchor, MASK_UNPICKABLE);
	image_mask_set(bg, MASK_UNPICKABLE);
	image_mask_set(lbl, MASK_UNPICKABLE);

	blend_image(anchor, 1.0, awb_cfg.animspeed);

	if (cprops.x > VRESW * 0.5) then
		local dx = -1 * props.width;
		if (cprops.x - dx < 0) then 
			dx = dx + math.abs(cprops.x - dx);
		end
		move_image(anchor, dx, 0); 
	else
		move_image(anchor, cprops.width, 0);
	end

	show_image(lbl);
	blend_image(bg, 0.5);

	image_inherit_order(anchor, true);
	image_inherit_order(lbl, true);
	image_inherit_order(bg, true);
	order_image(lbl, 1);
	move_image(lbl, 2, 2);

	awbwman_drophover();
	awb_cfg.hover = anchor;
end

function awbwman_drophover()
	if (awb_cfg.hover) then
		blend_image(awb_cfg.hover, 0.0, awb_cfg.animspeed);
		expire_image(awb_cfg.hover, awb_cfg.animspeed);
	end
	awb_cfg.hover = nil;
end

function awbwman_shutdown()
	for i, v in ipairs(awb_cfg.rooticns) do
		local val = string.format("%s:%s", tostring_rdx(v.x / VRESW), 
			tostring_rdx(v.y / VRESH));
		store_key("rooticn_" .. v.name, val);
	end

	store_key("global_vol", tostring_rdx(awb_cfg.global_vol));

	local dblrate = mouse_dblclickrate();
	store_key("mouse_dblclick", tostring_rdx(dblrate));

	local ax, ay = mouse_acceleration();
	store_key("mouse_accel_x", tostring_rdx(ax));
	store_key("mouse_accel_y", tostring_rdx(ay));

	awbwman_dumpanalog("analog.state");
	shutdown();
end

function awbwman_gethelper(wnd)
	return awb_cfg.helper;
end

function awbwman_sethelper(wnd)
	awb_cfg.helper = wnd;
end

function awbwman_loadanalog(inp)
	if (not resource(inp)) then
		return;
	end

	local t = system_load(inp)();
	if (t == nil) then
		return;
	end

	for k, v in ipairs(t) do
		inputanalog_filter(v.devid, v.subid, v.deadzone,
			v.upper_bound, v.lower_bound, v.kernel_size, v.mode);
	end
end

function awbwman_dumpanalog(outp)
	local ref = inputanalog_query();
	if (ref == nil) then
		return;
	end
	
	zap_resource(outp);
	if (open_rawresource(outp) == nil) then
		warning("Couldn't store analog state");
		return;
	end
		
	write_rawresource([[local t = {};]]);
	for i,j in ipairs(ref) do
		write_rawresource(string.format(
[[table.insert(t, {
devid = %d,
subid = %d,
mode = "%s",
deadzone = %d,
upper_bound = %d,
lower_bound = %d,
kernel_size = %d});
]], j.devid, j.subid, j.mode, j.deadzone,
				j.upper_bound, j.lower_bound, j.kernel_size));
	end

	write_rawresource("return t;");
	close_rawresource();
end

--
-- Load / Store default settings for window behavior etc.
--
function awbwman_init(defrndr, mnurndr)
	awb_cfg.meta       = {};
	awb_cfg.bordericns = {};
	awb_cfg.rooticns   = {};
	awb_cfg.helper     = nil;

	awb_cfg.defrndfun  = defrndr;
	awb_cfg.mnurndfun  = mnurndr;

	local mvol = get_key("global_vol");
	if (mvol ~= nil) then
		awb_cfg.global_vol = tonumber_rdx(mvol);
	else
		awb_cfg.mvol = 1.0;
	end

	local mvalx = get_key("mouse_accel_x");
	local mvaly = get_key("mouse_accel_y");

	if (mvalx ~= nil) then
		if (mvaly ~= nil) then
			mouse_acceleration( tonumber_rdx(mvalx), tonumber_rdx(mvaly) );
		else
			mouse_acceleration( tonumber_rdx(mvalx) );
		end
	end

	local mdbl = get_key("mouse_dblclick");
	if (mdbl ~= nil) then
		mouse_dblclickrate( tonumber_rdx(mdbl) );
	end

	awb_col = system_load("scripts/colourtable.lua")();
	
-- just somewhere for global notification messages to attach
	awb_cfg.notifyanchor = null_surface(1,1);
	show_image(awb_cfg.notifyanchor);

	awb_cfg.col = awb_col;
	awb_cfg.activeres   = load_image("awbicons/border.png");
	awb_cfg.inactiveres = load_image("awbicons/border_inactive.png");
	awb_cfg.ttactiveres = load_image("awbicons/tt_border.png");
	awb_cfg.ttinactvres = load_image("awbicons/tt_border.png");
	awb_cfg.alphares    = load_image("awbicons/alpha.png");
	local load_image = load_image_asynch;
	
	awb_cfg.tabicns = {};
	awb_cfg.tabicns.list = load_image("awbicons/floppy.png");
	awb_cfg.tabicns.icon = awb_cfg.tabicns.list;
	awb_cfg.tabicns.tool = awb_cfg.tabicns.list;

-- These should really have a packed- storage form, but that feature is currently
-- missing and the planned approach doesn't really play well with image_sharestorage 
	awb_cfg.bordericns["minus"]    = load_image("awbicons/minus.png");
	awb_cfg.bordericns["plus"]     = load_image("awbicons/plus.png");
	awb_cfg.bordericns["clone"]    = load_image("awbicons/clone.png");
	awb_cfg.bordericns["r1"]       = load_image("awbicons/r1.png");
	awb_cfg.bordericns["g1"]       = load_image("awbicons/g1.png");
	awb_cfg.bordericns["b1"]       = load_image("awbicons/b1.png");
	awb_cfg.bordericns["close"]    = load_image("awbicons/close.png");
	awb_cfg.bordericns["resize"]   = load_image("awbicons/resize.png");
	awb_cfg.bordericns["toback"]   = load_image("awbicons/toback.png");
	awb_cfg.bordericns["minimize"] = load_image("awbicons/minus.png");
	awb_cfg.bordericns["play"]     = load_image("awbicons/play.png");
	awb_cfg.bordericns["pause"]    = load_image("awbicons/pause.png");
	awb_cfg.bordericns["input"]    = load_image("awbicons/joystick.png");
	awb_cfg.bordericns["ginput"]   = load_image("awbicons/globalinp.png");
	awb_cfg.bordericns["volume"]   = load_image("awbicons/speaker.png");
	awb_cfg.bordericns["save"]     = load_image("awbicons/save.png");
	awb_cfg.bordericns["load"]     = load_image("awbicons/load.png");
	awb_cfg.bordericns["record"]   = load_image("awbicons/record.png");
	awb_cfg.bordericns["aspect"]   = load_image("awbicons/aspect.png");
	awb_cfg.bordericns["vcodec"]   = load_image("awbicons/vcodec.png");
	awb_cfg.bordericns["vquality"] = load_image("awbicons/vquality.png");
	awb_cfg.bordericns["acodec"]   = load_image("awbicons/acodec.png");
	awb_cfg.bordericns["aquality"] = load_image("awbicons/aquality.png");
	awb_cfg.bordericns["fps"]      = load_image("awbicons/fps.png");
	awb_cfg.bordericns["cformat"]  = load_image("awbicons/cformat.png");
	awb_cfg.bordericns["subdivide"]= load_image("awbicons/subdiv.png");
	awb_cfg.bordericns["amplitude"]= load_image("awbicons/ampl.png");
	awb_cfg.bordericns["filter"]   = load_image("awbicons/filter.png");
	awb_cfg.bordericns["settings"] = load_image("awbicons/settings.png");
	awb_cfg.bordericns["ntsc"]     = load_image("awbicons/ntsc.png");
	awb_cfg.bordericns["list"]     = load_image("awbicons/list.png");
	awb_cfg.bordericns["uparrow"]  = load_image("awbicons/uparrow.png");
	awb_cfg.bordericns["downarrow"]= load_image("awbicons/downarrow.png");
	awb_cfg.bordericns["flip"]     = load_image("awbicons/flip.png");
	awb_cfg.bordericns["shuffle"]  = load_image("awbicons/shuffle.png");
	awb_cfg.bordericns["sortaz"]   = load_image("awbicons/az.png");
	awb_cfg.bordericns["sortza"]   = load_image("awbicons/za.png");
	awb_cfg.bordericns["sysopt"]   = load_image("awbicons/sysopt.png");
	awb_cfg.bordericns["resolution"]  = load_image("awbicons/resolution.png");
	awb_cfg.bordericns["fastforward"] = load_image("awbicons/fastforward.png");
	awb_cfg.bordericns["volume_top"]  = load_image("awbicons/topbar_speaker.png");
	awb_cfg.bordericns["mouse"]       = load_image("awbicons/topbar_mouse.png");
	awb_cfg.bordericns["mouselock"]   = load_image("awbicons/topbar_mouselock.png");
	awb_cfg.bordericns["search"]      = load_image("awbicons/topbar_search.png");

	for k,v in pairs(awb_cfg.bordericns) do
		image_pushasynch(v);
	end

	build_shader(nil, awbwnd_invsh, "awb_selected");

	awbwman_loadanalog("analog.state");
	awbwman_rootwnd();
end
