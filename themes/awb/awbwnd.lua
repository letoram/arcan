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

local function awbwnd_alloc(tbl)
-- root will serve as main visibility, clipping etc. region
	tbl.anchor = null_surface(tbl.width, tbl.height);
	image_mask_set(tbl.anchor, MASK_UNPICKABLE);
	show_image(tbl.anchor);	
	return tbl;
end

--
-- Define a new rendertarget reusing the existing
-- hiarchy, then drop it as rendertarget, now we have
-- an iconified version of the contents of the window
-- return as a vid
--
local function awbwnd_iconify()

end

local function awbwnd_resize(self, neww, newh)
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
		move_image(self.dir.r.vid, xofs + hspace, yofs);
		self.dir.r:resize(self.dir.r.size, vspace);
	end
	
	resize_image(self.anchor, neww, newh);
	move_image(self.canvas.vid, xofs, yofs); 
	self.canvas:resize(hspace, vspace);
end

--
-- Just scan all local members and stop at the first
-- one that claims ownership of the vid
--
local function awbwnd_own(self, vid)
	local rv = nil;

	if (self.canvas) then
		rv = self.canvas:own(vid);
	end

	if (self.dir.t) then
		rv = self.dir.t:own(vid);
	end

	if (not rv and self.dir.r) then
		rv = self.dir.r:own(vid);
	end

	if (not rv and self.dir.l) then
		rv = self.dir.l:own(vid);
	end

	if (not rv and self.dir.d) then
		rv = self.dir.d:own(vid);
	end

	return rv;
end

--
-- mostly just empty wrapper / placeholder
-- when (if) we need to cascade this operation to
-- partly- managed members
--
local function awbwnd_move(self, newx, newy, timeval)
	move_image(self.anchor, newx, newy, timeval);
end

local function awbwnd_destroy(self, timeval)
	blend_image(self.anchor,  0.0, timeval);
	expire_image(self.anchor, timeval);

	for k, v in pairs(self.dir) do
		if (v) then 
			delete_image(v.activeimg);
			delete_image(v.inactiveimg);
		end
	end
--
-- the rest should disappear in cascaded deletions
--
end

local function awbbar_destroy(self)
	delete_image(self.active);
	delete_image(self.inactive);

	for i=1,#self.left do
		delete_image(self.left[i].vid);
	end

	for i=1,#self.right do
		delete_image(self.right[i].vid);
	end

	if (self.fill) then
		delete_image(self.fill.vid);
		self.fill = nil;
	end

	self.left  = nil;
	self.right = nil;
end

local function awbbar_resize(self, neww, newh)
	self.w = neww;
	self.h = newh;

	resize_image(self.vid, neww, newh);
	local storep = image_storage_properties(self.vid);

-- vertical or horizontal?
	local stepx = 0;
	local stepy = 0;

	if (neww > newh) then
		image_scale_txcos(self.vid, neww / storep.width, 1);
		stepx = 1;
	else
		image_scale_txcos(self.vid, 1, newh / storep.height);
		stepy = 1;
	end

	local startx = 0;
	local starty = 0;
	
	for i=1,#self.left do
		resize_image(self.left[i].vid, self.size, self.size);
		move_image(self.left[i].vid, stepx * (i-1) * self.size,
			stepy * (i-1) * self.size);
	end

	for i=1,#self.right do
		resize_image(self.right[i].vid, self.size, self.size);
		move_image(self.left[i].vid, stepx * (i-1) * self.size,
			stepy * (i-1) * self.size);
	end

	if (self.fill) then
	end
end

local function awbbar_addicon(self, dir, image, trig)
	local icontbl = {
		trigger = trig
	};
	
	local icon = null_surface(self.size, self.size);
	link_image(icon, self.vid);
	image_inherit_order(icon, true);

	if (dir == "l" or dir == "r") then
		table.insert(dir == "l" and self.left or self.right, icontbl);
		order_image(icon, 2);

	elseif (dir == "fill") then
		if (self.fill ~= nil) then
			return nil;
		end
		
		image_order(icon, 1);
	else
		return nil;
	end

	show_image(icon);
	image_sharestorage(image, icon);
	image_clip_on(icon);
	icontbl.vid = icon;

-- resize will also reorder / resize fill
	self:resize(self.w, self.h);
	return icontbl;
end

local function awbbar_own(self, vid)
	local tbl = {self.left, self.right, {self.fill}};

	if (vid == self.vid) then
		return true;
	end

	for k, v in ipairs(tbl) do
		for ind, val in ipairs(v) do
			if (val.vid == vid) then
				if (val:trigger()) then
					return true;
				end
			end
		end
	end

end

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

local function awbwnd_addbar(self, dir, activeres, inactiveres, bsize, rsize)
	if (dir ~= "t" and dir ~= "b" and dir ~= "l" and dir ~= "r") then
		return nil;
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
		left     = {},
		right    = {},
		fill     = nil,
		size     = bsize,
		rsize    = rsize
	};

	awbbar.parent = self;
	awbbar.activeimg = load_image(activeres);
	image_tracetag(awbbar.activeimg, "awbbar_active_store");

	awbbar.inactiveimg = load_image(inactiveres);
	image_tracetag(awbbar.inactiveimg, "awbbar_inactive_store");

	awbbar.vid      = null_surface(self.width, bsize);
	link_image(awbbar.vid, self.anchor);
	show_image(awbbar.vid);

	image_inherit_order(awbbar.vid, true);
	image_tracetag(awbbar.vid, "awbwnd(" .. self.name .. ")"
		.. "." .. dir .. "bar");

	order_image(awbbar.vid, 1);
	awbbar:active();

	if (self.dir[dir]) then
		self.dir[dir]:destroy();
	end

	self.dir[dir] = awbbar;
	
-- resize will move / cascade etc.
	self:resize(self.width, self.height);
	return awbbar;
end

local function awbwnd_update_canvas(self, vid, volatile)
	link_image(vid, self.anchor);
	image_inherit_order(vid, true);
	order_image(vid, 0);
	show_image(vid);

	local canvastbl = {
		parent = self
	};
	canvastbl.vid = vid;
	canvastbl.resize = function(self, neww, newh)
		resize_image(self.vid, neww, newh);
	end
	canvastbl.own = function(self, vid)
		return vid == self.vid;
	end

	local oldcanvas = self.canvas;
	self.canvas = canvastbl;
	image_tracetag(vid, "awbwnd(" .. self.name ..").canvas");

--
-- size canvas after window, moving / resizing based on
-- which border directions that are in use
--

	if (oldcanvas and oldcanvas.volatile) then
		delete_image(canvastbl.vid);
	else	
		return oldcanvas;
	end
end

local function awbwnd_active(self)
	local tbl = {self.dir.t, self.dir.l, 
		self.dir.b, self.dir.r, self.canvas};
	
	for i, v in ipairs(tbl) do
		if (v and v.active) then
			v:active();
		end
	end

end

local function awbwnd_inactive(self)
	local tbl = {self.dir.t, self.dir.l, 
		self.dir.b, self.dir.r, self.canvas};

	for i, v in ipairs(tbl) do
		if (v and v.inactive) then
			v:inactive();
		end
	end
	
end

function awbwnd_create(options)
	local restbl = {
		show       = awbwnd_show,
    hide       = awbwnd_hide,
    active     = awbwnd_active,
    add_bar    = awbwnd_addbar,
    resize     = awbwnd_resize,
    destroy    = awbwnd_destroy,
		iconify    = awbwnd_iconify,
		move       = awbwnd_move,
		own        = awbwnd_own,
		active     = awbwnd_active,
		inactive   = awbwnd_inactive,
		name       = "awbwnd",
    update_canvas = awbwnd_update_canvas,

-- defaults 
   width       = math.floor(VRESW * 0.3),
   height      = math.floor(VRESH * 0.3),
	 x           = math.floor(0.5 * (VRESW - (VRESW * 0.3)));
	 y           = math.floor(0.5 * (VRESH - (VRESH * 0.3)));
   minw        = 0,
   minh        = 0,

-- internal states
-- each (dir) can have an action bar attached
--
	dir = {
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
			restbl.key = val;
		end
	end

	return awbwnd_alloc(restbl);
end
