-- Arcan helperscript, listview.
--
-- Usage:
----------
-- listview_create(elem_list, nelems, font, fontsize) => table
--
-- Table methods:
--------------------
-- show();
-- inactivate();
-- destroy();
-- move_cursor(step, relative_motion);
-- window_color(borderr, borderg, borderb, windowr, windowg, windowb);
-- window_opacity(borderopa, windowopa)
-- window_vid() -> vid
-- push_to_front()
-- select() -> textstr, index
----------------------------------------------------------------------

local function listview_color(self, borderr, borderg, borderb, windowr, windowg, windowb)
	local bprops = {x = 0, y = 0, width = 1, height = 1, opa = 1.0};
	local wprops = {opa = 1.0, width = 1, height = 1, x = 3, y = 3};
-- copy surface properties so that we can reset them on the new objects
	if (self.window and self.window ~= BADID) then wprops = image_surface_properties(self.window); delete_image(self.window); end
	if (self.border and self.border ~= BADID) then bprops = image_surface_properties(self.border); delete_image(self.border); end

	self.border = fill_surface(8, 8, borderr, borderg, borderb);
	self.window = fill_surface(8, 8, windowr, windowg, windowb);

-- we associate with an anchor used for movement so that we can clip to
-- window rather than border
	link_image(self.border, restbl.anchor);
	link_image(self.window, restbl.anchor);
	
	image_mask_clear(self.border, MASK_SCALE);
	image_mask_clear(self.border, MASK_OPACITY);
	image_mask_clear(self.window, MASK_SCALE);
	image_mask_clear(self.window, MASK_OPACITY);

-- reset all the old properties
	resize_image(self.border, bprops.width, bprops.height);
	resize_image(self.window, wprops.width, wprops.height);
	move_image(self.window, wprops.x, wprops.y);
	move_image(self.border, bprops.x, bprops.y);
	blend_image(self.window, wprops.opa);
	blend_image(self.border, bprops.opa);
end

local function listview_vid(self)
	return self.anchor;
end

local function listview_opacity(self, borderopa, windowopa)
	blend_image(self.window, windowopa);
	blend_image(self.border, borderopa);
end

local function listview_redraw(self)
	local opa = 1.0;
	
	if (self.listvid and self.listvid ~= BADID) then
		delete_image(self.listvid);
	end
	
--	figure out the interval to place in the list
	self.page_beg, self.page_ofs, self.page_end = self:calcpage(self.cursor, self.page_size, #self.list);
	
    renderstr = self.fontstr;
    for ind = self.page_beg, self.page_end do
		tmpname = self.list[ind];
		renderstr = renderstr .. tmpname .. [[\n\r]];
    end

-- self.list_lines is GCed, .list is "not"
	self.listvid, self.list_lines = render_text(renderstr, self.vspace);
	self.width = image_surface_properties(self.listvid).width + 4;
	link_image(self.listvid, self.window);
	image_mask_clear(self.listvid, MASK_OPACITY);
	image_clip_on(self.listvid);
	order_image(self.listvid, self.order + 2);
	blend_image(self.listvid, opa);
end

local function listview_destroy(self)
	expire_image(self.window, 20);
	blend_image(self.window, 0.0, 20);
	expire_image(self.border, 20);
	blend_image(self.border, 0.0, 20);
	expire_image(self.cursorvid, 20);
	blend_image(self.cursorvid, 0.0, 20);
	expire_image(self.listvid, 20);
	blend_image(self.listvid, 0.0, 20);
end

local function listview_show(self)
	show_image(self.window);
	show_image(self.border);
	self:redraw();
end

local function listview_select(self)
	return self.list[self.cursor];
end

local function listview_move_cursor(self, step, relative)
    local itempos = relative and (self.cursor + step) or step;
	
    if (itempos < 1) then
		itempos = #self.list;
    elseif (itempos > #self.list) then
		itempos = 1;
    end

    self.cursor = itempos;
	self:redraw();
	instant_image_transform(self.cursorvid);
	move_image(self.cursorvid, 0, self.list_lines[self.page_ofs] - 2 + self.yofs, 10);
	resize_image(self.cursorvid, self.width, self.fontsize);
	order_image(self.cursorvid, self.order+3);
end

local function listview_tofront(self)
	self.order = max_current_image_order() + 1;
	order_image(self.window, self.order+1);
	order_image(self.border, self.order);
	order_image(self.listvid, self.order+2);
	order_image(self.cursorvid, self.order+3);
end

-- Need this wholeheartedly to get around the headache of 1-indexed vs ofset. 
local function listview_calcpage(self, number, size, limit)
    local page_start = math.floor( (number-1) / size) * size;
    local offset = (number - 1) % size;
    local page_end = page_start + size;
    
    if (page_end > limit) then
		page_end = limit;
    end

    return page_start + 1, offset + 1, page_end;
end

function listview_create(elem_list, height, maxw, font, fontsize)
	restbl = {};
	restbl.anchor = fill_surface(1, 1, 0, 0, 0);
	restbl.cursorvid = fill_surface(1, 1, 255, 255, 255);
	restbl.yofs = 6;
	link_image(restbl.cursorvid, restbl.anchor);
	blend_image(restbl.cursorvid, 0.3);
	image_mask_clear(restbl.cursorvid, MASK_OPACITY);
			
	restbl.height = height;
	restbl.list = elem_list;

	restbl.width = 1;
	restbl.cursor = 1;
	
	if (font) then
		restbl.fontsize = fontsize;
		restbl.fontstr  = font .. "," .. fontsize .. " "; 
	else
		restbl.fontsize = 18;
		restbl.fontstr  = [[\#ffffff\ffonts/default.ttf,18 ]];
	end

	restbl.page_size = math.floor( height / (restbl.fontsize + 6) );
	restbl.window_color = listview_color;
	restbl.window_opacity = listview_opacity;
	restbl.show = listview_show;
	restbl.inactivate = listview_inactivate;
	restbl.destroy = listview_destroy;
	restbl.move_cursor = listview_move_cursor;
	restbl.window_vid = listview_vid;
	restbl.push_to_front = listview_tofront;
	restbl.redraw = listview_redraw;
	restbl.select = listview_select;
	restbl.calcpage = listview_calcpage;
	
	restbl.elements = elem_list;

	restbl.order = 0;
	restbl:window_color(0, 0, 255, 0, 0, 164);
	restbl:window_opacity(0.2, 0.8);
	restbl:move_cursor(0, true);
	restbl:push_to_front();

-- some minor cleanup, "scale-" anmate, make sure cursor sizes etc. align
	local props = image_surface_properties(restbl.listvid);
	local windw = props.width + 10;
	if (windw > maxw) then windw = maxw; end
	
	resize_image(restbl.window, windw - 6, restbl.height - 6, 10);
	resize_image(restbl.border, windw, restbl.height, 10);
	return restbl;
end
