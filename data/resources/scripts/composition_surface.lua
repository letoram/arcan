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
-- missing:
-- adding bars,
-- resizing (+ specialized, i.e. maximized, ...)
--
-- => to_rendertarget
--    (setup a render or recordtarget)
--

--
-- indexed by border type and width
--
local border_shaders = {
};

local default_width = 1;

--
-- support different border shaders to allow i.e.
-- blurred or textured etc.
--

local shader_types = {};
if (SHADER_LANGUAGE == "GLSL120") then
	shader_types["default"] = [[
	uniform sampler2D map_diffuse;
	uniform float border;
	uniform float obj_opacity;
	uniform vec2 obj_output_sz;

	varying vec2 texco;

	void main()
	{
		vec3 col = texture2D(map_diffuse, texco).rgb;
		float margin_s = border / obj_output_sz.x;
		float margin_t = border / obj_output_sz.y;

		if ( texco.s <= 1.0 - margin_s && texco.s >= margin_s &&
			texco.t <= 1.0 - margin_t && texco.t >= margin_t )
			discard;

		gl_FragColor = vec4(col.r, col.g, col.b, 1.0);
	]];
else
-- note, no support for GLES yet
end

local function get_border_shader(width, subtype)
	if (subtype == nil) then
		subtype = "default";
	end

	if (shader_types[subtype] == nil) then
		warning("composition_surface.lua::get_border_shader()" ..
			"invalid_subtype: " .. subtype);
		return border_shaders[default][default_width];
	end

	if (border_shaders[subtype][width] ~= nil) then
		return border_shaders[subtype][width];
	end

	border_shaders[subtype][width] = build_shader(nil,
		shader_types[subtype], "border_shader_" .. tostring(width));

	shader_uniform(border_shaders[subtype][width],
		"border", "f", PERSIST, width);

	return border_shaders[subtype][width];
end

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

	if (wnd.border) then
		resize_image(wnd.border, wnd.width + wnd.borderw * 2,
			wnd.height + wnd.borderw * 2);
	end

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

--
-- return or create a bar with desired thickness
--
local function compsurf_wnd_bar(wnd, dir, thickness)
end

--
-- enable (width > 0) / disable border with optional color ([4])
--
local function compsurf_wnd_border(wnd, width, col)
	if (col == nil) then
		col = {255, 255, 255, 255};
	end

	if (valid_vid(wnd.border)) then
		delete_image(wnd.border);
	end

	if (width <= 0) then
		wnd.border = nil;
		wnd.borderw = 0;
		return;
	end

	wnd.border = fill_surface(2, 2, col[1], col[2], col[3]);
	wnd.borderw = width;

	image_shader(wnd.border, get_border_shader(width));
	resize_image(wnd.border, wnd.width + width * 2, wnd.height + width * 2);
	move_image(wnd.border, -1 * width, -1 * width);
	show_image(wnd.border);
	link_image(wnd.border, wnd.canvas);
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

		set_bar = compsurf_wnd_bar,
		set_border = compsurf_wnd_border,

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
	resize_image(wnd.canvas, wnd.width, wnd.height);
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

-- explicitly hint what state the cursor should be in
		cursor_normal = function() end,
		cursor_resize = function() end,
		cursor_move = function() end,

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

--
-- precompile the default shader types and
-- hope that the driver is "competent" enough to cache
--
if (defw == nil) then
	defw = 2;
end

default_width = defw;

for k, v in pairs(shader_types) do
	border_shaders[k] = {};
	get_border_shader(default_width, k);
end
