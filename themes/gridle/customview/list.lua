--
-- simplisting list + icons view
--  

local restbl = {};
restbl.name = "list";

restbl.create = function(self, width, height) 
	self.clipregion = fill_surface(width, height, 0, 0, 0);
	self.selector   = fill_surface(width, settings.colourtable.font_size + 2, 0, 40, 200);

-- icon collections etc. for mame and friends.
	local tmp = glob_resource("icons/*.ico", ALL_RESOURCES);
	self.icons = {};
	for ind,val in ipairs(tmp) do
		self.icons[val] = true;
	end

	link_image(self.selector, self.clipregion);
	image_clip_on(self.selector);
	image_mask_clear(self.selector, MASK_OPACITY);

	self.width  = width;
	self.height = height;

	show_image(self.selector);
	return self.clipregion;
end

restbl.escape = function(self) return true; end
restbl.up     = function(self, step) restbl:step(-1 * step); end
restbl.down   = function(self, step) restbl:step(step); end
restbl.left   = function(self, step) restbl:step(self.page_size * -1 * step); end
restbl.right  = function(self, step) restbl:step(self.page_size * step); end
restbl.current_item = function(self)
	return self.list[self.cursor];
end

restbl.move_cursor = function(self)
	local page_beg, page_ofs, page_end = self:curpage();

	instant_image_transform(self.selector);
	move_image(self.selector, 0, self.menu_lines[page_ofs], 10);
end

restbl.select_random = function(self, fv)
	self.cursor = math.random(1, #data.games);
	self:redraw();
end

restbl.get_linestr = function(self, gametbl)
	local res = gametbl.title;

	if self.icons[gametbl.setname .. ".ico"] then
		res = [[\P16,16,icons/]] .. gametbl.setname .. ".ico," .. res;
	end 

	if self.icons[gametbl.target .. ".ico"] then
		local fs = tostring(settings.colourtable.font_size);
		res = "\\P" .. fs .. "," .. fs ..",icons/" .. gametbl.target .. ".ico," .. res;
	end

	return res;	
end

restbl.redraw = function(self)
	if (valid_vid(self.menu)) then
		delete_image(self.menu);
	end
	
	local page_beg, page_ofs, page_end = self:curpage(); 
	local renderstr = settings.colourtable.data_fontstr;

-- self.linestr is responsible for padding with icons etc.
	for ind = page_beg, page_end do
		renderstr = renderstr .. self:get_linestr(self.list[ind]) .. [[\n\r]];
	end

	local menu, lines = render_text( renderstr, 2 );
	self.menu = menu;
	self.menu_lines = lines;

	link_image(self.menu, self.clipregion);
	image_mask_clear(self.menu, MASK_OPACITY);
	image_clip_on(self.menu);

	order_image(self.menu, max_current_image_order());
	show_image(self.menu);

	self:move_cursor();
	return nil;
end

restbl.drawable = function(self) return self.menu; end

restbl.calc_page = function(self, number, size, limit)
	local page_start = math.floor( (number - 1) / size) * size;
	local offset     = (number - 1) % size;
	local page_end   = page_start + size;
	
	if (page_end > limit) then
		page_end = limit;
	end

	return page_start + 1, offset + 1, page_end;
end

restbl.curpage = function(self)
	return self:calc_page(self.cursor, self.page_size, #self.list);
end

restbl.step = function(self, stepv)
	local curpg, ign, ign2 = self:curpage();

	local ngn = self.cursor + stepv;
	ngn = ngn < 1 and #self.list or ngn;
	ngn = ngn > #self.list and 1 or ngn;

	self.cursor = ngn;
	local newpg, ign, ign2 = self:curpage();

	if (newpg ~= curpg) then
		self:redraw();	
	else
		self:move_cursor();
	end
end

restbl.update_list = function(self, gamelist)
	self.list   = gamelist;
	self.cursor = 1;
	self.page_size = math.floor( self.height / (settings.colourtable.font_size + 4) );
	self:redraw();
end

restbl.trigger_selected = function(self) return self.list[ self.cursor ]; end

return restbl;
