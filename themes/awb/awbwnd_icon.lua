-- 
-- Sweep the temporary table and distribute in the window region
--
local function awbicon_reposition(self)
	local cx = self.hspace;
	local cy = self.vspace;

	for i, v in ipairs(self.icons) do
		move_image(v, cx, cy);

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
local function awbicon_setscrollbar(self, visible, ofs, total)
	local enabled = image_surface_properties(
		self.dir[self.icon_bardir].fill.vid).opa <= 0;

	if (not enabled and visible <= 0) then
		return;

	elseif (enabled and visible <= 0) then
		hide_image(self.dir[self.icon_bardir].fill.vid);
		self.dir[self.icon_bardir].oldsz = self.dir[self.icon_bardir].bsize;
		self.dir[self.icon_bardir].bsize = 0;
		self:icon_resize(neww, newh);
		return;

	elseif (not enabled and visible >= 0) then
		show_image(self.dir[self.icon_bardir].fill.vid);
		self.dir[self.icon_bardir].bsize = self.dir[self.icon_bardir].oldsz;
		self:icon_resize(neww, newh);
	end

	resize_image(self.scrollcaret, self.topbar_sz, math.floor(self.height * 
		(visible / total)));
	move_image(self.scrollcaret, 1, math.floor(visible * ofs / total));
end

local function awbicon_add(self, icntbl)
-- anchor + clipping region
	local icn_area = null_surface(self.cell_w, self.cell_h);
	move_image(icn_area, cx, cy);
	link_image(icn_area, self.canvas.vid);
	image_inherit_order(icn_area, true);
	image_clip_on(icn_area);
	image_tracetag(icn_area, tostring(icntbl.name) .. ".anchor_region");
	show_image(icn_area);

-- container for icon (lifecycle managed elsewhere)
	icn = null_surface(self.cell_w, self.cell_h);
	image_sharestorage(icntbl.icon, icn);
	link_image(icn, icn_area);
	image_inherit_order(icn, true);
	image_clip_on(icn);
	order_image(icn, 1);
	show_image(icn);
	image_tracetag(icn, tostring(icntbl.name) .. ".icon");

-- caption is managed here however, assumed caption.height < icnh-2-icnsize
-- (if the icon is descriptive enough, just don't prove a caption)
-- otherwise, apply cropping / clipping to caption before calling _add
	if (icntbl.caption) then
		local props = image_surface_properties(icntbl.caption);
		link_image(icntbl.caption, icn_area);
		show_image(icntbl.caption);
		image_inherit_order(icntbl.caption, true);
		order_image(icntbl.caption, 1);
		image_clip_on(icntbl.caption);
		image_tracetag(icntbl.caption, tostring(icntbl.name) .. ".caption");
		move_image(icntbl.caption, math.floor(0.5 * (self.cell_w - props.width)),
			self.cell_h - props.height);
	end

-- aspect correct fitting the icon into the clipping region
	resize_image(icn, self.icon_sz, self.icon_sz);
	move_image(icn, math.floor(0.5 * (self.cell_w - self.icon_sz)), 0);	

-- icn_area works as container for deletions as well
	table.insert(self.icons, icn_area);
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
	local lim   = cols * rows;
	local total = 0;
	local tbl = nil;

-- grow (request more icons at self.ofs + #icons)
-- shrink (drop n items from the end of icons)
-- else just reposition
	if (lim > #self.icons) then
		tbl, total = self:datasel(self.ofs + #self.icons, lim - #self.icons, 
			self.cell_w, self.cell_h);

		for i, v in ipairs(tbl) do
			awbicon_add(self, v);
		end

	elseif (lim < #self.icons) then
		for i=#self.icons,lim,-1 do
			local tbl = table.remove(self.icons);
			if (valid_vid(tbl)) then
				delete_image(tbl);
			end

		end
	end

-- show scrollbar / move scroll-cursor
	self:reposition();
end

local function scrollbar_click(self, x, y)
	print("click at local:", x, y);
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

	link_image(scrollcaret_icn, newicn.vid);
	image_inherit_order(scrollcaret_icn, true);
	order_image(scrollcaret_icn, 1);
	show_image(scrollcaret_icn);
	resize_image(scrollcaret_icn, 
		pwin.dir["t"].size - 2, pwin.dir["t"].size - 2); 

	pwin.icon_resize = pwin.resize;
	pwin.resize = awbicon_resize;

	pwin:resize(pwin.w, pwin.h);
	return pwin;
end
