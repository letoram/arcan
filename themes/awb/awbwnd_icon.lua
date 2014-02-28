--
-- AWB IconView
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
			cy = cy + self.cell_h + self.vspace + self.caph;
		end
	end
end

local function awbicon_add(self, icntbl)
-- anchor + clipping region
	local icn_area = null_surface(self.cell_w, self.cell_h);
	show_image(icn_area);

	move_image(icn_area, cx, cy);
	link_image(icn_area, self.canvas.vid);
	image_clip_on(icn_area);

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
		image_clip_on(icntbl.caption);
		image_tracetag(icntbl.caption, tostring(icntbl.name) .. ".caption");
		move_image(icntbl.caption, math.ceil(0.5 * (self.cell_w - props.width)),
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

	icntbl.click = function()
		self:focus();
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

	mouse_addlistener(icntbl, {"over", "click", "out", "dblclick"});
end

local function def_datasel(filter, ofs, lim)
	local tbl = filter.tbl;
	local res = {};
	local ul = ofs + lim;
	ul = ul > #tbl and #tbl or ul;

	for i=ofs, ul do
		table.insert(res, tbl[i]);
	end

	return res, #tbl;
end

--
-- Window-resize; just figure out how many additional items
-- to try and request (or how many items to drop)
--
local function awbicon_resize(self, neww, newh)
	self:orig_resize(neww, newh);

	if (self.capacity ~= nil and 
		self.total ~= nil and (self.ofs + self.capacity > self.total)) then
		self.ofs = self.total - self.capacity;
	end

	if (self.ofs < 1) then 
		self.ofs = 1;
	end				

-- invalidate / force repopulation
	if (self.lastofs == nil or self.ofs ~= self.lastofs) then
		for i=1,#self.icons do
			self.icons[i]:delete();
		end

		self.icons = {};
		self.lastofs = self.ofs;
	end

	local props = image_surface_properties(self.canvas.vid);
	local cols  = math.floor(props.width / (self.cell_w + self.hspace));
	local rows  = math.floor(props.height / (self.cell_h + self.vspace));

	self.capacity = cols * rows;
	local tbl = nil;
	
	if (self.capacity > #self.icons) then
		tbl, self.total = self:datasel(self.ofs + #self.icons, 
			self.capacity - #self.icons, self.cell_w, self.cell_h);

		for i, v in ipairs(tbl) do
			awbicon_add(self, v);
		end
	end

	awbwnd_scroll_check(self);
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
	pwin.caph    = 12;
	pwin.vspace  = 6;
	pwin.hspace  = 6;
	pwin.total   = 1;
	pwin.capacity = 1;
	
	if (options) then
		for k,v in pairs(options) do
			pwin[k] = v;
		end
	end

	pwin.canvas.minw = cell_w;
	pwin.canvas.minh = cell_h;

	pwin.ofs       = 1;

	if (type(datasel_fun) == "table") then
		pwin.datasel = def_datasel;
		pwin.tbl = datasel_fun;

	elseif (type(datasel_fun) == "function") then
		pwin.datasel = datasel_fun;
	else
		warning("awbwnd_iconview(broken), no data source specified");
		warning(debug.traceback());
		return nil;
	end

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
	local newicn = bartbl:add_icon("scroll", "fill", scrollbar_icn);
	delete_image(scrollbar_icn);
	pwin.scroll = true;

	link_image(scrollcaret_icn, newicn.vid);
	image_inherit_order(scrollcaret_icn, true);
	order_image(scrollcaret_icn, 1);
	show_image(scrollcaret_icn);
	resize_image(scrollcaret_icn, 
		pwin.dir["t"].size - 2, pwin.dir["t"].size - 2); 

	pwin.orig_resize = pwin.resize;
	pwin.resize = awbicon_resize;

	pwin:resize(pwin.w, pwin.h);

	local caretmh = {
		wnd = pwin,
		caret_dy = 0,
		drag = function(self, vid, dx, dy)
			awbwnd_scroll_caretdrag(self, vid, dx, dy); 
		end,
		drop = function(self, vid, dx, dy)
			awbwnd_scroll_caretdrag(self, vid, dx, dy);
		end,
		name = "list_scroll_caret",
		own = function(self, vid) return scrollcaret_icn == vid; end
	};

	local scrollmh = {
		wnd = pwin,
		caret = scrollcaret_icn,
		name = "icon_scrollbar",
		own = function(self, vid) return newicn.vid == vid; end,
		click = awbwnd_scroll_caretclick
	};

	local canvash = {
		name = "icon_canvas",
		own = function(self, vid) return vid == pwin.canvas.vid; end,
		click = function() pwin:focus(); end
	};

	mouse_addlistener(canvash, {"click"});
	mouse_addlistener(caretmh, {"drag", "drop"});
	mouse_addlistener(scrollmh, {"click"});

	table.insert(pwin.handlers, scrollmh);
	table.insert(pwin.handlers, caretmh);
	table.insert(pwin.handlers, canvash);
	pwin.on_destroy = function()
		for i, v in ipairs(pwin.icons) do
			mouse_droplistener(v);
		end
	end

	pwin:resize(pwin.w, pwin.h);
	return pwin;
end
