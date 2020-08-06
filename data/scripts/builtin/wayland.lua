--
-- pseudo-window manager helper script for working with wayland and
-- x-wayland clients specifically.
--
-- Returns a factory function for taking a wayland-bridge carrying a
-- single client and constructing a wm/state tracker.
--
-- factory(vid, segreq_table, config)
--
-- i.e.
-- if status.kind == "segment-request" then
--     wm = factory(vid, status, config)
-- end
--
-- config contains display options and possible wm event hooks for
-- latching into an outer wm scheme.
--
-- missing:
--
--  [ ] animation controls
--  [ ] xwayland considerations
--  [ ] data-device
--  [ ] drag and drop
--  [ ] popups / positioners
--  [ ] subsurfaces / rendertarget aggregation
--  [ ] decoration controls
--
local x11_lut =
{
	["type"] =
	function(ctx, source, typename)
-- special:
--  popup
--  dropdown
--  tooltip
--  menu
--  utility
--  notification
--  icon
--  dnd
	end,
	["pair"] =
	function(ctx, source, wl_id, x11_id)
	end,
	["fullscreen"] =
	function(ctx, source, on)
	end,
}

-- this table contains hacks around some bits in wayland that does not map to
-- regular events in shmif and comes packed in 'message' events
local wl_top_lut =
{
	["move"] =
	function(ctx)
		ctx.moving = true
	end,
	["maximize"] =
	function(ctx)
	end,
	["demaximize"] =
	function(ctx)
	end,
	["menu"] =
	function(ctx)
	end,
	["resize"] =
	function(ctx, source, dx, dy)
		if not dx or not dy then
			return
		end

		dx = tonumber(dx)
		dy = tonumber(dy)

		if not dx or not dy then
			return
		end

		ctx.resizing = {dx, dy}
	end,
-- practically speaking there is really only xdg now, though if someone
-- adds more, any wm specific mapping should be added here
	["shell"] =
	function(ctx, shell_type)
	end,
	["scale"] =
	function(ctx, sf)
	end,
-- new window geometry
	["geom"] =
	function(ctx, x, y, w, h)
	end
}

local function on_x11(ctx, source, status)
-- most involved here as the meta-WM forwards a lot of information
	if status.kind == "message" then
		local opts = string.split(status.message, ':')
		if not opts or not opts[1] or not x11_lut[opts[1]] then
			return
		end
		return x11_lut[opts[1]](ctx, source, unpack(opts, 2))

	elseif status.kind == "registered" then
		ctx.guid = status.guid

	elseif status.kind == "viewport" then
-- special case as it refers to positioning

	elseif status.kind == "terminated" then
		ctx:destroy()
	end
end

local function wnd_input_table(wnd, iotbl)
	if not wnd.focused then
		return
	end

	target_input(wnd.vid, iotbl)
end

-- these just request the focus state to change, the wm has final say
local function wnd_mouse_over(wnd)
	if wnd.wm.cfg.mouse_focus and not wnd.focused then
		wnd.wm.focus(wnd)
	end
end

local function wnd_mouse_out(wnd)
	if wnd.wm.cfg.mouse_focus and wnd.focused then
		wnd.wm.focus()
	end
end

local function wnd_mouse_btn(wnd, vid, button, active, x, y)
	if not active then
		wnd.moving = false
		wnd.resizing = false
	end

	target_input(vid, {
		kind = "digital",
		mouse = true,
		devid = 0,
		subid = button,
		active = active,
	})
end

local function wnd_mouse_drag(wnd, vid, dx, dy)

-- also need to cover 'cursor-tagging' hint here for drag and drop

	if wnd.moving then
		if wnd.wm.move then
			local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy)
			wnd.x = x
			wnd.y = y
		else
			wnd.x = wnd.x + dx
			wnd.y = wnd.y + dy
		end

-- for x11 we also need to message the new position
		move_image(wnd.vid, wnd.x, wnd.y)
		return

	elseif wnd.resizing then
		if not wnd.in_resize then
			wnd.in_resize = {wnd.w, wnd.h}
		end

-- block unwanted directions
		local lx = wnd.resizing[1]
		local ly = wnd.resizing[2]

		if lx == 0 then
			dx = 0
		else
			dx = dx * lx
		end

		if wnd.resizing[2] == 0 then
			dy = 0
		else
			dy = dy * ly
		end

-- for left and top edges we also need to 'nudge' when the drag-rz
-- state gets committed

		wnd.in_resize[1] = wnd.in_resize[1] + dx
		wnd.in_resize[2] = wnd.in_resize[2] + dy

-- need to clamp to something
		if wnd.in_resize[1] < 32 then
			wnd.in_resize[1] = 32
		end

		if wnd.in_resize[2] < 32 then
			wnd.in_resize[2] = 32
		end

		target_displayhint(wnd.vid, wnd.in_resize[1], wnd.in_resize[2])

-- re-emit as button/click event
	else
	end
end

local function wnd_mouse_motion(wnd, vid, x, y, rx, ry)
	local tx = x - wnd.x
	local ty = y - wnd.y

	target_input(wnd.vid, {
		kind = "analog", mouse = true,
		devid = 0, subid = 0,
		samples = {tx, rx}
	})

	target_input(wnd.vid, {
		kind = "analog", mouse = true,
		devid = 0, subid = 1,
		samples = {ty, ry}
	})
end

local function wnd_hint_state(wnd)
	local mask = 0
	if not wnd.focused then
		mask = bit.bor(mask, TD_HINT_UNFOCUSED)
	end

	if not wnd.visible then
		mask = bit.bor(mask, TD_HINT_INVISIBLE)
	end
	return mask
end

local function wnd_unfocus(wnd)
	wnd.focused = false
	target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd))
	wnd.wm.custom_cursor = false
	mouse_switch_cursor("default")
end

local function wnd_focus(wnd)
	wnd.focused = true
	target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd))
	wnd.wm.custom_cursor = true
end

local function wnd_destroy(wnd)
	mouse_droplistener(wnd)
	wnd.wm.known_surfaces[wnd.cookie] = nil
end

local function wnd_maximize(wnd, w, h)
	if wnd.maximized then
		return
	end

	wnd.maximized = {wnd.w, wnd.h}
	target_displayhint(wnd, w, h, wnd_hint_state(wnd))
end

local function wnd_unmaximize(wnd)
	if not wnd.maximized then
		return
	end

	wnd.maximized = false
	target_displayhint(wnd, w, h, wnd_hint_state(wnd))
	wnd_hint_state(wnd)
end

local function tl_vtable(wm)
	return {
		name = "wl_toplevel",
		wm = wm,

-- states that need to be configurable from the WM and forwarded to the
-- client so that it can update decorations or modify its input response
		mapped = false,
		focused = false,
		fullscreen = false,
		maximized = false,
		visible = false,
		moving = false,
		resizing = false,

-- wm side calls these to acknowledge state changes
		focus = wnd_focus,
		unfocus = wnd_unfocus,
		maximize = wnd_maximize,
		unmaximize = wnd_unmaximize,

-- states that needs to be tracked for drag-resize/drag-move
		x = 0,
		y = 0,
		w = 0,
		h = 0,

-- keyboard input
		input_table = wnd_input_table,

-- touch-mouse input goes here
		over = wnd_mouse_over,
		out = wnd_mouse_out,
		drag = wnd_mouse_drag,
		drop = wnd_mouse_drop,
		button = wnd_mouse_btn,
		motion = wnd_mouse_motion,
		popup = wnd_mouse_popup,
		destroy = wnd_destroy,

		own =
		function(self, vid)
			return self.vid == vid
		end
	}
end

local function on_toplevel(wnd, source, status)
	if status.kind == "create" then
		local new = tl_vtable()
		new.wm = wnd

-- request dimensions from wm
		local vid, aid, cookie =
		accept_target(320, 200,
			function(...)
				return on_toplevel(new, ...)
			end
		)
		new.vid = vid
		new.cookie = cookie

-- tie to bridge as visibility / clipping anchor
		image_tracetag(vid, "wl_toplevel")
		new.vid = vid
		image_inherit_order(vid, true)
		link_image(vid, wnd.anchor)

-- register mouse handler
		mouse_addlistener(new, {"over", "out", "drag", "button", "motion", "drop"})

		return new, cookie

	elseif status.kind == "terminated" then
		wnd:destroy()

-- might need to add frame delivery notification so that we can track/clear
-- parts that have 'double buffered' state

	elseif status.kind == "resized" then
-- first time showing
		if not wnd.mapped then
			wnd.mapped = true
			show_image(wnd.vid)
			wnd.wm.mapped(wnd)
		end

-- special handling for drag-resize where we request a move
		if wnd.resizing and (wnd.resizing[1] < 0 or wnd.resizing[2] < 0) then
			local dw = wnd.w - status.width
			local dh = wnd.h - status.height
			local dx = 0
			local dy = 0
			if wnd.resizing[1] < 0 then
				dx = dw
			end
			if wnd.resizing[2] < 0 then
				dy = dh
			end

			if wnd.wm.move then
				local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy)
				wnd.x = x
				wnd.y = y
			else
				wnd.x = wnd.x + dx
				wnd.y = wnd.y + dy
			end
			move_image(wnd.vid, wnd.x, wnd.y)
		end

		resize_image(wnd.vid, status.width, status.height)

		wnd.w = status.width
		wnd.h = status.height

-- wl specific wm hacks
	elseif status.kind == "message" then
		local opts = string.split(status.message, ':')
		if not opts or not opts[1] then
			return
		end

		if
			opts[1] == "shell" and
			opts[2] == "xdg_top" and
			opts[3] and wl_top_lut[opts[3]] then
			wl_top_lut[opts[3]](wnd, source, unpack(opts, 4))
		end
	end
end

local function on_cursor(ctx, source, status)
	if status.kind == "create" then
		local cursor = accept_target(32, 32,
		function(...)
			return on_cursor(ctx, ...)
		end)

		ctx.cursor.vid = cursor
		ctx.dirty_cursor = true
		link_image(ctx.bridge, cursor)

	elseif status.kind == "resized" then
		ctx.cursor.width = status.width
		ctx.cursor.height = status.height
		resize_image(ctx.cursor.vid, status.width, status.height)

		if ctx.custom_cursor then
			mouse_custom_cursor(ctx.cursor)
		end

	elseif status.kind == "message" then
-- hot-spot modification?
		if ctx.custom_cursor then
			mouse_custom_cursor(ctx.cursor)
		end
	end
end

local function bridge_handler(ctx, source, status)
	if status.kind == "terminated" then
		ctx:destroy()
		return

-- real typemap:
--
-- cursor         : shared cursor map, nothing special
--                  takes message(x,y) for hotspot
--
-- application    : wayland toplevel
-- popup          : can attach to toplevels or other popups, complex positioning
-- multimedia     : subsurface, 'stitch' easiest as a rendertarget
-- bridge-x11     : unknown x11 surface, will hint what it is later
--
-- states :
--  'in drag handler'
--
	elseif status.kind ~= "segment_request" then
		return
	end

	local permitted = {
		cursor = on_cursor,
		application = on_toplevel,
		popup = on_popup,
		multimedia = on_subsurface
	}

	local handler = permitted[status.segkind]
	if not handler then
		warning("unhandled segment type: " .. status.segkind)
		return
	end

-- actual allocation is deferred to the specific handler, some might need to
-- call back into the outer WM to get suggested default size/position - x11
-- clients need world-space coordinates and so on
	local wnd, cookie = handler(ctx, source, {kind = "create"})
	if wnd then
		ctx.known_surfaces[cookie] = wnd
	end
end

local function set_rate(ctx, period, delay)
	message_target(ctx.bridge,
		string.format("seat:rate:%d,%d", period, delay))
end

-- first wayland node, limited handler that can only absorb meta info,
-- act as clipboard and allocation proxy
local function set_bridge(ctx, source)
	local w = ctx.cfg.width and ctx.cfg.width or VRESW
	local h = ctx.cfg.width and ctx.cfg.width or VRESH

-- dtbl can be either a compliant monitor table or a render-target
	local dtbl = ctx.cfg.display and ctx.cfg.display or WORLDID
	target_displayhint(source, w, h, 0, dtbl)

-- wl_drm need to be able to authenticate against the GPU, which may
-- have security implications for some people - low risk enough for
-- opt-out rather than in
	if not ctx.cfg.block_gpu then
		target_flags(source, TARGET_ALLOWGPU)
	end

	target_updatehandler(source,
		function(...)
			return bridge_handler(ctx, ...)
		end
	)

	ctx.bridge = source
	ctx.anchor = null_surface(w, h)
	image_mask_set(ctx.anchor, MASK_UNPICKABLE)
	show_image(ctx.anchor)

--	ctx:repeat_rate(ctx.cfg.repeat, ctx.cfg.delay)
end

local function bridge_table(cfg)
	local res = {
		windows = {},
		known_surfaces = {},
		cursor = {
			vid = BADID,
			hotspot_x = 0,
			hotspot_y = 0,
			width = 1,
			height = 1
		},
		control = BADID,
		cfg = cfg,
		repeat_rate = set_rate
	}

	if not cfg.focus then
		warning("wlwm - no focus handler provided in cfg")
		res.focus =
		function()
			return false
		end
	else
		res.focus = cfg.focus
	end

	res.destroy =
	function()
		local rmlist = {}

-- convert to in-order and destroy all windows first
		for k,v in pairs(res.known_surfaces) do
			table.insert(rmlist, v)
		end
		for i,v in ipairs(rmlist) do
			if v.destroy then
				v:destroy()
				if cfg.destroy then
					cfg.destroy(v)
				end
			end
		end

		if cfg.destroy then
			cfg.destroy()
		end
		if valid_vid(res.bridge) then
			delete_image(res.bridge)
		end
		if valid_vid(res.anchor) then
			delete_image(res.anchor)
		end
		local keys = {}
		for k,v in pairs(res) do
			table.insert(keys, v)
		end
		for _,k in ipairs(keys) do
			res[k] = nil
		end
	end

	if not cfg.mapped then
		warning("wlwm - no mapped handler provided in cfg")
		res.mapped =
		function()
		end
	else
		res.mapped = cfg.mapped
	end

	return res
end

-- factory function is intended to be used when a bridge-wayland segment
-- requests something that is not a bridge-wayland, then the bridge (ref
-- by [vid]) will have its handler overridden and treated as a client.
return
function(vid, segreq, cfg)
	local ctx = bridge_table(cfg)
	set_bridge(ctx, vid)
	bridge_handler(ctx, vid, segreq)
	return ctx
end
