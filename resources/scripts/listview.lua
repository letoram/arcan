-- Arcan helperscript, listview.
--
-- Usage:
----------
-- listview_create(elem_list, nelems, font, fontsize) => table
--
-- Table methods:
--------------------
-- show();
-- destroy();
-- move_cursor(step, relative_motion);
-- push_to_front()
-- select() -> textstr, index
----------------------------------------------------------------------

local function listview_redraw(self)
	if (valid_vid(self.listvid)) then	delete_image(self.listvid); end
	
--	figure out the interval to place in the list
	self.page_beg, self.page_ofs, self.page_end = self:calcpage(self.cursor, self.page_size, #self.list);
	renderstr = "";
	
    for ind = self.page_beg, self.page_end do
			local tmpname = string.gsub(self.list[ind], "\\", "\\\\");
			local fmt = self.formats[ tmpname ];
			
			if (string.sub(tmpname, 1, 3) == "---") then
				renderstr = renderstr .. settings.colourtable.hilight_fontstr .. tmpname .. [[\n\r]];
			else
				if (fmt) then
					renderstr = renderstr .. fmt .. tmpname .. [[\n\r]];
				else
					renderstr = renderstr .. settings.colourtable.data_fontstr .. tmpname .. [[\n\r]];
				end
			end
		end

-- self.list_lines is GCed, .list is "not"
	self.listvid, self.list_lines = render_text(renderstr, self.vspace);
	
	link_image(self.listvid, self.window);
	image_clip_on(self.listvid);
	show_image(self.listvid);
	
	local props = image_surface_properties(self.listvid);
	props.width = (props.width + 10 > 0) and (props.width + 10) or self.maxw;

	resize_image(self.border, props.width, props.height, 5);
	resize_image(self.window, props.width - 6, props.height - 6, 5);

	order_image(self.listvid, image_surface_properties(self.window).order + 1);
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
	expire_image(self.anchor, 20);
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
	if (string.sub( self.list[ self.cursor ], 1, 3) == "---" ) then
		if (step ~= 0) then 
			self:move_cursor(step, relative);
		end
	end

-- this one is pretty inefficient as it will always drop / redraw the list 
	self:redraw();

	local order = image_surface_properties(self.listvid).order;
	
-- could be fixed by caching page etc. and see if we land on a new one
	instant_image_transform(self.cursorvid);
	move_image(self.cursorvid, 3, self.list_lines[self.page_ofs] + 4, 10);
	resize_image(self.cursorvid, image_surface_properties(self.window, 5).width, settings.colourtable.font_size + 2);
	order_image(self.cursorvid, order + 1);
end

local function listview_tofront(self)
	local base = max_current_image_order();
	order_image(self.border, base + 1); 
	order_image(self.window, base + 2); 
	order_image(self.listvid, base + 3); 
	order_image(self.cursorvid, base + 4);
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

function listview_show(self)
	restbl.anchor    = fill_surface(1, 1, 0, 0, 0);
	restbl.cursorvid = fill_surface(1, 1, 255, 255, 255);
	restbl.border    = fill_surface(8, 8, settings.colourtable.dialog_border.r, settings.colourtable.dialog_border.g, settings.colourtable.dialog_border.b);
	restbl.window    = fill_surface(8, 8, settings.colourtable.dialog_window.r, settings.colourtable.dialog_window.g, settings.colourtable.dialog_window.b);

	move_image(restbl.anchor, -1, -1);
	blend_image(restbl.anchor, 1.0, settings.fadedelay);
	
	link_image(self.border, restbl.anchor);
	link_image(self.window, restbl.anchor);

	blend_image(self.window, settings.colourtable.dialog_window.a);
	blend_image(self.border, settings.colourtable.dialog_border.a);
	
	link_image(self.cursorvid, restbl.anchor);
	blend_image(self.cursorvid, 0.3);
	move_image(self.window, 3, 3);

	self:move_cursor(0, true);
	self:push_to_front();
end

function listview_create(elem_list, height, maxw, formatlist)
	restbl = {};
	
-- we associate with an anchor used for movement so that we can clip to
-- window rather than border
	if (settings == nil) then settings = {}; end
	if (settings.colourtable == nil) then settings.colourtable = system_load("scripts/colourtable.lua")(); end
	
	restbl.height = height;
	restbl.list = elem_list;
	restbl.width = 1;
	restbl.cursor = 1;
	restbl.maxw = math.ceil( maxw );

	restbl.page_size = math.floor( height / (settings.colourtable.font_size + 6) );
	if (restbl.page_size == 0) then
		warning("listview_create() -- bad arguments: empty page_size. (" .. tostring(height) .. " / " .. tostring(settings.colourtable.font_size + 6) .. ")\n");
		return nil;
	end
		
	restbl.show = listview_show;
	restbl.destroy = listview_destroy;
	restbl.move_cursor = listview_move_cursor;
	restbl.push_to_front = listview_tofront;
	restbl.redraw = listview_redraw;
	restbl.select = listview_select;
	restbl.calcpage = listview_calcpage;
	restbl.formats = formatlist;

	if (restbl.formats == nil) then restbl.formats = {}; end
	return restbl;
end
