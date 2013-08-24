--
-- AWB IconView
--
-- Todolist:
-- Fix last few event handlers for scrollbar 
-- (single scroll, full page flip, ..)
-- Icons for changing default iconsize

-- Sweep the temporary table and distribute in the window region
--
local function awbicon_reposition(self)
	local cx = self.hspace;
	local cy = self.vspace;

	for i, v in ipairs(self.icons) do
		move_image(v.anchor, cx, cy);
		if (cx + self.cell_w > self.w or cy + self.cell_h > self.h) then
			hide_image(v.anchor);
		else
			show_image(v.anchor);
		end

		cx = cx + self.cell_w + self.hspace;

		if (cx + self.cell_w > self.w) then
			cx = self.hspace;
			cy = cy + self.cell_h + self.hspace;
		end
	end
end

--
-- Resizes caret relative to current vertical scrollbar size 
-- (and hide/show scrollbar if one isn't needed)
--
local function awbicon_setscrollbar(self)
	if (self.capacity >= self.total) then
		if (self.scroll) then
			self.scroll = false;
			hide_image(self.dir[self.icon_bardir].fill.vid);
			self.dir[self.icon_bardir].oldsz = self.dir[self.icon_bardir].bsize;
			self.dir[self.icon_bardir].bsize = 0;
		end

		return;

	elseif (self.capacity < self.total and self.scroll == false) then
		self.scroll = true;
		show_image(self.dir[self.icon_bardir].fill.vid);
		self.dir[self.icon_bardir].bsize = self.dir[self.icon_bardir].oldsz;
	end

	local prop = image_surface_properties(self.dir[self.icon_bardir].fill.vid);
	local stepsz = prop.height / self.total;
	
	resize_image(self.scrollcaret, self.dir[self.icon_bardir].size - 2,
		stepsz * self.capacity);
	move_image(self.scrollcaret, 1, stepsz * (self.ofs - 1)); 
end

--
-- Same as in awbwnd_list
--
local function clampofs(self)
	if (self.ofs < 1) then
		self.ofs = 1;
	elseif (self.ofs + self.capacity >= self.total) then
		self.ofs = self.total - self.capacity;
	end
end

local function scrollup(self, n)
	self.ofs = self.ofs - math.abs(n);
	clampofs(self);
	self.lasth = 0;

	for i=1,#self.icons do
		self.icons[i]:delete();
	end

	self.icons = {};
	self:resize(self.w, self.h);
end

local function scrolldown(self, n)
	self.ofs = self.ofs + math.abs(n);
	clampofs(self);
	self.lasth = 0;

	for i=1,#self.icons do
		self.icons[i]:delete();
	end

	self.icons = {};
	self:resize(self.w, self.h);
end

local function caretdrop(self)
	self.caret_dy = 0;
end

local function caretdrag(self, vid, dx, dy)
	self.wnd:focus();
	local prop = image_surface_properties(
		self.wnd.dir[self.wnd.icon_bardir].fill.vid);

	local stepsz = prop.height / self.wnd.total;
	self.caret_dy = self.caret_dy + dy;

	if(self.caret_dy < -5) then
		local steps = math.floor(-1 * self.caret_dy / 5);
		self.caret_dy = self.caret_dy + steps * 5;
		scrollup(self.wnd, steps); 

	elseif (self.caret_dy > 5) then
		local steps = math.floor(self.caret_dy / 5);
		self.caret_dy = self.caret_dy - steps * 5;
		scrolldown(self.wnd, steps);
	end
end

local function scrollclick(self, vid, x, y)
	local props = image_surface_resolve_properties(self.caret);
	self.wnd:focus();

	self.wnd.ofs = (y < props.y) and (self.wnd.ofs - self.wnd.capacity) or
		(self.wnd.ofs + self.wnd.capacity);

	clampofs(self.wnd);

	self.wnd.lasth = 0;
	for i=1,#self.wnd.icons do
		self.wnd.icons[i]:delete();
	end
	self.wnd.icons = {};
	self.wnd:resize(self.wnd.w, self.wnd.h);
end


local function awbicon_add(self, icntbl)
-- anchor + clipping region
	local icn_area = null_surface(self.cell_w, self.cell_h);
	move_image(icn_area, cx, cy);
	link_image(icn_area, self.canvas.vid);
	image_inherit_order(icn_area, true);
	image_tracetag(icn_area, tostring(icntbl.name) .. ".anchor_region");
	show_image(icn_area);

-- container for icon (lifecycle managed elsewhere)
	local icn = null_surface(self.cell_w, self.cell_h);
	image_sharestorage(icntbl.icon, icn);
	image_mask_set(icn, MASK_UNPICKABLE);
	link_image(icn, icn_area);
	image_inherit_order(icn, true);
	order_image(icn, 1);
	blend_image(icn, 0.5);
	image_tracetag(icn, tostring(icntbl.name) .. ".icon");

-- caption is managed here however, assumed caption.height < icnh-2-icnsize
-- (if the icon is descriptive enough, just don't prove a caption)
-- otherwise, apply cropping / clipping to caption before calling _add
	if (icntbl.caption) then
		local props = image_surface_properties(icntbl.caption);
		link_image(icntbl.caption, icn_area);
		show_image(icntbl.caption);
		image_mask_set(icntbl.caption, MASK_UNPICKABLE);
		image_inherit_order(icntbl.caption, true);
		order_image(icntbl.caption, 1);
		image_tracetag(icntbl.caption, tostring(icntbl.name) .. ".caption");
		move_image(icntbl.caption, math.floor(0.5 * (self.cell_w - props.width)),
			self.cell_h - props.height);
	end

-- aspect correct fitting the icon into the clipping region
	resize_image(icn, self.icon_sz, self.icon_sz);
	move_image(icn, math.floor(0.5 * (self.cell_w - self.icon_sz)), 0);	

-- need to track whole icntbl for handler deregistration etc.
	table.insert(self.icons, icntbl);
	icntbl.anchor = icn_area;
	icntbl.own = function(self, vid)
		return vid == icn_area;
	end

	icntbl.dblclick = function(self)
		icntbl:trigger();
	end

	icntbl.over = function()
		blend_image(icn, 1.0, 5);
	end

	icntbl.out = function()
		blend_image(icn, 0.5, 5);
	end

	icntbl.delete = function()
		delete_image(icntbl.anchor);
		icntbl.anchor = nil; -- rest dies in cascade
		mouse_droplistener(icntbl);
	end

	mouse_addlistener(icntbl, {"over", "out", "dblclick"});
end

--
-- Window-resize; just figure out how many additional items
-- to try and request (or how many items to drop)
--
local function awbicon_resize(self, neww, newh)
	self:icon_resize(neww, newh);

	local props = image_surface_properties(self.canvas.vid);
	local cols  = math.floor(props.width  / (self.cell_w + self.hspace));
	local rows  = math.floor(props.height / (self.cell_h + self.vspace));
	self.capacity = cols * rows;
	local total = 0;
	local tbl = nil;

-- grow (request more icons at self.ofs + #icons)
-- shrink (drop n items from the end of icons)
-- else just reposition
	if (self.capacity > #self.icons) then
		tbl, self.total = self:datasel(self.ofs + #self.icons, 
			self.capacity - #self.icons, self.cell_w, self.cell_h);

		for i, v in ipairs(tbl) do
			awbicon_add(self, v);
		end

	elseif (self.capacity < #self.icons) then
		for i=#self.icons,self.capacity+1,-1 do
			local tbl = table.remove(self.icons);
			tbl:delete();
		end
	end

	awbicon_setscrollbar(self);
	self:reposition();
end

--
-- Modify PWIN table (assumed to come from awbwnd_create) and to have
-- a bar in "r" (or set the bardir argument) 
--
-- to behave like a grid based icon view
--
-- datasel_fun is used as callback for getting a table of possible entries
-- datasel_fun(filterstr, start_ofs, item_limit) => array of tables with;
--  .trigger
--  .caption(vid)
--  .icon(vid)
-- 
-- where caption and icon are expected to be wnd controllable icons
-- (will be cleaned up whenever it is needed.
--
-- scrollbar_icn, scrollcaret_icn will be managed locally 
--
function awbwnd_iconview(pwin, cell_w, cell_h, iconsz, datasel_fun, 
	scrollbar_icn, scrollcaret_icn, bardir, options)

	if (bardir == nil) then
		bardir = "r";
	end

	pwin.cell_w  = cell_w;
	pwin.cell_h  = cell_h;
	pwin.icon_sz = iconsz;
	pwin.vspace  = 6;
	pwin.hspace  = 12;
	
	if (options) then
		for k,v in pairs(options) do
			pwin[k] = v;
		end
	end

	pwin.canvas.minw = cell_w;
	pwin.canvas.minh = cell_h;

	pwin.ofs       = 1;
	pwin.datasel   = datasel_fun;
	pwin.icons     = {};

	pwin.icon_bardir = bardir;
	pwin.scrollbar   = awbicon_setscrollbar;
	pwin.reposition  = awbicon_reposition;
	pwin.scrollcaret = scrollcaret_icn;

	image_tracetag(scrollbar_icn,   "awbwnd_iconview.scrollbar");
	image_tracetag(scrollcaret_icn, "awbwnd_iconview.scrollcaret_icn");

--
-- build scrollbar 
--
	local bartbl = pwin.dir[bardir];
	local newicn = bartbl:add_icon("fill", scrollbar_icn);
	delete_image(scrollbar_icn);
	pwin.scroll = true;

	link_image(scrollcaret_icn, newicn.vid);
	image_inherit_order(scrollcaret_icn, true);
	order_image(scrollcaret_icn, 1);
	show_image(scrollcaret_icn);
	resize_image(scrollcaret_icn, 
		pwin.dir["t"].size - 2, pwin.dir["t"].size - 2); 

	pwin.icon_resize = pwin.resize;
	pwin.resize = awbicon_resize;

	pwin:resize(pwin.w, pwin.h);

	local caretmh = {
		wnd = pwin,
		caret_dy = 0,
		drag = caretdrag,
		drop = caretdrop,
		name = "list_scroll_caret",
		own = function(self, vid) return scrollcaret_icn == vid; end
	};

	local scrollmh = {
		wnd = pwin,
		caret = scrollcaret_icn,
		name = "icon_scrollbar",
		own = function(self, vid) return newicn.vid == vid; end,
		click = scrollclick
	};

	mouse_addlistener(caretmh, {"drag", "drop"});
	mouse_addlistener(scrollmh, {"click"});

	pwin.on_destroy = function()
		mouse_droplistener(scrollmh);
		mouse_droplistener(caretmh);

		for i, v in ipairs(pwin.icons) do
			mouse_droplistener(v);
		end
	end

	return pwin;
end
