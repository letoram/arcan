--
-- Simple Window Helper Class
-- Supports a generic "canvas", clipping and optional bars at the
-- top, left, right and bottom sides respectively.
--
-- Used to build more advanced ones (grid layout, listview layout etc.)
-- Usage:
-- table = awb_alloc(options)
-- 	useful options: width, height, minw, minh
--
-- Todo:
-- more "fill" positioning options when lim > maxsz, (center, left, right)
--

local function awbwnd_alloc(tbl)
-- root will serve as main visibility, clipping etc. region
	tbl.anchor = null_surface(tbl.w, tbl.h);
	image_tracetag(tbl.anchor, tbl.name .. ".anchor");
	image_mask_set(tbl.anchor, MASK_UNPICKABLE);
	show_image(tbl.anchor);	
	move_image(tbl.anchor, tbl.x, tbl.y);
	tbl.temp = {};
	tbl.handlers = {};
	return tbl;
end

function awbwnd_set_border(s, sz, r, g, b)
-- border exists "outside" normal tbl dimensions
	if (s.borders) then
		for i, v in pairs(s.borders) do
			image_color(v, r, g, b);
		end
		s.borders = nil;
		s.resize = s.default_resize;
	end

	if (sz > 0) then
		local dirs = {"t", "l", "r", "b"};
		s.borders = {};
		for i, v in ipairs(dirs) do
			s.borders[v] = color_surface(1, 1, r, g, b);
			link_image(s.borders[v], s.anchor);
			image_inherit_order(s.borders[v], true);
			order_image(s.borders[v], 2);
			show_image(s.borders[v]);
			image_tracetag(s.borders[v], "awbwnd_border(" .. v .. ")");
		end
		
		s.default_resize = s.resize;
		s.resize = function(self, neww, newh, completed, dt)
			if (dt == nil) then
				dt = 0;
			end

			s:default_resize(neww, newh, completed, dt);

			move_image(s.borders.t, 0 - sz, 0 - sz, dt);
			move_image(s.borders.b, 0 - sz, s.h, dt);
			move_image(s.borders.l, 0 - sz, 0, dt);
			move_image(s.borders.r, s.w, 0, dt); 

			resize_image(s.borders.t, s.w + sz * 2,  sz, dt); 
			resize_image(s.borders.r, sz, s.h, dt);
			resize_image(s.borders.l, sz, s.h, dt);
			resize_image(s.borders.b, s.w + sz * 2,  sz, dt);
		end
	end
end

local function awbwnd_update_minsz(self)
	self.minw = 0;
	self.minh = 0;

	for k, v in pairs(self.dir) do
		if (v) then
			local tw, th = v:min_sz();
			self.minw = self.minw + tw;
			self.minh = self.minh + th;
		end
	end

	if (self.canvas) then
		self.minw = self.minw + self.canvas.minw;
		self.minh = self.minh + self.canvas.minh;
	end
end

local function awbwnd_resize(self, neww, newh, finished, canvassz)
	if (self.anchor == nil) then
		return;
	end

--
-- Should we forcibly maintain canvas aspect
--
	if (neww == 0 or newh == 0) then
		local props = image_surface_initial_properties(self.canvas.vid);
		if (neww == 0) then
			neww = newh * (props.width / props.height);
		else
			newh = neww * (props.height / props.width);
		end
	end

	awbwnd_update_minsz(self);

	neww = neww >= self.minw and neww or self.minw;
	newh = newh >= self.minh and newh or self.minh;

	local vspace = newh;
	local hspace = neww; 
	local yofs   = 0;
	local xofs   = 0;

	if (self.dir.t) then
		vspace = vspace - self.dir.t.rsize;
		yofs   = self.dir.t.rsize;
		self.dir.t:resize(neww, self.dir.t.size);
	end

	if (self.dir.tt) then
		vspace = vspace - self.dir.tt.rsize;
		yofs   = self.dir.t.rsize + self.dir.tt.rsize;
		self.dir.tt:resize(neww, self.dir.tt.size);
		if (self.dir.t) then
			move_image(self.dir.tt.vid, 0, self.dir.t.rsize);
		else
			move_image(self.dir.tt.vid, 0);
		end
	end

	if (self.dir.b) then
		vspace = vspace - self.dir.b.rsize;
		move_image(self.dir.b.vid, 0, yofs + vspace);
		self.dir.b:resize(neww, self.dir.b.size); 
	end

	if (self.dir.l) then
		hspace = hspace - self.dir.l.rsize;
		xofs = xofs + self.dir.l.rsize;
		move_image(self.dir.l.vid, 0, yofs);
		self.dir.l:resize(self.dir.l.size, vspace);
	end

	if (self.dir.r) then
		hspace = hspace - self.dir.r.rsize;
	
		if (self.dir.r.rsize ~= self.dir.r.size) then
			move_image(self.dir.r.vid, xofs + hspace + 
				self.dir.r.rsize - self.dir.r.size, yofs);
		else
			move_image(self.dir.r.vid, xofs + hspace, yofs);
		end
		self.dir.r:resize(self.dir.r.size, vspace);
	end

	if (canvassz and (xofs > 0 or yofs > 0)) then
		awbwnd_resize(self, neww + xofs, newh + xofs, finished, false);
		return;
	end

	resize_image(self.anchor, neww, newh);
	move_image(self.canvas.vid, xofs, yofs); 

-- cache these values as they're somewhat expensive to 
-- calculate and used reasonably often
	self.w = neww;
	self.h = newh;

	self.canvasx = xofs;
	self.canvasy = yofs;
	self.canvasw = hspace;
	self.canvash = vspace;

	self.canvas:resize(hspace, vspace);
	if (self.on_resize) then
		self:on_resize(neww, newh, hspace, vspace);
	end

	if (finished and self.on_resized) then
		self:on_resized(neww, newh, hspace, vspace);
	end
end

--
-- Just scan all local members and stop at the first
-- one that claims ownership of the vid
--
local function awbwnd_own(self, vid)
	local rv = nil;
	local t = {self.canvas, self.dir.tt, self.dir.t, 
		self.dir.r, self.dir.l, self.dir.b};

	for ind, val in ipairs(t) do
		if (val and val:own(vid)) then
			self:focus();
			return true;
		end
	end
end

--
-- mostly just empty wrapper / placeholder
-- when (if) we need to cascade this operation to
-- partly- managed members
--
local function awbwnd_move(self, newx, newy, timeval)
	if (self.anchor == nil) then
		return;
	end
	
	move_image(self.anchor, newx, newy, timeval);
	self.x = newx;
	self.y = newy;
end

local function awbwnd_destroy(self, timeval)
-- let subtype specific hooks be invoked before we reset members
	if (type(self.on_destroy) == "function") then
		if (self:on_destroy() == true and self.confirm_destroy) then
			return;
		end

	elseif (type(self.on_destroy) == "table") then
		for i=1,#self.on_destroy do
			if (self.on_destroy[i](self) == true and self.confirm_destroy) then
				return;
			end
		end
	end

--
-- delete the icons immediately as we don't want them pressed
-- and they "fade" somewhat oddly when there's a background bar
--
	for k, v in pairs(self.dir) do
		if (v) then
			v:destroy();
		end
	end

--
-- workaround for (cascade-window in minimize getting deleted)
--
	awbwman_minimize_drop(self);	

--
-- just quickly spot invocations that miss :
--
	if (type(timeval) == "table") then
		print(debug.traceback());
	end

	if (valid_vid(self.canvas.vid)) then
		force_image_blend(self.canvas.vid, BLEND_NORMAL);
	end
	blend_image(self.anchor,  0.0, timeval);
	expire_image(self.anchor, timeval);

	for i,v in ipairs(self.temp) do
		delete_image(v);
	end

-- De-register mouse-handlers that subtasks may have set
	for i,v in ipairs(self.handlers) do
		mouse_droplistener(v);
	end
	self.handlers = nil;

	local cascade = self.cascade;

-- Clear all members to be sure we don't keep references around
	for i,v in pairs(self) do
		self[i] = nil;
	end

	self.alive = false;

	if (cascade) then
		for i,j in ipairs(cascade) do
			if (j.destroy) then
				j:destroy(timeval);
			end
		end
	end
end

local function awbbar_destroy(self)
	if (valid_vid(self.vid)) then
		delete_image(self.vid);
	end

	self.left  = nil;
	self.right = nil;

	self.parent.dir[ self.dir ] = nil;
end

local function awbbar_minsz(bar)
	local w = 0;
	local h = 0;

	if (bar.vertical) then
		w = bar.rsize;
		h = (#bar.left + #bar.right) * bar.size + 
			(bar.fill and bar.fill.minsz or 0);
	else
		h = bar.rsize;
		w = (#bar.left + #bar.right) * bar.size + 
			(bar.fill and bar.fill.minsz or 0);
	end

	return w, h;
end

--
-- Default version enforces square buttons
--
function awbbaricn_resize(vid, limit, vertical)
	resize_image(vid, limit, limit);
	return limit, limit;
end

function awbbaricn_rectresize(vid, limit, vertical)
	local props = image_surface_initial_properties(vid);
	resize_image(vid, props.width, props.height);
	return props.width, props.height;
end

local function awbbar_resize(self, neww, newh)
	self.w = neww;
	self.h = newh;
	if (self.left == nil) then
		return;
	end

	resize_image(self.vid, neww, newh);
	local storep = image_storage_properties(self.vid);
	local stepx;
	local stepy;
	local lim; 

-- tile pattern
	if (self.vertical) then
		stepx = 0;
		stepy = 1;
		lim = newh;
		image_scale_txcos(self.vid, 1, newh / storep.height);
	else
		image_scale_txcos(self.vid, neww / storep.width, 1);
		stepy = 0;
		stepx = 1;
		lim = neww;
	end

-- reposition icons and figure out fillspace
	local lofs = 0;
	for i=1,#self.left do
		local w, h = self.rzfun(self.left[i].vid, self.size, self.vertical);
		move_image(self.left[i].vid, math.floor(self.left[i].xofs + stepx * lofs), 
			math.floor(self.left[i].yofs + stepy * lofs)); 
		lofs = lofs + w + self.left[i].xofs + self.spacing;
		lim = lim - w;
	end

	local rofs = 0;
	for i=1,#self.right do
		local w, h = self.rzfun(self.right[i].vid, self.size, self.vertical);
		rofs = rofs + w;

		move_image(self.right[i].vid, math.floor(stepx * (self.w - rofs)), 
			math.floor(stepy * (self.h - rofs)));

		lim = lim - w;
	end

	if (self.fill) then
		if (self.fill.maxsz > 0 and lim > self.fill.maxsz) then
			lim = self.fill.maxsz;
		end

		if (self.vertical) then
			move_image(self.fill.vid, 0, lofs);
			if (self.noresize_fill == nil) then
				resize_image(self.fill.vid, self.size, lim);
			end
		else
			move_image(self.fill.vid, lofs, 0);
			if (self.noresize_fill == nil) then
				resize_image(self.fill.vid, lim, self.size);
			end
		end
	end
end

local function awbicn_destroy(self)
	local tbl = {self.parent.left, self.parent.right, {self.parent.fill}};
	delete_image(self.vid);

-- mouse handler is assigned to the bar so no problem there
	for i,v in ipairs(tbl) do
		for ii,vv in ipairs(v) do
			if (vv == self) then
				table.remove(v, ii);
				return;
			end
		end
	end
end

local function awbbar_addicon(self, name, dir, image, trig)
	local icontbl = {
		trigger = trig,
		parent  = self,
		destroy = awbicn_destroy,
		xofs = 0,
		yofs = 0,
		name = name
	};

--
-- If the icon provided is broken, replace it with a red one
-- (not worth the abort()), then link it to the null surface to
-- prevent a leak.
--
	local savelink = false;
	if (not valid_vid(image)) then
		image = fill_surface(8, 8, 255, 0, 0);
		image_tracetag(image, "awbbar_icon_leak(" .. name .. ")");
		savelink = true;
	end

	local props = image_surface_initial_properties(image);
	local icon = null_surface(props.width, props.height);
	link_image(icon, self.vid);
	image_inherit_order(icon, true);
	image_tracetag(icon, self.parent.name .. ".bar(" .. dir .. ").icon");

	if (savelink) then
		link_image(image, icon);
	end

	if (dir == "l" or dir == "r") then
		table.insert(dir == "l" and self.left or self.right, icontbl);
		order_image(icon, 2);

	elseif (dir == "fill") then
		if (self.fill ~= nil) then
			delete_image(self.fill.vid);
		end

		icontbl.maxsz = 0;
		icontbl.minsz = 0;
		self.fill = icontbl; 
		order_image(icon, 1);
	else
		return nil;
	end

	show_image(icon);
	image_sharestorage(image, icon);
	icontbl.vid = icon;

-- resize will also reorder / resize fill
	self:resize(self.w, self.h);
	return icontbl;
end

--
-- This little odd design is mostly legacy before the mouse 
-- API was steady, could(should?) be replaced with individual
-- handlers for each button.
--
local function awbbar_own(self, vid, state)
	local tbl = {self.left, self.right, {self.fill}};

	if (vid == self.vid) then
		return true;
	end

	for k, v in ipairs(tbl) do
		for ind, val in ipairs(v) do
			if (val.vid == vid) then
				local mx, my = mouse_xy();
				if (state ~= "click" and state ~= "rclick") then
					return true;
				end

				if (val.trigger and val:trigger(mx - self.parent.x, 
					my - self.parent.y)) then
					return true;
				end
			end
		end
	end

end

--
-- If this window is used as a source in cursortag,
-- this function allows recipients to register for
-- updates if the media has changed in some way
--

local function awbbar_inactive(self)
	if (self.w == nil) then 
		return;
	end

	image_sharestorage(self.inactiveimg, self.vid);
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT, self.vid);
	self:resize(self.w, self.h);
end

local function awbbar_active(self)
	if (self.w == nil) then
		return;
	end
	
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT, self.vid);
	image_sharestorage(self.activeimg, self.vid);
	self:resize(self.w, self.h);
end

local function awbbar_click(self)
	self.parent:focus();
end

local function awbbar_hover(self, vid, x, y, state)
	if (state == false) then
		awbwman_drophover();

	elseif (self.hoverlut[vid]) then
		awbwman_hoverhint(self.hoverlut[vid]);
	end
end

local function awbwnd_addbar(self, dir, activeimg, 
	inactiveimg, bsize, rsize, options)

	if (dir ~= "t" and dir ~= "b" and dir ~= "l" and 
		dir ~= "r" and dir ~= "tt") then
		return nil;
	end

	if (options == nil) then
		options = {};
	end

	if (rsize == nil) then
		rsize = bsize;
	end

	local awbbar = {
		destroy  = awbbar_destroy,
		resize   = awbbar_resize,
		add_icon = awbbar_addicon,
		own      = awbbar_own,
		active   = awbbar_active,
		inactive = awbbar_inactive,
		min_sz   = awbbar_minsz,
		rzfun    = awbbaricn_resize,
		left     = {},
		right    = {},
		hoverlut = {},
		fill     = nil,
		parent   = self,
		size     = bsize,
		rsize    = rsize,
		spacing  = 0,
		dir      = dir
	};

	if (not options.mouse_nodefault) then
		awbbar.click = awbbar_click;
		awbbar.hover = awbbar_hover;
		awbbar.name = self.name .. "_ttbar_mh";
		mouse_addlistener(awbbar, {"click", "hover"});
		table.insert(self.handlers, awbbar);
	end

	if (options.spacing ~= nil) then
		awbbar.spacing = spacing;
	end

	awbbar.vertical = dir == "l" or dir == "r";
	awbbar.activeimg = activeimg;
	awbbar.inactiveimg = inactiveimg;
	awbbar.vid = null_surface(self.w, bsize);

	link_image(awbbar.vid, self.anchor);
	show_image(awbbar.vid);

	image_inherit_order(awbbar.vid, true);
	image_tracetag(awbbar.vid, "awbwnd(" .. self.name .. ")"
		.. "." .. dir .. "bar");

	order_image(awbbar.vid, 1);

	if (self.dir[dir]) then
		self.dir[dir]:destroy();
	end

	self.dir[dir] = awbbar;
	
-- resize will move / cascade etc.
	self:resize(self.w, self.h);
	awbbar:active();
	return awbbar;
end

local function awbwnd_update_canvas(self, vid, mirrored)
	if (mirrored == nil) then
		mirrored = 0; 
	end

	if (vid == nil or vid == BADID) then	
		return;
	end

	link_image(vid, self.anchor);
	image_inherit_order(vid, true);
	order_image(vid, 0);
	show_image(vid);

	image_set_txcos_default(vid, mirrored); 

	move_image(vid, self.canvasx, self.canvasy);
	resize_image(vid, self.canvasw, self.canvash);

	local canvastbl = {
		parent = self,
		minw = 1,
		minh = 1,
		vid = vid
	};

	canvastbl.resize = function(self, neww, newh)
		resize_image(self.vid, neww, newh);
	end

	canvastbl.own = function(self, vid)
		return vid == self.vid;
	end


	local oldcanvas = self.canvas;
	self.canvas = canvastbl;
	image_tracetag(vid, "awbwnd(" .. self.name ..").canvas");

	if (oldcanvas and valid_vid(oldcanvas.vid) and 
		oldcanvas.vid ~= vid) then
		delete_image(oldcanvas.vid);
	end
end

local function awbwnd_active(self)
	local tbl = {self.dir.t, self.dir.tt, self.dir.l, 
		self.dir.b, self.dir.r, self.canvas};
	
	for i, v in ipairs(tbl) do
		if (v and v.active) then
			v:active();
		end
	end

end

local function awbwnd_inactive(self)
	local tbl = {self.dir.t, self.dir.tt, self.dir.l, 
		self.dir.b, self.dir.r, self.canvas};

	for i, v in ipairs(tbl) do
		if (v and v.inactive) then
			v:inactive();
		end
	end
	
end

local function awbwnd_show(self)
	if (self.hidetbl == nil) then
		return;
	end

	self:resize(self.hidetbl.w, self.hidetbl.h);
	show_image(self.anchor, self.animspeed);
	move_image(self.anchor, self.hidetbl.x, self.hidetbl.y, self.animspeed);

	self.hidetbl = nil;
end

local function awbwnd_hide(self, dstx, dsty)
	self.hidetbl = {
		x = self.x,
		y = self.y, 
		w = self.w,
		h = self.h
	};

	self:resize(64, 64);
	move_image(self.anchor, dstx, dst, self.animspeed);
	blend_image(self.anchor, 1.0, self.animspeed);
	blend_image(self.anchor, 0.0, self.animspeed);
end

function awbwnd_subwin_inputfunc(self, iotbl)
	if (iotbl.active == false and iotbl.utf8 == "") then
		return;
	end
	
	if (iotbl.lutsym == "HOME") then
		self.caretpos = 1;
		self.chofs    = 1;
		self:redraw();

	elseif (iotbl.lutsym == "END") then
		self.caretpos = string.len( self.msg ) + 1;
		self.chofs = self.caretpos - self.ulim;
		self.chofs = self.chofs < 1 and 1 or self.chofs;
		self.chofs = string.utf8lalign(self.msg, self.chofs);
	
		self:redraw();

	elseif (iotbl.lutsym == "LEFT") then
		self.caretpos = string.utf8back(self.msg, self.caretpos);

		if (self.caretpos < self.chofs) then
			self.chofs = self.chofs - self.ulim;
			self.chofs = self.chofs < 1 and 1 or self.chofs;
			self.chofs = string.utf8lalign(self.msg, self.chofs);
		end
		self:redraw();

	elseif (iotbl.lutsym == "RIGHT") then
		self.caretpos = string.utf8forward(self.msg, self.caretpos);
		if (self.chofs + self.ulim <= self.caretpos) then
			self.chofs = self.chofs + 1;
			self:redraw();
		else
			self:update_caret();
		end

	elseif (iotbl.lutsym == "DELETE") then
		self.msg = string.delete_at(self.msg, self.caretpos);
		self:redraw();

	elseif (iotbl.lutsym == "BACKSPACE") then
		if (self.caretpos > 1) then
			self.caretpos = string.utf8back(self.msg, self.caretpos);
			if (self.caretpos <= self.chofs) then
				self.chofs = self.caretpos - self.ulim;
				self.chofs = self.chofs < 0 and 1 or self.chofs;
			end

			self.msg = string.delete_at(self.msg, self.caretpos);
			self:redraw();
		end

	elseif (iotbl.lutsym == "ESCAPE") then
		if (self.cancel) then
			self.cancel();
		end

	elseif (iotbl.lutsym == "RETURN") then
		if (self.accept) then
			self.accept();
		end

	else
		local keych = iotbl.utf8;
		if (keych == nil) then
			return;
		end

		self.msg, nch = string.insert(self.msg,
			keych, self.caretpos, self.nchars);
		self.caretpos = self.caretpos + nch;

		self:redraw();
	end
end

--
-- Create an input component that allows for text edits
-- and returns as a table with a rew vid (link to whatever
-- container should be used)
--
function awbwnd_subwin_input(trigger, lblfun, options)
	local res = {
		msg      = "",
		caretpos = 1,
		limit    = -1,
		noborder = true,
		dynamic  = false,
		w        = 64,
		h        = 32,
		ulim     = 10,
		chofs    = 1
	};

	for k,v in pairs(options) do
		res[k] = v;
	end

	res.anchor = null_surface(1, 1);
	image_mask_set(res.anchor, MASK_SCALE);
	show_image(res.anchor);

	if (res.owner) then
		link_image(res.anchor, options.owner);
		image_inherit_order(res.anchor, true);
		order_image(res.anchor, 1);
	end

	if (not res.noborder) then
		res.border = color_surface(res.w, res.h, options.borderr, 
			options.borderg, options.borderb);
		image_inherit_order(res.border, true);
		order_image(res.border, 2);
		image_mask_set(res.border, MASK_SCALE);
		link_image(res.border, res.anchor);
		show_image(res.border);
	else
		res.borderw = 0;
	end

	res.canvas = color_surface(res.w - res.borderw * 2, 
		res.h - res.borderw * 2, options.bgr, options.bgg, options.bgb);
	link_image(res.canvas, res.anchor);
	image_inherit_order(res.canvas, true);
	order_image(res.canvas, 3);

	move_image(res.canvas, res.borderw, res.borderw);

-- size caret, figure out upper clipping limits etc. using 
-- a reference character image
	local ctv = lblfun("A");
	local ch  = image_surface_properties(ctv);
	res.ulim  = math.ceil(res.w / ch.width);
	delete_image(ctv);

	res.caret = color_surface(2, ch.height, 
		options.caretr, options.caretg, options.caretb); 

	link_image(res.caret, res.canvas);
	image_inherit_order(res.caret, true);
	image_clip_on(res.caret, CLIP_SHALLOW);
	order_image(res.caret, 4);
	move_image(res.caret, res.borderw, res.borderw);

	image_transform_cycle(res.caret, 1);
	blend_image(res.caret, 0.5, 15);
	blend_image(res.caret, 1.0, 15);

-- move caret also (but keep blinking ..)
	show_image(res.canvas);

	res.clip_msg = function(self, cv)
		local uc  = string.utf8ralign(self.msg, 
			cv and cv or (self.chofs + self.ulim));

		return string.gsub(string.sub(self.msg, self.chofs, uc), "\\", "\\\\");
	end

	res.update_caret = function(self)
		if (not valid_vid(self.textvid)) then
			return;
		end

		local xpos = 0;
		local height = image_surface_properties(self.caret).height;

		local msgstr = self:clip_msg(self.caretpos - 1);
		local dimv = lblfun(msgstr);
		local prop = image_surface_properties(dimv);
		local cnvprop = image_surface_properties(self.canvas);

		delete_image(dimv);
		xpos = prop.width;
		if (xpos + 2 > cnvprop.width) then
			local dx = cnvprop.width - xpos;
			move_image(self.textvid, dx, self.borderw);
			move_image(self.caret, cnvprop.width - 2, self.borderw);
		else
			move_image(self.textvid, self.borderw, self.borderw);
			move_image(self.caret, xpos + 2, self.borderw);
		end
	end

--
-- Anchor, border, canvas, test, cursor 
--
	res.validator = function(self)
		return true;
	end

	res.cascade = {};

	res.resize = function(self, neww, newh)
		local height = newh; 

		if (res.textvid and height == nil) then
			local props = image_surface_properties(res.textvid);
			height = props.height + self.borderw * 2 + 4;
		else
			height = newh and newh or 16;
		end

		resize_image(res.anchor, neww, newh);
		if (valid_vid(res.border)) then
			resize_image(res.border, neww, newh);
		end
	
		resize_image(res.canvas, neww - res.borderw * 2, newh - res.borderw * 2);
		res:update_caret();
	end

	res.redraw = function(self)
		if (self.textvid) then
			delete_image(self.textvid);
		end

		if (self.caretpos - self.chofs + 1 > self.ulim) then
			self.chofs = string.utf8lalign(self.msg, self.caretpos - self.ulim);
		end

		res.textvid = lblfun( self:clip_msg() );

		if (res.textvid ~= BADID) then
			show_image(res.textvid);
			link_image(res.textvid, res.canvas);
			image_clip_on(res.textvid, CLIP_SHALLOW);
			image_inherit_order(res.textvid, true);
			order_image(res.textvid, 3);
			move_image(res.textvid, res.borderw, res.borderw);
			local props = image_surface_properties(res.textvid);

			if (res.w == nil) then
				res:resize(props.width + res.borderw * 2);
			else
				self:update_caret();
			end
		end
	end

-- returns true on finished signal, requiring both a valid string
-- and enter etc. being pressed
	res.input = awbwnd_subwin_inputfunc;

	res.destroy = function(self, time)
		if (res.textvid) then
			delete_image(res.textvid);
		end
		
		delete_image(res.border);
		for k, v in pairs(res) do
			res[v] = nil;
		end
	end

	res:resize(res.w, res.h);

	return res;
end

local function awbwnd_addcascade(self, wnd)
	if (self.cascade == nil) then
		self.cascade = {};
	end

	self:drop_cascade(wnd);
	table.insert(self.cascade, wnd);
end

local function awbwnd_dropcascade(self, wnd)
	if (self.cascade == nil) then
		return;
	end

	for i=#self.cascade,1,-1 do
		if (self.cascade[i] == wnd) then
			table.remove(self.cascade, i);
			return;
		end
	end
end

local function awbwnd_drophandler(self, slot, fptr)
	for i, v in ipairs(self[slot]) do
		if (v == fptr) then
			table.remove(self[slot], i);
			return;
		end
	end
end

local function awbwnd_addhandler(self, slot, fptr)
	if (self[slot] ~= nil) then
		if (type(self[slot]) == "table") then			
			self:drop_handler(slot, fptr);
			table.insert(self[slot], fptr);

		elseif (type(self[slot]) == "function") then
			self[slot] = {self[slot], fptr};
		end
	
	else
		self[slot] = fptr;
	end
end

local function awbwnd_canvas_iprops(self)
	return image_surface_initial_properties(self.canvas.vid);
end

function awbwnd_create(options)
	local restbl = {
		show       = awbwnd_show,
    hide       = awbwnd_hide,
    active     = awbwnd_active,
    add_bar    = awbwnd_addbar,
    resize     = awbwnd_resize,
    destroy    = awbwnd_destroy,
		move       = awbwnd_move,
		own        = awbwnd_own,
		hide       = awbwnd_hide,
		active     = awbwnd_active,
		inactive   = awbwnd_inactive,
		set_border = awbwnd_set_border,
		add_cascade= awbwnd_addcascade,
		drop_cascade=awbwnd_dropcascade,
		add_handler= awbwnd_addhandler,
		drop_handler= awbwnd_drophandler,
		canvas_iprops = awbwnd_canvas_iprops,
		req_focus  = function() end, -- set by window manager
		on_destroy = nil,
		on_update  = {},
		name       = "awbwnd",
    update_canvas = awbwnd_update_canvas,

-- defaults 
   w           = math.floor(VRESW * 0.3),
   h           = math.floor(VRESH * 0.3),
	 x           = math.floor(0.5 * (VRESW - (VRESW * 0.3)));
	 y           = math.floor(0.5 * (VRESH - (VRESH * 0.3)));
	 canvasw     = 1,
	 canvash     = 1,
	 canvasx     = 0,
	 canvasy     = 0,
   minw        = 0,
   minh        = 0,
	 animspeed   = 0,
	 alive       = true,

-- internal states
-- each (dir) can have an action bar attached
--
	dir = {
		 tt = nil,
			t = nil,
			r = nil,
			l = nil,
			d = nil
		};
	};

--
-- project option ontop of the default settings
-- but don't allow unrecognized options to pollute the
-- namespace 
--
	for key, val in pairs(options) do
		if (restbl[key]) then
			restbl[key] = val;
		end
	end

	return awbwnd_alloc(restbl);
end
