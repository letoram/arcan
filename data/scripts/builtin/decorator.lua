--
-- a basic window decorator
--
-- The decorations currently cover border, as well as managing reserved space
-- for various decorations ('pad region')
--
-- Example use is as follows:
--     local decor_mgr = system_load("builtin/decorator.lua")()
--     local decor_cfg = {
--         size = {4, 4, 2, 2}, -- t, l, d, r
--         pad = {0, 0, 0, 0}, -- reserve n pixel in sub- direction for other decor
--         drag_rz = function(continued, dx, dy, x, y)
--         select = on_select,
--     }
--
--     local decorate = decor_mgr(decor_cfg)
--     local ctx = decorate(vid)
--
-- Which will build decoration objects, link and order them to the video
-- identifier.
--
-- To set visuals:
--     ctx:border_color(r, g, b, alpha)
--
-- To reassign to a different rendertarget:
--     ctx:switch_rt(rt_vid)
--
-- When finished with the decorations:
--     ctx:destroy()
--
-- The mouse event handlers in cfg provide:
--     drag_rz(ctx, border, dx, dy, mask_x, mask_y)
--     drag_move(ctx, border, dx, dy)
--
if not table.copy then
	system_load("builtin/table.lua")()
end

local function decor_destroy(ctx)
	for _,v in pairs(ctx.vids) do
		if valid_vid(v) then
			delete_image(v)
		end
	end

	for _,v in ipairs(ctx.mhs) do
		mouse_droplistener(v)
	end
end

local function border_color(ctx, r, g, b, a)
	for _, v in ipairs({"t", "l", "d", "r"}) do
		local vid = ctx.vids[v]
		if vid then
			image_color(vid, r, g, b)
			blend_image(vid, a, 1)
		end
	end
end

local function switch_rt(ctx, rt)
	for _, v in pairs(ctx.vids) do
		rendertarget_attach(rt, v, RENDERTARGET_DETACH)
	end
end

local function self_own(ctx, vid)
	return vid == ctx.self
end

local function border_click(ctx, vid)

end

-- 0 == lower edge
-- 1 == base
-- 2 == upper edge
-- to get surface-local coordinates we need the anchor, don't cache
-- this for animated surfaces as high-res
local function surface_state(tbl, delta, width)
-- option is to go either % or fixed px size, handle really small windows too
	local pct = delta / (width + 1)
	if delta < 16 then
		return 0
	elseif width - delta < 16 then
		return 2
	end
	return 1
end

-- icon name, mask x, mask y, move-mask x, move-mask y
local dirtbl = {
	{"rz_diag_l", -1,-1, -1, -1},
	{"rz_up"    , 0, -1,  0, -1},
	{"rz_diag_r", 1, -1,  0,  -1},
	{"rz_right",  1, 0,  0,  0},
	{"rz_diag_r", 1, 1,  0,  0},
	{"rz_down",   0, 1,  0,  0},
	{"rz_diag_l",-1, 1, -1,  0},
	{"rz_left",  -1, 0, -1,  0},
};

-- convert absolute-position and resolved object into a cursor and drag-mask
local function sl_to_dir_mask(props, x, y, h, near)
	if h then
		local edge = surface_state(props, x - props.x, props.width)
		if edge == 0 then -- ul, ll
			return near and dirtbl[1] or dirtbl[7]
		elseif edge == 1 then -- u, d
			return near and dirtbl[2] or dirtbl[6]
		else -- ur, lr
			return near and dirtbl[3] or dirtbl[5]
		end
	else
		local edge = surface_state(props, y - props.y, props.height)
		if edge == 0 then -- ul, ur
			return near and dirtbl[1] or dirtbl[3]
		elseif edge == 1 then -- l r
			return near and dirtbl[8] or dirtbl[4]
		else -- ll, lr
			return near and dirtbl[7] or dirtbl[5]
		end
	end
end

local function add_mouse(tbl, vid, mx, my, horiz, near, name)
	table.insert(tbl.mhs, {
		name = name,
		self = vid,
		pcache = {image_surface_resolve(vid), CLOCK},
		own = self_own,
		click = function(ctx)
			if tbl.select then
				tbl.select(tbl, true, ctx.last_cursor)
			end
		end,
		drag =
		function(ctx, vid, dx, dy)
			if not tbl.drag_rz then
				return
			end
			tbl.drag_rz(
				tbl, true,
					dx * ctx.drag_mask[1], dy * ctx.drag_mask[2],
					ctx.move_mask[1], ctx.move_mask[2]
			)
		end,
		drop =
		function(ctx, vid)
			if tbl.drag_rz then
				tbl.drag_rz(tbl, false, 0, 0, 0, 0)
			end
			if tbl.select then
				tbl.select(tbl, true, ctx.last_cursor)
			end
		end,
		motion =
		function(ctx, vid, x, y, rx, ry)
			if CLOCK - ctx.pcache[2] > 10 then
				ctx.pcache[1] = image_surface_resolve(vid)
			end
			local mask = sl_to_dir_mask(ctx.pcache[1], x, y, horiz, near)
			ctx.drag_mask = {mask[2], mask[3]}
			ctx.move_mask = {mask[4], mask[5]}

-- only fire on cursor change
			if tbl.select and ctx.current_cursor ~= ctx.last_cursor then
				ctx.current_cursor = mask[1]
				tbl.select(tbl, false, mask[1])
			end

			ctx.last_cursor = mask[1]
		end,
		out = function(ctx)
			if tbl.select then
				ctx.current_cursor = nil
				tbl.select(tbl, false)
			end
		end
-- just drop cursor, out one surface then becomes enter another
		}
	)
	mouse_addlistener(tbl.mhs[#tbl.mhs], {"drag", "drop", "motion", "out"})
end

local function get_fb(tbl, ind, fb)
	return tbl[ind] and tbl[ind] or fb
end

function build_decor(vid, cfg)
	local res = {
		update = function()
		end,
		switch_rt = switch_rt,
		destroy = decor_destroy,
		border_color = border_color,
		drag_rz = cfg.drag_rz,
		select = cfg.select,
		vids = {},
		mhs = {}
	}

	if not valid_vid(vid) then
		return false, "attempt to decorate a non-existing video object"
	end

-- should we pay the price for mouse events or not
	local use_mouse = cfg.drag_rz ~= nil or cfg.select ~= nil

	if not cfg.border or #cfg.border ~= 4 then
		return false, "missing border / invalid size (t,l,d,r) expected"
	end

	res.border = table.copy(cfg.border)
-- allow config provided 'extra' padding to allow space for scroll-bars
-- titlebar, statusbar and other kinds of decor
	local wpad = {0, 0, 0, 0}
	if cfg.pad then
		wpad = cfg.pad
	end

	if cfg.border[1] > 0 then
-- have 'top' extend over 'left' and 'right' as well
		local pad = cfg.border[2] + cfg.border[4] + wpad[2] + wpad[4]
		res.vids.t = color_surface(pad + 1, cfg.border[1], 1, 32, 32, 32)
		link_image(res.vids.t, vid, ANCHOR_UL, ANCHOR_SCALE_W)
		move_image(res.vids.t, -cfg.border[2] - wpad[2], -cfg.border[1] - wpad[1])

		if not cfg.force_order then
			image_inherit_order(res.vids.t, true)
			order_image(res.vids.t, 1)
		else
			order_image(res.vids.t, cfg.force_order)
		end

		if use_mouse then
			add_mouse(res, res.vids.t, -1, 0, true, true, "top")
		end
	end

	if cfg.border[2] > 0 then
		local pad = wpad[1] + wpad[3]
		res.vids.l = color_surface(cfg.border[2], pad+1, 32, 32, 32)

		link_image(res.vids.l, vid, ANCHOR_UL, ANCHOR_SCALE_H)
		move_image(res.vids.l, -cfg.border[2] - wpad[2], -wpad[1]);

		image_inherit_order(res.vids.l, true)

		if not cfg.force_order then
			image_inherit_order(res.vids.l, true)
			order_image(res.vids.l, 1)
		else
			order_image(res.vids.l, cfg.force_order)
		end

		if use_mouse then
			add_mouse(res, res.vids.l, -1, 0, false, true, "left")
		end
	end

	if cfg.border[3] > 0 then
		local pad = cfg.border[2] + cfg.border[4] + wpad[2] + wpad[4]
		res.vids.d = color_surface(pad + 1, cfg.border[3], 1, 32, 32, 32)

		link_image(res.vids.d, vid, ANCHOR_LL, ANCHOR_SCALE_W)
		image_inherit_order(res.vids.d, true)

		if not cfg.force_order then
			image_inherit_order(res.vids.d, true)
			order_image(res.vids.d, 1)
		else
			order_image(res.vids.d, cfg.force_order)
		end

		move_image(res.vids.d, -cfg.border[2] - wpad[2], wpad[3]);

		if use_mouse then
			add_mouse(res, res.vids.d, 0, 1, true, false, "down")
		end
	end

	if cfg.border[4] > 0 then
		local pad = wpad[1] + wpad[3]
		res.vids.r = color_surface(cfg.border[4], pad+1, 32, 32, 32)
		link_image(res.vids.r, vid, ANCHOR_UR, ANCHOR_SCALE_H)
		image_inherit_order(res.vids.r, true)

		if not cfg.force_order then
			image_inherit_order(res.vids.r, true)
			order_image(res.vids.r, 1)
		else
			order_image(res.vids.r, cfg.force_order)
		end

		move_image(res.vids.r, wpad[4], -wpad[1])

		if use_mouse then
			add_mouse(res, res.vids.r, 0, 1, false, false, "right")
		end
	end

	return res
end

return function(cfg)
	return function(vid)
		return build_decor(vid, cfg)
	end
end
