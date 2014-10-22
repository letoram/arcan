-- Arcan helperscript, listview.
--
-- Usage:
----------
-- listview_create(elem_list, nelems, font, fontsize) => table
--
-- Note:
-- This is rather dated and could/should be rewritten to take advantage
-- of API changes as to how clipping, ordering etc. work now.
-- (null_surface, color_surface, image_inherit_order, ..)
--
-- Table methods:
--------------------
-- show([order]);
-- destroy();
-- move_cursor(step, relative_motion);
-- push_to_front()
-- select() -> textstr, index
----------------------------------------------------------------------

local function listview_redraw(self)
--	figure out the interval to place in the list
	self.page_beg, self.page_ofs, self.page_end = self:calcpage(self.cursor,
		self.page_size, #self.list);

-- no need to redraw
	if (self.page_beg == self.last_beg and self.page_end == self.last_end) then
		return false;
	end

	if (valid_vid(self.listvid)) then
		delete_image(self.listvid);
	end

	self.last_beg = self.page_beg;
	self.last_end = self.page_end;

	local renderstr = "";

    for ind = self.page_beg, self.page_end do
			local tmpname = self.gsub_ignore and self.list[ind] or
				string.gsub(self.list[ind], "\\", "\\\\");

			local prefix = self.formats[ tmpname ] and self.formats[ tmpname ] or "";
			local suffix = "";

			if (type(prefix) == "table") then
				suffix = prefix[2] and prefix[2] or "";
				prefix = prefix[1] and prefix[1] or "";
			end

			if (string.sub(tmpname, 1, 3) == "---") then
				renderstr = renderstr .. self.hilight_fontstr ..
				string.sub(tmpname, 4) .. [[\n\r]];
			else
				renderstr = string.format("%s%s%s%s%s\\!b\\!i\\n\\r",
					self.data_fontstr, prefix, renderstr, tmpname, suffix);
			end
		end

	renderstr = string.gsub(renderstr, "^%s*(.-)%s*$", "%1");

-- self.list_lines is GCed, .list is "not"
	self.listvid, self.list_lines = render_text(renderstr, self.vspace);

	image_tracetag(self.listvid, "listview(list)");
	link_image(self.listvid, self.window);
	image_clip_on(self.listvid);
	image_inherit_order(self.listvid, true);
	show_image(self.listvid);

--
-- Possibly switch [16] with whatever the font width is for one character
--
	local props   = image_surface_properties(self.listvid);
	self.padding  = 2;
	props.width   = (props.width + self.padding);  --< self.maxw)
--		and (props.width + self.padding) or self.maxw;

	move_image(self.window, self.borderw, self.borderw);
	resize_image(self.border, props.width + self.borderw * 2,
		props.height + self.borderw, self.animspeed, INTERP_EXPOUT);
	resize_image(self.window, props.width,
		props.height - self.borderw, self.animspeed, INTERP_EXPOUT);
	order_image(self.listvid, image_surface_properties(self.window).order + 1);
end

local function listview_invalidate(self)
	self.last_beg = nil;
	self.last_ofs = nil;
end

local function listview_destroy(self)
	if (self.anchor == nil) then
		return;
	end

	if (self.cascade_destroy) then
		self.cascade_destroy:destroy();
	end

	if (mouse_droplistener) then
		mouse_droplistener(self.mhandler);
	end

	resize_image(self.border, 1, 1, self.animspeed, INTERP_EXPOUT);
	resize_image(self.window, 1, 1, self.animspeed, INTERP_EXPOUT);

	blend_image(self.window, 0.0, self.animspeed);
	blend_image(self.border, 0.0, self.animspeed);
	expire_image(self.anchor, self.animspeed);

	if (valid_vid(self.cursorvid)) then
		blend_image(self.cursorvid, 0.0, self.animspeed);
		self.cursorvid = nil;
	end

	if (valid_vid(self.listvid)) then
		blend_image(self.listvid, 0.0, self.animspeed);
		self.listvid = nil;
	end

	self.mhandler = nil;
	self.anchor = nil;
end

local function listview_select(self)
	return self.list[self.cursor];
end

--
-- Used to implement mouse movement
-- translate mouse coordinate into listview space and pass as rely
-- this function will then look up in list-lines and convert into
--
--
local function listview_cursor_toline(self, abs_x, abs_y)
	local props = image_surface_resolve_properties(self.listvid);
	abs_x = abs_x - props.x;
	abs_y = abs_y - props.y;

	if (abs_x > props.width or abs_y > props.height) then
		return;
	end

	local i = 1;
	while i < #self.list_lines-1 and abs_y >= self.list_lines[i+1] do
		i = i + 1;
	end

	return i;
end

local function listview_move_cursor(self, step, relative, mouse_src)
	local itempos = relative and (self.cursor + step) or step;

-- start with wrapping around
	if (itempos < 1) then
		itempos = #self.list;
	elseif (itempos > #self.list) then
		itempos = 1;
	end

-- Special treatment, three dashes means skip (and draw whatever
-- separator glyph in use
	self.cursor = itempos;
	if (string.sub( self.list[ self.cursor ], 1, 3) == "---" ) then
		if (step ~= 0 and mouse_src == nil) then
			self:move_cursor(step, relative);
		end
	end

-- self will only be redrawn if we've landed on a different page
-- / offset than before (or if the datamodel has changed)
	self:redraw();

-- maintain order rather than revert
	local order = image_surface_properties(self.listvid).order;

-- cursor behavior changed (r431 and beyond),
-- now it leaves a quickly fading trail rather than moving around ..
	if (valid_vid(self.cursorvid)) then
		blend_image(self.cursorvid, 0.0, self.animspeed);
		expire_image(self.cursorvid, self.animspeed);
		self.cursorvid = nil;
	end

-- create a new cursor
	self.cursorvid = color_surface(image_surface_properties(
		self.window, self.animspeed).width,
		self.font_size + 2, 255, 255, 255);
	image_mask_set(self.cursorvid, MASK_UNPICKABLE);

	link_image(self.cursorvid, self.listvid);
	image_inherit_order(self.cursorvid, 1);
	image_clip_on(self.cursorvid, CLIP_SHALLOW);
	blend_image(self.cursorvid, 0.3);
	move_image(self.cursorvid, 0, self.list_lines[self.page_ofs] );
	order_image(self.cursorvid, 1);
end

local function listview_tofront(self, base)
	if (self == nil or self.anchor == nil) then
		return;
	end

	if (base == nil) then
		base = max_current_image_order();
	end

	order_image(self.anchor, base);
end

local function listview_calcpage(self, number, size, limit)
	local page_start = math.floor( (number-1) / size) * size;
	local offset = (number - 1) % size;
	local page_end = page_start + size;

	if (page_end > limit) then
		page_end = limit;
	end

	return page_start + 1, offset + 1, page_end;
end

function listview_show(self, order)
	self.anchor    = null_surface(1, 1);
	self.border    = color_surface(8, 8,
		self.dialog_border.r, self.dialog_border.g, self.dialog_border.b);
	self.window    = fill_surface(8, 8,
		self.dialog_window.r, self.dialog_window.g, self.dialog_window.b);

	image_tracetag(self.anchor, "listview(anchor)");
	image_tracetag(self.border, "listview(border)");
	image_tracetag(self.window, "listview(window)");

	image_mask_set(self.window, MASK_UNPICKABLE);
	image_mask_set(self.border, MASK_UNPICKABLE);
	image_mask_set(self.anchor, MASK_UNPICKABLE);

	move_image(self.anchor, 0, 0);

	link_image(self.border, self.anchor);
	link_image(self.window, self.anchor);

	image_inherit_order(self.border, true);
	image_inherit_order(self.window, true);

	order_image(self.window, 1);

	show_image(self.anchor);
	blend_image(self.window, self.dialog_window.a);
	blend_image(self.border, self.dialog_border.a);

	move_image(self.window, self.borderw * 0.5, self.borderw * 0.5);

	self:move_cursor(0, true, false);
	self:push_to_front(order);
end

local function window_height(self, nlines)
	local heightstr = self.hilight_fontstr;
	for i=1,nlines do
		heightstr = heightstr .. " A\\n\\r"
	end
	txw, txh = text_dimensions(heightstr);
	return txh;
end

function listview_create(elem_list, height, maxw, formatlist)
	local restbl = {
		show          = listview_show,
		destroy       = listview_destroy,
		move_cursor   = listview_move_cursor,
		push_to_front = listview_tofront,
		redraw        = listview_redraw,
		select        = listview_select,
  	calcpage      = listview_calcpage,
    invalidate    = listview_invalidate,
		animspeed = 20
	};

	assert(elem_list ~= nil and #elem_list > 0);

	if (settings == nil) then
		settings = {};
	end

	if (settings.colourtable == nil) then
		settings.colourtable = system_load("scripts/colourtable.lua")();
	end

	local mh = {
		name = "listview",
		motion = function(self, vid)
			if (vid ~= restbl.listvid) then
				return;
			end

			local mx, my = mouse_xy();
			local line = listview_cursor_toline(restbl, mx, my);
			if (line and line ~= restbl.cursor) then
				restbl:move_cursor(line, false, true);
			end

			return true;
		end,
		clickh = function(self, vid, dx, dy, left)
			if (restbl.on_click) then
				local line = nil;

				if (vid == restbl.listvid) then
					local mx, my = mouse_xy();
					line = listview_cursor_toline(restbl, mx, my);
					restbl:on_click(line, left);
				end
			end
		end,
		click = function(self, vid, dx, dy)
			self:clickh(vid, dx, dy, false);
		end,
		rclick = function(self, vid, dx, dy)
			self:clickh(vid, dx, dy, true);
		end,
		own = function(self, vid)
			return true;
		end
	};

	restbl.mhandler = mh;
	restbl.height  = height;
	restbl.list    = elem_list;
	restbl.width   = 1;
	restbl.cursor  = 1;
	restbl.borderw = 2;
	restbl.vscroll = false;
	restbl.maxw    = maxw and math.ceil( maxw ) or VRESW;
	restbl.formats = formatlist;

	restbl.font_size       = settings.colourtable.font_size;
	restbl.hilight_fontstr = settings.colourtable.hilight_fontstr;
	restbl.data_fontstr    = settings.colourtable.data_fontstr;
	restbl.dialog_border   = settings.colourtable.dialog_border;
	restbl.dialog_window   = settings.colourtable.dialog_window;
	restbl.gsub_ignore     = false;

	restbl.page_size = math.floor(height/(restbl.font_size + restbl.borderw));

	if (restbl.page_size == 0) then
		warning(string.format("listview_create() -- bad arguments: " ..
			"empty page_size. (%d / %d)\n", height,
			restrbl.font_size + restbl.borderw));
		return nil;
	end

	while (window_height(restbl, restbl.page_size) > height) do
		restbl.page_size = restbl.page_size - 1;
	end
	if (restbl.page_size == 0) then restbl.page_size = 1; end

	if (restbl.formats == nil) then restbl.formats = {}; end
	return restbl;
end
