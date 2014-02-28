--
-- AWB List View
-- Specialized window subclass to handle longer multi-column lists
-- With clickable headers, sorting etc.
-- 
function awbwnd_scroll_check(self)
	if (self.capacity >= self.total) then
		if (self.scroll) then
			self.scroll = false;
			hide_image(self.dir[self.icon_bardir].fill.vid);
			self.dir[self.icon_bardir].oldsz = self.dir[self.icon_bardir].bsize;
			self.dir[self.icon_bardir].bsize = 0;
-- make sure the bar- resize gets updated
			self:orig_resize(self.w, self.h);
		end

		return;

	elseif (self.capacity < self.total and self.scroll == false) then
		self.scroll = true;
		show_image(self.dir[self.icon_bardir].fill.vid);
		self.dir[self.icon_bardir].bsize = self.dir[self.icon_bardir].oldsz;
		self:orig_resize(self.w, self.h);
	end

-- with capacity matching total we don't have a bar to deal with so that
-- case can be safely ignored
	local prop = image_surface_properties(self.dir[self.icon_bardir].fill.vid);
	local barsz = (self.capacity / self.total) * prop.height;

	local yv = math.floor(self.ofs-1+0.001) / self.total * prop.height;

-- special hack to cover rounding / imprecision etc.)
	if (self.ofs + self.capacity >= self.total) then
		move_image(self.scrollcaret, 1, prop.height - barsz - 1);
	else
	 	move_image(self.scrollcaret, 1, 1 + yv);
	end

	resize_image(self.scrollcaret, self.dir[self.icon_bardir].size - 2, barsz);
end

function awblist_resize(self, neww, newh)
	self:orig_resize(neww, newh);
	local props = image_surface_properties(self.canvas.vid);
	move_image(self.ianchor, props.x, props.y);

	self.capacity = math.floor(props.height / (self.lineh + self.linespace)) - 1;

	if (self.capacity < 1) then
		self.capacity = 1;
	end

	if (self.total ~= nil and (self.ofs + self.capacity - 1 > self.total)) then
		self.ofs = self.total - self.capacity;
		
		if (self.ofs < 1) then 
			self.ofs = 1;
		end

		if (self.capacity < self.total) then
			self.invalidate = true;
		end
	end

-- only redraw if we've grown (keep image when shrinking and clip
-- in order to minimize transfers / regenerating the texture), some parts of
-- this function is really expensive and high-resolution mice etc. do
-- emitt lots of resize events when drag-resizing
	if (self.invalidate or (props.height - self.lasth >
		(self.lineh + self.linespace))) then

		self.invalidate = false;
		self.lasth  = props.height;
		self.restbl, self.total = self:datasel(self.ofs, self.capacity, list);	
	
		for i, v in ipairs(self.listtemp) do
			delete_image(v);
		end
		self.listtemp = {};
		self.line_heights = nil;
		
-- Render each column separately, using a clipping anchor 
		local xofs = 0;
		for ind, col in ipairs(self.cols) do
			local clip = null_surface(math.floor(props.width * col), props.height);
			image_tracetag(clip, "listview.col(" .. tostring(ind) .. ").clip");
	
			link_image(clip, self.ianchor);
			show_image(clip);
			image_mask_set(clip, MASK_UNPICKABLE);
			image_inherit_order(clip, true);

			if (ind > 1 and self.collines[ind-1] ~= nil) then
				move_image(self.collines[ind-1], xofs, 0);
				resize_image(self.collines[ind-1], 2, props.height);
			end
	
			xofs = xofs + math.floor(props.width * col) + 4;

-- concat the subselected column lines, force-add headers to the top
			local rendtbl = {};

			for i, v in ipairs(self.restbl) do
				table.insert(rendtbl, v.cols[ind]);
			end

			local colv, lines = self.renderfn(table.concat(rendtbl, [[\n\r]]));
			local colw = image_surface_properties(colv).width;

-- only take the first column (assumed to always be dominating / representative)
			if (self.line_heights == nil) then
				self.line_heights = lines;
			end

			link_image(colv, clip);
			image_tracetag(colv, "listview.col(" .. tostring(ind) ..").column");

			show_image(colv);
			move_image(colv, 0, math.floor(self.linespace * 0.5));
			image_inherit_order(colv, true);
			order_image(colv, 2);
			image_mask_set(colv, MASK_UNPICKABLE);
			image_clip_on(colv, CLIP_SHALLOW);
			table.insert(self.listtemp, clip);  
		end

-- hilighted striped bars to make it easier to distinguish between items
		if (self.bglines) then
			for i,v in ipairs(self.bglines) do
				delete_image(v);
			end
			
			self.bglines = {};

			local yofs = 0;
			for i=2,#self.line_heights do
				if (i % 2 == 0) then
					local a = color_surface(props.width, 
						self.line_heights[i] - self.line_heights[i - 1], 
						self.rowhicol[1], self.rowhicol[2], self.rowhicol[3]);

					move_image(a, 0, self.line_heights[i]);
					link_image(a, self.ianchor); 
					image_tracetag(a, "listview.stripbg");
					show_image(a);
					image_inherit_order(a, true);
					image_clip_on(a);
					image_mask_set(a, MASK_UNPICKABLE);
					table.insert(self.bglines, a);
				end
			end
		end

	end

-- always update clipping anchors
	awbwnd_scroll_check(self);

	local xofs = 0;
	local ctot;
	if (self.scroll) then
		ctot = props.width - self.dir[self.icon_bardir].size;
	else
		ctot = props.width;
	end
	local ccur = ctot;
	
	for i, col in ipairs(self.cols) do
		local clipw = math.floor(props.width * col);

-- if not marked as static enforced columns, make sure that we don't overuse
-- a column with too much space reserved
		if (self.static == nil or self.static == false) then
			local colw = image_surface_properties(image_children(
				self.listtemp[i])[1]).width;

				if (clipw > colw * 1.1) then
					clipw = math.floor(colw * 1.1);
				end
		end

		if (i == #self.cols) then
			clipw = ccur;
		else
			ccur = ccur - clipw;
		end

		resize_image(self.listtemp[i], clipw, props.height);
		move_image(self.listtemp[i], xofs, 0);
	
		if (i > 1 and self.collines[i-1] ~= nil) then
			blend_image(self.collines[i-1], 0.5); 
			move_image(self.collines[i-1], xofs - 2, 0);
			resize_image(self.collines[i-1], 2, props.height); 
		end

		xofs = xofs + clipw;
	end

	if (self.bglines) then
		for i,v in ipairs(self.bglines) do
			resize_image(v, props.width, image_surface_properties(v).height);
		end
	end

	blend_image(self.cursor, self.total == 0 and 0.0 or 1.0);
	resize_image(self.ianchor, props.width, props.height);
	resize_image(self.cursor, ctot, self.lineh + self.linespace);
end

function awbicon_liney(self, yv)
	if (self.line_heights) then

-- find the matching pair and pick the closest one
		for i=1,#self.line_heights-1 do
			local dy1 = self.line_heights[i];
			local dy2 = self.line_heights[i+1];

			if (dy1 <= yv and dy2 >= yv) then
				return dy1, i;
			end
		end

		return self.line_heights[#self.line_heights], #self.line_heights;
	end

	return 0, nil;
end

local function clampofs(self)
	if (self.ofs < 1) then
		self.ofs = 1;

	elseif (self.ofs + self.capacity > self.total) then
		self.ofs = self.total - self.capacity + 1;
	end

	self.ofs = math.floor(self.ofs);
end

function awbwnd_scroll_up(self, n)
	self.ofs = self.ofs - math.abs(n);
	clampofs(self);
	self.lasth = 0;
	self:resize(self.w, self.h);
end

function awbwnd_scroll_down(self, n)
	self.ofs = self.ofs + math.abs(n);
	clampofs(self);
	self.lasth = 0;
	self:resize(self.w, self.h);
end

function awbwnd_scroll_caretdrop(self)
	self.caret_dy = nil;
end

function awbwnd_scroll_caretdrag(self, vid, dx, dy)
	self.wnd:focus();
	
	local mx, my = mouse_xy();
	local pprop = image_surface_resolve_properties(
		self.wnd.dir[self.wnd.icon_bardir].fill.vid);
	
	local mry = (my - pprop.y) / pprop.height;
	mry = mry < 0 and 0 or mry;
	mry = mry > 1 and 1 or mry;

	local lastofs = self.wnd.ofs;
	self.wnd.ofs = 1 + math.ceil(
		(self.wnd.total - self.wnd.capacity) * mry );

	if (self.wnd.ofs + self.wnd.capacity > self.wnd.total + 1) then
		self.wnd.ofs = self.wnd.total - self.wnd.capacity;
	end

	if (lastofs ~= self.wnd.ofs) then
		awbwnd_scroll_up(self.wnd, 0);
	end
end

function awbwnd_scroll_caretclick(self, vid, x, y)
	local props = image_surface_resolve_properties(self.caret);
	self.wnd:focus();

	self.wnd.ofs = (y < props.y) and (self.wnd.ofs - self.wnd.capacity) or
		(self.wnd.ofs + self.wnd.capacity);

	clampofs(self.wnd);

	self.wnd.lasth = 0;
	self.wnd:resize(self.wnd.w, self.wnd.h);
end

local function def_datasel(filter, ofs, lim, list)
	local tbl = filter.tbl;
	local res = {};
	local ul = ofs + lim;
	ul = ul > #tbl and #tbl or ul;

	for i=ofs, ofs+lim do
		table.insert(res, tbl[i]);
	end

	return res, #tbl;
end

function awbwnd_listview(pwin, lineh, linespace, colcfg, datasel_fun, 
	render_fun,scrollbar_icn, scrollcaret_icn, cursor_icn, bardir,
	options)

	if (bardir == nil) then
		bardir = "r";
	end

-- overridable options
	pwin.cell_w   = cell_w;
	pwin.cell_h   = cell_h;
	pwin.rowhicol = {0, 0, 0};
	pwin.bglines  = {};

-- apply user options
	if (options) then
		for k,v in pairs(options) do
			pwin[k] = v;
		end
	end

-- protect against namespace collisions
	pwin.lasth      = 0;
	pwin.lineh      = lineh;
	pwin.linespace  = linespace;
	pwin.ofs        = 1;
	pwin.listtemp   = {};
	local panch = null_surface(1, 1);
	image_mask_set(panch, MASK_UNPICKABLE);
	image_tracetag(panch, "listview(dataanchor)");

	if (type(datasel_fun) == "table") then
		pwin.datasel = def_datasel;
		pwin.tbl = datasel_fun;

	elseif (type(datasel_fun) == "function") then
		pwin.datasel = datasel_fun;

	else
		warning("awbwnd_listview(broken), no data source specified");
		warning(debug.traceback());
	end

	pwin.renderfn   = render_fun;
	pwin.cols       = colcfg;
	pwin.collines   = {};

	for i=2,#pwin.cols do
		local barl = color_surface(1, 2, 255, 255, 255);
		image_tracetag(barl, "bar_handle");
		link_image(barl, panch);
		blend_image(barl, 0.5);
		image_inherit_order(barl, true);
		order_image(barl, 2);
		table.insert(pwin.collines, barl); 
	end

	pwin.scrollup   = awbwnd_scroll_up;
	pwin.scrolldown = awbwnd_scroll_down; 

	pwin.icon_bardir = bardir;
	pwin.scrollcaret = scrollcaret_icn;
	pwin.scroll      = true;
	pwin.line_y      = awbicon_liney;

	image_tracetag(scrollbar_icn,   "awbwnd_listview.scrollbar");
	image_tracetag(scrollcaret_icn, "awbwnd_listview.scrollcaret_icn");

	pwin.on_destroy = function()
		if (pwin.bglines) then
			for ind, val in ipairs(pwin.bglines) do
				delete_image(val);
			end
			pwin.bglines = nil;
		end
	end

	pwin.input = function(self, iotbl)
		if (iotbl.active == false) then
			return;
		end

		if (iotbl.lutsym == "UP") then
			pwin:scrollup(1);

		elseif (iotbl.lutsym == "DOWN") then
			pwin:scrolldown(1);
		end
	end

	pwin.force_update = function(self)
		self.invalidate = true;
		self:resize(self.w, self.h);
	end

-- build scrollbar 
	local bartbl = pwin.dir[bardir];
	local newicn = bartbl:add_icon("scroll", "fill", scrollbar_icn);

	delete_image(scrollbar_icn);
	link_image(scrollcaret_icn, newicn.vid);
	image_inherit_order(scrollcaret_icn, true);
	order_image(newicn.vid, 3);
	order_image(scrollcaret_icn, 3);
	show_image(scrollcaret_icn);
	resize_image(scrollcaret_icn,
		pwin.dir["t"].size - 2, pwin.dir["t"].size - 2); 
	image_clip_on(scrollcaret_icn, CLIP_SHALLOW);

	pwin.orig_resize = pwin.resize;
	pwin.resize = awblist_resize;

	link_image(cursor_icn, panch); 
	image_tracetag(cursor_icn, "cursor_icon");
	image_inherit_order(cursor_icn, true);
	order_image(cursor_icn, 1);
	show_image(cursor_icn);
	blend_image(cursor_icn, 0.8);
	pwin.cursor = cursor_icn;
	image_clip_on(cursor_icn, CLIP_SHALLOW);
	image_mask_set(cursor_icn, MASK_UNPICKABLE);

	local caretmh = {
		wnd  = pwin,
		drag = awbwnd_scroll_caretdrag,
		drop = awbwnd_scroll_caretdrop,
		name = "list_scroll_caret",
		own  = function(self,vid) return scrollcaret_icn == vid; end
	};

	local scrollmh = {
		caret = pwin.scrollcaret,
		wnd   = pwin, 
		name  = "list_scrollbar",
		own   = function(self, vid) return newicn.vid == vid; end,
		click = awbwnd_scroll_caretclick 
	};

	mouse_addlistener(scrollmh, {"click"});
	mouse_addlistener(caretmh,  {"drag", "drop"});

	local mhand = {};
	mhand.dblclick = function(self, vid, x, y)
		pwin:focus();
		local props = image_surface_resolve_properties(pwin.canvas.vid);
		local yofs, linen = pwin:line_y(y - props.y);

		if (linen and pwin.restbl[linen]) then
			pwin.restbl[linen]:trigger(pwin);
		end
	end

	if (options.double_single) then
		mhand.click = mhand.dblclick;
	else
		mhand.click = function(self, vid, x, y)
			local props = image_surface_resolve_properties(pwin.canvas.vid);
			local yofs, linen = pwin:line_y(y - props.y);
			move_image(pwin.cursor, 0, yofs); 
			pwin:focus();
		end
	end

	mhand.rclick = function(self, vid, x, y)
		pwin:focus();
		local props = image_surface_resolve_properties(pwin.canvas.vid);
		local yofs, linen = pwin:line_y(y - props.y);
		if (linen and pwin.restbl[linen] and pwin.restbl[linen].rtrigger) then
			pwin.restbl[linen]:rtrigger(pwin);
			move_image(pwin.cursor, 0, yofs);
		end
	end

	mhand.motion = function(self, vid, x, y)
		if (not pwin:focused() or awbwman_activepopup()) then
			return;
		end

		pwin:focus();
		local props = image_surface_resolve_properties(pwin.canvas.vid);
		local yofs, linen = pwin:line_y(y - props.y);
		pwin.selline = linen;
		move_image(pwin.cursor, 0, yofs); 
	end

	mhand.own = function(self, vid)
		return pwin.canvas.vid == vid;
	end

	mhand.name = "listview_mouseh";
	mouse_addlistener(mhand, {"click", "dblclick", "motion", "rclick"});
	table.insert(pwin.handlers, scrollmh);
	table.insert(pwin.handlers, caretmh);
	table.insert(pwin.handlers, mhand);

--
-- selected cursor management linked to canvas
--
	local props = image_surface_properties(pwin.canvas.vid);

-- we want to anchor this for all the columns etc. to have a different
-- opacity for the canvas
	show_image(panch);
	link_image(panch, pwin.anchor);
	image_inherit_order(panch, true);
	order_image(panch, 2);
	move_image(panch, props.x, props.y);

	pwin.ianchor = panch;
	pwin.mhandler = mhand;
	pwin:resize(pwin.w, pwin.h);
	return pwin;
end
