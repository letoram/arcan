--
-- Composition Surface
--
-- Utility script / interface for managing windows
-- connected to external processes / frameservers.
--
-- The use for this is both traditional window
-- management but also for created controlled
-- nested surfaces for recording, remote desktop etc.
--

--
-- missing:
-- adding borders,
-- adding bars,
-- resizing (+ specialized, i.e. maximized, ...)
--
-- => to_rendertarget
--    (setup a render or recordtarget)
--

local function compsurf_find(ctx)
	for k,v in ipairs(ctx.windows) do
		if (v.name == name) then
			return v;
		end
	end
end

local function wnd_ind(surf, wnd)
	for k,v in ipairs(surf.windows) do
		if (surf.windows == wnd) then
			return k;
		end
	end
end

local function broadcast(group, wnd)
	for k,v in ipairs(group) do
		v(wnd);
	end
end

local function compsurf_wnd_select(wnd)
	if (wnd.wm.selected == wnd) then
		return
	end

	if (wnd.wm.selected) then
		broadcast(wnd.wm.handlers.deselect, wnd.wm.selected);
		order_image(wnd.wm.selected.canvas, wnd.wm.selected.deselorder);
	end

	wnd.wm.selected = wnd;
	order_image(wnd.canvas, wnd.selorder);
	broadcast(wnd.wm.handlers.select, wnd);
end

local function compsurf_wnd_destroy(wnd)
	if (wnd.wm.selected == wnd) then
		wnd.wm.selected = nil;
	end

	broadcast(wnd.wm.handlers.destroy, wnd);

	table.remove(wnd.wm.windows, wnd_ind(wnd.wm, wnd));
	delete_image(wnd.canvas);

	for k,v in pairs(wnd) do
		wnd[k] = nil;
	end
	mouse_droplistener(wnd);
end

local function compsurf_wnd_own(wnd, vid)
	return (vid == wnd.canvas or image_children(wnd.canvas, vid));
end

local function compsurf_wnd_click(wnd)
end

local function compsurf_wnd_rclick(wnd)
end

local function compsurf_wnd_dblclick(wnd)
end

local function compsurf_wnd_repos(wnd)
-- limit to managed surface area
	local dx = wnd.x;
	local dy = wnd.y;

	if ((wnd.x - wnd.pad_left) +
		wnd.pad_right + wnd.width > wnd.wm.max_w) then
		dx = wnd.wm.max_w - wnd.width - wnd.pad_left - wnd.pad_right;
	end

	if ((wnd.x - wnd.pad_left) < 0) then
		dx = wnd.pad_left;
	end

	if ((wnd.y - wnd.pad_top) < 0) then
		dy = wnd.pad_top;
	end

	if ((wnd.y - wnd.pad_top) +
		wnd.pad_bottom + wnd.height > wnd.wm.max_h) then
		dy = wnd.wm.max_h - wnd.height - wnd.pad_top - wnd.pad_bottom;
	end

	if (dx ~= wnd.x or dy ~= wnd.y) then
		move_image(wnd.canvas, dx, dy);
		wnd.x = dx;
		wnd.y = dy;
	end
end

local function compsurf_wnd_resize(wnd, neww, newh)
	resize_image(wnd.canvas, neww, newh);
	wnd.width = neww;
	wnd.height = newh;
	compsurf_wnd_repos(wnd);
end

local function compsurf_wnd_drag(wnd, vid, x, y)
	if (wnd.wm.meta == nil) then
		return;
	end

	wnd.dragging = true;

	local mx, my = mouse_xy();
	nudge_image(wnd.canvas, x, y);
	wnd.x = wnd.x + x;
	wnd.y = wnd.y + y;
	compsurf_wnd_repos(wnd);
end

local function compsurf_wnd_drop(wnd)
	wnd.dragging = nil;
end

local function compsurf_wnd_over(wnd)
end

local function compsurf_wnd_press(wnd)
	wnd:select();
end

local function compsurf_wnd_release(wnd)
end

local function compsurf_wnd_out(wnd)
end

local function compsurf_wnd_motion(wnd, vid, x, y)
	if (wnd.dragging or wnd.meta) then
		return;
	end

end

local function compsurf_wnd_hover(wnd)
end

local wseq = 1;

local function compsurf_add_window(ctx, surf, opts)
	local wnd = {
		name = ctx.name .. "_wnd_" .. tostring(wseq),
		wm = ctx,
		canvas = surf,
		select = compsurf_wnd_select,
		destroy = compsurf_wnd_destroy,
		resize = compsurf_wnd_resize,

-- account for additional "tacked-on" surfaces (border, bars, ...)
		pad_left = 0,
		pad_right = 0,
		pad_top = 0,
		pad_bottom = 0,

-- track position / dimensions here to cut down on _properties calls
		x = 0,
		y = 0,
		width = ctx.def_ww,
		height = ctx.def_wh,

-- background "only" objects can fix the orderv.
		selorder = opts.selorder ~= nil and opts.selorder or ctx.selorder,
		deselorder = opts.deselorder ~= nil and opts.deselorder or ctx.deselorder,

-- stub symbol, replace with eg. target_input(source, iotbl)
		input = function() end,

-- default mouse handlers
		own = compsurf_wnd_own,
		click = compsurf_wnd_click,
		dblclick = compsurf_wnd_dblclick,
		rclick = compsurf_wnd_click,
		press = compsurf_wnd_press,
		release = compsurf_wnd_release,
		drag = compsurf_wnd_drag,
		over = compsurf_wnd_over,
		out = compsurf_wnd_out,
		motion = compsurf_wnd_motion,
		hover = compsurf_wnd_hover,
	};

	link_image(wnd.canvas, ctx.canvas);
	image_inherit_order(wnd.canvas, true);

	show_image(wnd.canvas);

	mouse_addlistener(wnd, {"click", "drag",
		"dblclick", "over", "press", "release",
		"out", "hover", "motion"}
	);

	wseq = wseq + 1;
	wnd:select();
	return wnd;
end

local seq = 1;

function compsurf_create(width, height, opts)
	local restbl = {
		canvas = null_surface(width, height),
		windows = {},
		max_w = width,
		max_h = height,
		def_ww = opts.def_ww ~= nil and opts.def_ww or math.floor(width * 0.3),
		def_wh = opts.def_wh ~= nil and opts.def_wh or math.floor(height * 0.3),
		name = opts.name ~= nil and opts.name or ("compsurf_" .. tostring(seq)),
		selorder = opts.selorder ~= nil and opts.selorder or 2,
		deselorder = opts.selorder ~= nil and opts.deselorder or 1,
		find_window = compsurf_find,
		add_window = compsurf_add_window,

-- listen to major state changes
		handlers = {
			select = {},
			deselect = {},
			resize = {},
			destroy = {},
		},
	};

	if (opts) then
		if (opts.borders) then
			restbl.have_borders = true;
		end
	end

	image_mask_set(restbl.canvas, MASK_UNPICKABLE);
	show_image(restbl.canvas);
	seq = seq + 1;
	return restbl;
end
