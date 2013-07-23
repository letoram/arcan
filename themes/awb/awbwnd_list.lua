--
-- Assume hetroneneous linesize
--
function awblist_resize(self, neww, newh)
	self:list_resize(neww, newh);
	local props = image_surface_properties(self.canvas.vid);

-- only redraw if we've grown (keep image when shrinking)
	if (props.height - self.lasth > self.lineh) then
		self.lasth  = props.height;
		self.restbl = self:datasel(self.ofs, math.ceil(newh / self.lineh));

		for i, v in ipairs(self.listtemp) do
			delete_image(v);
		end
		self.listtemp = {};

-- Render each column separately, using a clipping anchor 
		local xofs = 0;
		for ind, col in ipairs(self.cols) do
			local clip = null_surface(math.floor(
				props.width * col), props.height);
	
			link_image(clip, self.canvas.vid);
			show_image(clip);
			image_mask_set(clip, MASK_UNPICKABLE);
			image_inherit_order(clip, true);
			image_tracetag(clip, "listview.col(" .. tostring(ind) .. ").clip");
			xofs = xofs + math.floor(props.width * col);

			local rendtbl = {};
			for i, v in ipairs(self.restbl) do
				table.insert(rendtbl, v.cols[ind]);
			end

			local colv, lines = self.renderfn(table.concat(rendtbl, [[\n\r]]));
			self.line_heights = lines;

			link_image(colv, clip);
			show_image(colv);
			image_tracetag(colv, "listview.col(" .. tostring(ind) ..").column");
			image_inherit_order(colv, true);
			image_mask_set(colv, MASK_UNPICKABLE);
			image_clip_on(colv, CLIP_SHALLOW);
			table.insert(self.listtemp, clip);
		end
	end

-- always update clipping anchors
	local xofs = 0;
	for i, col in ipairs(self.cols) do
		local clipw = math.floor(props.width * col);
		resize_image(self.listtemp[i], clipw, props.height);
		move_image(self.listtemp[i], xofs, 0);
		xofs = xofs + clipw;
	end

	resize_image(self.cursor, props.width, self.lineh);
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

function awbwnd_listview(pwin, lineh, colcfg, datasel_fun, render_fun,
	scrollbar_icn, scrollcaret_icn, cursor_icn, bardir, options)

	if (bardir == nil) then
		bardir = "r";
	end

	pwin.cell_w  = cell_w;
	pwin.cell_h  = cell_h;
	
	if (options) then
		for k,v in pairs(options) do
			pwin[k] = v;
		end
	end

	pwin.lasth     = 0;
	pwin.lineh     = lineh;
	pwin.ofs       = 1;
	pwin.listtemp  = {};
	pwin.datasel   = datasel_fun;
	pwin.renderfn  = render_fun;
	pwin.cols      = colcfg; 

	pwin.icon_bardir = bardir;
	pwin.scrollcaret = scrollcaret_icn;
--	pwin.scrollbar   = awbicon_setscrollbar;
	pwin.line_y      = awbicon_liney;

	image_tracetag(scrollbar_icn,   "awbwnd_listview.scrollbar");
	image_tracetag(scrollcaret_icn, "awbwnd_listview.scrollcaret_icn");

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

	pwin.list_resize = pwin.resize;
	pwin.resize = awblist_resize;

	link_image(cursor_icn, pwin.canvas.vid);
	image_inherit_order(cursor_icn, true);
	blend_image(cursor_icn, 0.8);
	pwin.cursor = cursor_icn;
	image_clip_on(cursor_icn, CLIP_SHALLOW);
	image_mask_set(cursor_icn, MASK_UNPICKABLE);

-- find cursor ..
	local mhand = {};
	mhand.dblclick = function(self, vid, x, y)
		local props = image_surface_resolve_properties(pwin.canvas.vid);
		local yofs, linen = pwin:line_y(y - props.y);

		if (linen and pwin.restbl[linen]) then
			pwin.restbl[linen]:trigger();
		end
	end

	mhand.motion = function(self, vid, x, y)
		local props = image_surface_resolve_properties(pwin.canvas.vid);
		local yofs, linen = pwin:line_y(y - props.y);
		move_image(pwin.cursor, 0, yofs); 
	end

	mhand.own = function(self, vid)
		return pwin.canvas.vid == vid;
	end

	mouse_addlistener(mhand, {"dblclick", "motion"}); 
--
-- selected cursor management linked to canvas
-- 
	pwin:resize(pwin.w, pwin.h);
	return pwin;
end
