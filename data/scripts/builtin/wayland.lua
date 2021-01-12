--
-- pseudo-window manager helper script for working with wayland and
-- x-wayland clients specifically.
--
-- Returns a factory function for taking a wayland-bridge carrying a
-- single client and constructing a wm/state tracker - as well as an
-- optional connection manager that takes any primary connection that
-- identifies as 'bridge-wayland' and deals with both 1:1 and 1:*
-- cases.
--
-- local factory, connection = system_load("builtin/wayland.lua")()
-- factory(vid, segreq_table, config)
--
-- (manual mode from a handler to an established bridge-wayland):
--     if status.kind == "segment-request" then
--          wm = factory(vid, status, config)
--     end
--
-- (connection mode):
-- 	local vid = target_alloc("wayland_only", function() end)
--
-- 	connection(vid,
-- 	function(source, status)
--  	wm = factory(source, status, config)
-- 	end)
--
--  a full example can be found in tests/interactive/wltest
--
-- config contains display options and possible wm event hooks for
-- latching into an outer wm scheme.
--
-- possible methods in config table:
--
--  decorate(window, vid, width, height) => t, l, d, r:
--      attach / set decorations using vid as anchor and width/height.
--      called whenever decoration state/sizes change. If 'vid' is not
--      provided, it means existing decorations should be destroyed.
--
--      the decorator should return the number of pixels added in each
--      direction for maximize/fullscreen calculations to be correct.
--
--  destroy(window):
--      called when a window has been destroyed, just before video
--      resources are deleted.
--
--  focus(window) or focus():
--      called when a window requests focus, to acknowledge, call
--      wnd:focus() and wnd:unfocus() respectively.
--
--  move(window, x, y, dx, dy):
--      called when a window requests to be moved to x, y, return
--      x, y if permitted - or constrain coordinates and return new
--      position
--
--  configure(window, [type]):
--      request for an initial size for a toplevel window (if any)
--      should return w, h, x, y
--
--  state_change(window, state={
--      "fullscreen", "realized", "composed",
--      "maximized", "visible", "focused", "toplevel"}
--      , [popup|parent], [grab])
--
--  mapped(window):
--      called when a new toplevel window is ready to be drawn
--
--  log : function(domain, message) (default: print)
--  fmt : function(string, va_args) (default: string.format)
--
--  the 'window' table passed as arguments provides the following methods:
--
--     focus(self):
--         acknowledge a focus request, raise and change pending visuals
--
--     unfocus(self):
--         mark the window has having lost focus
--
--     maximize(self):
--         acknowledge a maximization request
--
--     minimize(self):
--         acknowledge a minimization request
--
--     fullscreen(self):
--         acknowledge a fullscreen request or force fullscreen
--
--     destroy(self):
--         kill window and associated resources
--
--  the 'window' table passed as arguments provides the following properties:
--      mouse_proxy (vid) set if another object should be used to determine ownership
--
-- the returned 'wm' table exposes the following methods:
--
--  destroy():
--      drop all resources tied to this client
--
--  resize(width, height, density):
--      change the 'output' for this client, roughly equivalent to outmost
--      window resizing, changing display or display resolution - density
--      in ppcm.
--

-- for drag and drop purposes, we need to track all bridges so that we can
-- react on 'drag' and then check underlying vid when cursor-tagged in drag state,
-- and then test and forward to clients beneath it
local bridges = {}

local x11_lut =
{
	["type"] =
	function(ctx, source, typename)
		ctx.states.typed = typename
		if not ctx.states.mapped then
			ctx:apply_type()
		end
	end,
	["pair"] =
	function(ctx, source, wl_id, x11_id)
		local wl_id = wl_id and wl_id or "missing"
		local x11_id = x11_id and x11_id or "missing"

		ctx.idstr = wl_id .. "-> " .. x11_id
		ctx.wm.log("wl_x11", ctx.wm.fmt("paired:wl=%s:x11=%s", wl_id, x11_id))
-- not much to do with the information
	end,
	["fullscreen"] =
	function(ctx, source, on)
		ctx.wm.state_change(ctx, "fullscreen")
	end,
}

-- this table contains hacks around some bits in wayland that does not map to
-- regular events in shmif and comes packed in 'message' events
local wl_top_lut =
{
	["move"] =
	function(ctx)
		ctx.states.moving = true
	end,
	["maximize"] =
	function(ctx)
		ctx.wm.state_change(ctx, "maximize")
	end,
	["demaximize"] =
	function(ctx)
		ctx.wm.state_change(ctx, "demaximize")
	end,
	["menu"] =
	function(ctx)
		ctx.wm.context_menu(ctx)
	end,
	["fullscreen"] =
	function(ctx, source, on)
		ctx.wm.state_change(ctx, "fullscreen")
	end,
	["resize"] =
	function(ctx, source, dx, dy)
		if not dx or not dy then
			return
		end

		dx = tonumber(dx)
		dy = tonumber(dy)

		if not dx or not dy then
			ctx.states.resizing = false
			return
		end

-- masks for moving, used on left,top
		local mx = 0
		local my = 0
		if dx < 0 then
			mx = 1
		end
		if dy < 0 then
			my = 1
		end

		ctx.states.resizing = {dx, dy, mx, my}
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
		ctx.wm.log("toplevel", ctx.wm.fmt("anchor_geom:x=%f:y=%f:w=%f:h=%f", x, y, w, h))
		ctx.anchor_offset = {x, y}
	end
}

local function wnd_input_table(wnd, iotbl)
	if not wnd.states.focused then
		return
	end

	target_input(wnd.vid, iotbl)
end

-- these just request the focus state to change, the wm has final say
local function wnd_mouse_over(wnd)
	if wnd.wm.cfg.mouse_focus and not wnd.states.focused then
		wnd.wm.focus(wnd)
	end
end

-- this is not sufficient when we have a popup grab surface as 'out'
-- may mean in on the popup
local function wnd_mouse_out(wnd)
	if wnd.wm.cfg.mouse_focus and wnd.states.focused then
		wnd.wm.focus()
	end
end

local function wnd_mouse_btn(wnd, vid, button, active, x, y)
	if not active then
		wnd.states.moving = false
		wnd.states.resizing = false

	elseif not wnd.states.focused then
		wnd.wm.focus(wnd)
	end

-- catch any popups, this will cause spurious 'release' events in
-- clients if the button mask isn't accounted for
	if wnd.dismiss_chain then
		if active then
			wnd.block_release = button
			wnd:dismiss_chain()
		end
		return
	end

-- block until focus is ack:ed
	if not wnd.states.focused then
		return
	end

	if wnd.block_release == button and not active then
		wnd.block_release = nil
		return
	end

	target_input(wnd.vid, {
		kind = "digital",
		mouse = true,
		devid = 0,
		subid = button,
		active = active,
	})
end

local function wnd_mouse_drop(wnd)
	wnd:drag_resize()
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

local function wnd_mouse_drag(wnd, vid, dx, dy)
-- also need to cover 'cursor-tagging' hint here for drag and drop

	if wnd.states.moving then
		local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy)
		wnd.x = x
		wnd.y = y

-- for x11 we also need to message the new position
		if wnd.send_position then
			local msg = string.format("kind=move:x=%d:y=%d", wnd.x, wnd.y);
			wnd.wm.log("wl_x11", msg)
			target_input(vid, msg)
		end

		move_image(wnd.vid, wnd.x, wnd.y)
		return

--w when this is set, the resizing[] mask is also set
	elseif wnd.states.resizing then
		wnd:drag_resize(dx, dy)

-- need to clamp to something
		if wnd.in_resize[1] < 32 then
			wnd.in_resize[1] = 32
		end

		if wnd.in_resize[2] < 32 then
			wnd.in_resize[2] = 32
		end

		target_displayhint(wnd.vid, wnd.in_resize[1], wnd.in_resize[2])

-- re-emit as motion
	else
		local mx, my = mouse_xy()
		wnd_mouse_motion(wnd, vid, mx, my)
	end
end

local function wnd_hint_state(wnd)
	local mask = 0
	if not wnd.states.focused then
		mask = bit.bor(mask, TD_HINT_UNFOCUSED)
	end

	if not wnd.states.visible then
		mask = bit.bor(mask, TD_HINT_INVISIBLE)
	end

	if wnd.states.maximized then
		mask = bit.bor(mask, TD_HINT_MAXIMIZED)
	end

	if wnd.states.fullscreen then
		mask = bit.bor(mask, TD_HINT_FULLSCREEN)
	end

	return mask
end

local function wnd_unfocus(wnd)
	wnd.wm.log(wnd.name, wnd.wm.fmt("focus=off:idstr=%s", wnd.idstr and wnd.idstr or wnd.name))
	wnd.states.focused = false
	target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd))
	wnd.wm.custom_cursor = false
	mouse_switch_cursor("default")
end

local function wnd_focus(wnd)
	wnd.wm.log(wnd.name, wnd.wm.fmt("focus=on:idstr=%s", wnd.idstr and wnd.idstr or wnd.name))
	wnd.states.focused = true
	target_displayhint(wnd.vid, 0, 0, wnd_hint_state(wnd))
	wnd.wm.custom_cursor = wnd
	table.remove_match(wnd.wm.window_stack, wnd)
	table.insert(wnd.wm.window_stack, wnd)
	wnd.wm:restack()
end

local function wnd_destroy(wnd)
	wnd.wm.log(wnd.name, "destroy")
	mouse_droplistener(wnd)
	wnd.wm.windows[wnd.cookie] = nil
	table.remove_match(wnd.wm.window_stack, wnd)
	wnd.wm:restack()

	if wnd.wm.custom_cursor == wnd then
		mouse_switch_cursor("default")
	end
	if wnd.wm.cfg.destroy then
		wnd.wm.cfg.destroy(wnd)
	end
	if valid_vid(wnd.vid) then
		wnd.wm.known_surfaces[wnd.vid] = nil
		delete_image(wnd.vid)
	end
end

local function wnd_fullscreen(wnd)
	if wnd.states.fullscreen then
		return
	end

	wnd.states.fullscreen = {wnd.w, wnd.h, wnd.x, wnd.y}
	wnd.defer_move = {0, 0}
	target_displayhint(wnd.vid,
		wnd.wm.disptbl.width, wnd.wm.disptbl.height, wnd_hint_state(wnd))
end

local function wnd_maximize(wnd)
	if wnd.states.maximized then
		return
	end

-- drop fullscreen if we have it, but block hint
	if wnd.states.fullscreen then
		wnd:revert({no_hint = true})
	end

	wnd.states.maximized = {wnd.w, wnd.h, wnd.x, wnd.y}
	wnd.defer_move = {0, 0}

	target_displayhint(wnd.vid,
		wnd.wm.disptbl.width, wnd.wm.disptbl.height, wnd_hint_state(wnd))
end

local function wnd_revert(wnd, opts)
	local tbl

-- drop fullscreen to maximized or 'normal' (the attributes stack)
	if wnd.states.fullscreen then
		tbl = wnd.states.fullscreen
		wnd.states.fullscreen = false

	elseif wnd.states.maximized then
		tbl = wnd.states.maximized
		wnd.states.maximized = false
	else
		return
	end

-- the better way of doing this is probably to enable detailed frame
-- reporting for the surface, and have a state hook after this request
-- an edge case is where the maximized dimensions correspond to the
-- unmaximized ones which may be possible if there are no server-side
-- decorations.
	if not opts or not opts.no_hint then
		target_displayhint(wnd.vid, tbl[1], tbl[2], wnd_hint_state(wnd))
		wnd.defer_move = {tbl[3], tbl[4]}
	end

	wnd_hint_state(wnd)
end

local function tl_wnd_resized(wnd, source, status)
	if not wnd.states.mapped then
		wnd.states.mapped = true
		show_image(wnd.vid)
		wnd.wm.mapped(wnd)
	end

-- special handling for drag-resize where we request a move
	local rzmask = wnd.states.resizing
	if rzmask then
		local dw = (wnd.w - status.width)
		local dh = (wnd.h - status.height)
		local dx = dw * rzmask[3]
		local dy = dh * rzmask[4]

-- the move handler should account for padding
		local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy)
		wnd.x = x
		wnd.y = y
		move_image(wnd.vid, wnd.x, wnd.y)
		wnd.defer_move = nil
	end

-- special case for state changes (maximized / fullscreen)
	wnd.w = status.width
	wnd.h = status.height
	resize_image(wnd.vid, status.width, status.height)

	if wnd.use_decor then
		wnd.wm.decorate(wnd, wnd.vid, wnd.w, wnd.h)
	end

	if wnd.defer_move then
		local x, y = wnd.wm.move(wnd, wnd.defer_move[1], wnd.defer_move[2])
		move_image(wnd.vid, x, y)
		wnd.x = x
		wnd.y = y
		wnd.defer_move = nil
	end
end

local function self_own(self, vid)
-- if we are matching or a grab exists and we hold the grab or there is some proxy
	return self.vid == vid or (self.mouse_proxy and vid == self.mouse_proxy)
end

local function x11_wnd_realize(wnd, popup, grab)
	if wnd.realized then
		return
	end

	if not wnd.states.mapped or not wnd.states.typed then
		hide_image(wnd.vid)
		return
	end

	show_image(wnd.vid)
	target_displayhint(wnd.vid, wnd.w, wnd.h)
	mouse_addlistener(wnd, {"motion", "drag", "drop", "button", "over", "out"})
	table.insert(wnd.wm.window_stack, 1, wnd)

	wnd.wm.state_change(wnd, "realized", popup, grab)
	wnd.realized = true
end

local function x11_wnd_type(wnd)
	local popup_type =
		wnd.states.typed == "menu"
		or wnd.states.typed == "popup"
		or wnd.states.typed == "tooltip"
		or wnd.states.typed == "dropdown"

-- icccm says about stacking order:
-- wm_type_desktop < state_below < (no type) < dock | state_above < fullscreen
-- other options, dnd, splash, utility (persistent_for)

	if popup_type then
		wnd.use_decor = false
		wnd.wm.decorate(wnd)
		image_inherit_order(wnd.vid, false)
		order_image(wnd.vid, 65531)
	else
-- decorate should come from toplevel
		image_inherit_order(wnd.vid, true)
		wnd.use_decor = true
		order_image(wnd.vid, 1)
	end

	wnd:realize()
end

local function x11_nudge(wnd, dx, dy)
	local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy)
	move_image(wnd.vid, x, y)
	wnd.x = x
	wnd.y = y
	local msg = string.format("kind=move:x=%d:y=%d", x, y);

	wnd.wm.log("wl_x11", msg)
	target_input(wnd.vid, msg)
end

local function wnd_nudge(wnd, dx, dy)
	local x, y = wnd.wm.move(wnd, wnd.x + dx, wnd.y + dy, dx, dy)
	move_image(wnd.vid, x, y)
	wnd.x = x
	wnd.y = y
	wnd.wm.log("wnd", wnd.wm.fmt("source=%d:x=%d:y=%d", wnd.vid, x, y))
end

local function wnd_drag_rz(wnd, dx, dy, mx, my)
	if not dx then
		wnd.states.resizing = false
		wnd.in_resize = nil
		return
	end

	if not wnd.in_resize then
		wnd.in_resize = {wnd.w, wnd.h}
		if (mx and my) then
			wnd.states.resizing = {1, 1, mx, my}
		end
	end
-- apply direction mask, clamp against lower / upper constraints
	local tw = wnd.in_resize[1] + (dx * wnd.states.resizing[1])
	local th = wnd.in_resize[2] + (dy * wnd.states.resizing[2])

	if tw < wnd.min_w then
		tw = wnd.min_w
	end

	if th < wnd.min_h then
		th = wnd.min_h
	end

	if wnd.max_w > 0 and tw > wnd.max_w then
		tw = wnd.max_w
	end

	if wnd.max_h > 0 and tw > wnd.max_h then
		tw = wnd.max_h
	end

	wnd.in_resize = {tw, th}
	target_displayhint(wnd.vid, wnd.in_resize[1], wnd.in_resize[2])
	wnd.wm.log("wnd", wnd.wm.fmt("source=%d:drag_rz=%d:%d",
		wnd.vid, wnd.in_resize[1], wnd.in_resize[2]))
end

-- several special considerations with x11, particularly that some
-- things are positioned based on a global 'root' anchor, a rather
-- involved type model and a number of wm messages that we need to
-- respond to.
--
-- another is that we need to decorate window contents ourselves,
-- with all the jazz that entails.
local function x11_vtable()
	return {
		name = "x11_bridge",
		own = self_own,
		x = 0,
		y = 0,
		w = 32,
		h = 32,
		pad_x = 0,
		pad_y = 0,
		min_w = 32,
		min_h = 32,
		max_w = 0,
		max_h = 0,
		send_position = true,
		use_decor = true,

		states = {
			mapped = false,
			typed = false,
			fullscreen = false,
			maximized = false,
			visible = false,
			moving = false,
			resizing = false
		},

-- assumes a basic 'window' then we patch things around when we have
-- been assigned a type / mapped - default is similar to wayland toplevel
-- with added messaging about window coordinates within the space
		destroy = wnd_destroy,
		input_table = wnd_input_table,

		over = wnd_mouse_over,
		out = wnd_mouse_out,
		button = wnd_mouse_btn,
		drag = x11_mouse_drag,
		motion = wnd_mouse_motion,
		drop = wnd_mouse_drop,

		focus = wnd_focus,
		unfocus = wnd_unfocus,
		revert = wnd_revert,
		fullscreen = wnd_fullscreen,
		maximize = wnd_maximize,
		drag_resize = wnd_drag_rz,
		nudge = x11_nudge,
		apply_type = x11_wnd_type,
		realize = x11_wnd_realize
	}
end

local function wnd_dnd_source(wnd, x, y, types)
-- this needs the 'cursor-tag' attribute when we enter, then some
-- marking function to say if it is desired or not ..
end

local function wnd_copy_paste(wnd, src, dst)
	local nc = #src.states.copy_set
	if not dst.wm or not valid_vid(dst.wm.control) or nc == 0 then
		return
	end

	local control = dst.wm.control

-- send src to copy client, mark as 'latest' src, clamp number of offers
	target_input(control, "offer")
	local lim = nc < 32 and nc or 32
	for i=1,lim do
		target_input(control, v)
	end
	target_input(control, "/offer")

-- when the client has picked an offer, that will come back in the wm
-- handler on dst and initiate the paste operation then
	dst.wm.offer_src = src
end

local function tl_vtable(wm)
	return {
		name = "wl_toplevel",
		wm = wm,

-- states that need to be configurable from the WM and forwarded to the
-- client so that it can update decorations or modify its input response
		states = {
			mapped = false,
			focused = false,
			fullscreen = false,
			maximized = false,
			visible = false,
			moving = false,
			resizing = false,
			copy_set = {}
		},

-- wm side calls these to acknowledge or initiat estate changes
		focus = wnd_focus,
		unfocus = wnd_unfocus,
		maximize = wnd_maximize,
		fullscreen = wnd_fullscreen,
		revert = wnd_revert,
		nudge = wnd_nudge,
		drag_resize = wnd_drag_rz,
		dnd_source = wnd_dnd_source,
		copy_paste = wnd_paste_opts,

-- properties that needs to be tracked for drag-resize/drag-move
		x = 0,
		y = 0,
		w = 0,
		h = 0,
		min_w = 32,
		min_h = 32,
		max_w = 0,
		max_h = 0,

-- keyboard input
		input_table = wnd_input_table,

-- touch-mouse input goes here
		over = wnd_mouse_over,
		out = wnd_mouse_out,
		drag = wnd_mouse_drag,
		drop = wnd_mouse_drop,
		button = wnd_mouse_btn,
		motion = wnd_mouse_motion,
		destroy = wnd_destroy,
		own = self_own
	}
end

local function popup_click(popup, vid, x, y)
	local tbl =
	target_input(vid, {
		kind = "digital",
		mouse = true,
		devid = 0,
		subid = 1,
		active = true,
	})
	target_input(vid, {
		kind = "digital",
		mouse = true,
		devid = 0,
		subid = 1,
		active = false,
	})
end

-- put an invisible surface at the overlay level and add a mouse-handler that
-- calls a destroy function if clicked.
local function setup_grab_surface(popup)
	local vid = null_surface(popup.wm.disptbl.width, popup.wm.disptbl.height)
	rendertarget_attach(popup.wm.disptbl.rt, vid, RENDERTARGET_DETACH)

	show_image(vid)
	order_image(vid, 65530)
	image_tracetag(vid, "popup_grab")

	local done = false
	local tbl = {
		name = "popup_grab_mh",
		own = function(ctx, tgt)
			return vid == tgt
		end,
		button = function()
			if not done then
				done = true
				popup:destroy()
			end
		end
	}
	mouse_addlistener(tbl, {"button"})
	popup.wm.log("popup", popup.wm.fmt("grab_on"))

	return function()
		popup.wm.log("popup", popup.wm.fmt("grab_free"))
		mouse_droplistener(tbl)
		delete_image(vid)
		done = true
	end
end

local function popup_destroy(popup)
	if popup.grab then
		popup.grab = popup.grab()
	end

	mouse_switch_cursor("default")

-- might have chain-destroyed through the parent vid or terminated on its own
	if valid_vid(popup.vid) then
		delete_image(popup.vid)
		popup.wm.known_surfaces[popup.vid] = nil
	end

	mouse_droplistener(popup)
	popup.wm.windows[popup.cookie] = nil
end

local function popup_over(popup)
-- this might have changed with mouse_out
	if popup.wm.cursor then
		mouse_custom_cursor(popup.wm.cursor)
	else
		mouse_switch_cursor("default")
	end
end

local function popup_vtable()
	return {
		name = "popup_mh",
		own = self_own,
		motion = wnd_mouse_motion,
		click = popup_click,
		destroy = popup_destroy,
		over = popup_over,
		out = popup_out,
		states = {
		},
		x = 0,
		y = 0
	}
end

local function on_popup(popup, source, status)
	if status.kind == "create" then
		local wnd = popup

-- if we have a popup that has not been assigned to anything when we get
-- the next one already, not entirely 100% whether that is permitted, and
-- more importantly, actually used/sanctioned behaviour
		if wnd.pending_popup and valid_vid(wnd.pending_popup.vid) then
			wnd.pending_popup:destroy()
		end

		local popup = popup_vtable()
		local vid, aid, cookie =
		accept_target(
			function(...)
				return on_popup(popup, ...)
			end
		)
		image_tracetag(vid, "wl_popup")
		rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH)

		wnd.known_surfaces[vid] = true
		wnd.pending_popup = popup
		link_image(vid, wnd.anchor)
		popup.wm = wnd
		popup.cookie = cookie
		popup.vid = vid

-- also not entirely sure if popup-drag-n-drop behavior is a thing, so just
-- map clicks and motion for the time being
		mouse_addlistener(popup, {"motion", "click", "over", "out"})

	elseif status.kind == "terminated" then
		popup:destroy()

	elseif status.kind == "resized" then

-- wait with showing the popup until it is both viewported and mapped
		if not popup.states.mapped then
			popup.states.mapped = true
			if popup.got_parent then
				show_image(popup.vid)
			end
		end
		resize_image(popup.vid, status.width, status.height)

	elseif status.kind == "viewport" then
		local pwnd = popup.wm.windows[status.parent]
		if not pwnd then
			popup.wm.log("popup", popup.wm.fmt("bad_parent=%d", status.parent))
			popup.got_parent = false
			hide_image(popup.vid)
			return
		end

		pwnd.popup = popup
		popup.parent = pwnd
		popup.got_parent = true

-- more anchoring and positioning considerations here
		link_image(popup.vid, pwnd.vid)
		move_image(popup.vid, status.rel_x, status.rel_y)

-- 'popups' can be used for tooltips and so on as well, take that into account
-- as well as enable a 'grab' layer that lives with the focused popup
		if status.focus then
			order_image(popup.vid, 65531)
			if not popup.grab then
				popup.grab = setup_grab_surface(popup)
			end
			image_mask_clear(popup.vid, MASK_UNPICKABLE)
		else
-- release any existing grab
			if popup.grab then
				popup.grab = popup.grab()
			end
			order_image(popup.vid, 1)
			image_mask_set(popup.vid, MASK_UNPICKABLE)
		end

-- this needs to be synched if the window is moved through code/wm
		local props = image_surface_resolve(popup.vid)
		popup.x = props.x
		popup.y = props.y

-- possible animation hook
		if popup.states.mapped then
			show_image(popup.vid)
		end

		if popup.wm.pending_popup == popup then
			popup.wm.pending_popup = nil
		end
	end
end

local function on_toplevel(wnd, source, status)
	if status.kind == "create" then
		local new = tl_vtable()
		new.wm = wnd

-- request dimensions from wm
		local w, h, x, y = wnd.configure(new, "toplevel")
		local vid, aid, cookie =
		accept_target(w, h,
			function(...)
				return on_toplevel(new, ...)
			end
		)
		rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH)
		new.vid = vid
		new.cookie = cookie
		wnd.known_surfaces[vid] = true
		new.x = x
		new.y = y
		table.insert(wnd.window_stack, new)

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
		tl_wnd_resized(wnd, source, status)

-- viewport is used here to define another window as the current toplevel,
-- i.e. that should cause this window to hide or otherwise be masked, and
-- the parent set to order above it (until unset)
	elseif status.kind == "viewport" then
		local parent = wnd.wm.windows[status.parent]
		if parent then
			wnd.wm.log("wl_toplevel", wnd.wm.fmt("reparent=%d",status.parent))
			wnd.wm.state_change(wnd, "toplevel", parent)
		else
			wnd.wm.log("wl_toplevel", wnd.wm.fmt("viewport:unknown_parent:%d", status.parent))
		end

-- wl specific wm hacks
	elseif status.kind == "message" then
		wnd.wm.log("wl_toplevel", wnd.wm.fmt("message=%s", status.message))
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
		local cursor = accept_target(
		function(...)
			return on_cursor(ctx, ...)
		end)

		ctx.cursor.vid = cursor
		link_image(ctx.bridge, cursor)
		ctx.known_surfaces[cursor] = true
		image_tracetag(cursor, "wl_cursor")
		rendertarget_attach(ctx.disptbl.rt, cursor, RENDERTARGET_DETACH)

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

	elseif status.kind == "terminated" then
		delete_image(source)
		ctx.known_surfaces[source] = nil
	end
end

-- fixme: incomplete, input routing, attachments etc. needed
local function on_subsurface(ctx, source, status)
	if status.kind == "create" then
		local subwnd = {
			name = "tl_subsurface"
		}
		local vid, aid, cookie =
		accept_target(
			function(...)
				return on_subsurface(subwnd, ...)
			end
		)
		subwnd.vid = vid
		subwnd.wm = ctx
		subwnd.cookie = cookie
		ctx.wm.known_surfaces[vid] = true
		rendertarget_attach(ctx.wm.disptbl.rt, vid, RENDERTARGET_DETACH)
		image_tracetag(vid, "wl_subsurface")

-- subsurfaces need a parent to attach to and 'extend',
-- input should be translated into its coordinate space as well
		return subwnd, cookie
	elseif status.kind == "resized" then

	elseif status.kind == "viewport" then
		link_image(source, parent.vid)

	elseif status.kind == "terminated" then
		delete_image(source)
		ctx.wm.windows[ctx.cookie] = nil
		ctx.wm.known_surfaces[source] = nil
	end
end

local function x11_viewport(wnd, source, status)
	local anchor = wnd.wm.anchor
	if status.parent ~= 0 then
		local pwnd = wnd.wm.windows[status.parent]
		if pwnd then
			anchor = pwnd.vid
		end
	end

-- ignore repositioning hints while we are dragging
	if wnd.in_resize then
		return
	end

-- depending on type, we need to order around as well
	link_image(wnd.vid, anchor)
	move_image(wnd.vid, status.rel_x, status.rel_y)

	local props = image_surface_resolve(wnd.vid)
	local x, y = wnd.wm.move(wnd, props.x, props.y)
	wnd.x = x
	wnd.y = y

	wnd.wm.log("wl_x11", wnd.wm.fmt(
		"viewport:parent=%d:hx=%d:hy=%d:x=%d:y=%d",
		status.parent, status.rel_x, status.rel_y, x, y)
	)

-- we need something more here to protect against an infinite move-loop
--	target_input(wnd.vid, string.format("kind=move:x=%d:y=%d", x, y))
end

local function on_x11(wnd, source, status)
-- most involved here as the meta-WM forwards a lot of information
	if status.kind == "create" then
		local x11 = x11_vtable()
		x11.wm = wnd

		local w, h, x, y = wnd.configure(x11, "x11")

		local vid, aid, cookie =
		accept_target(w, h,
		function(...)
			return on_x11(x11, ...)
		end)
		rendertarget_attach(wnd.disptbl.rt, vid, RENDERTARGET_DETACH)

		x11.x = x
		x11.y = y
		move_image(vid, x, y)

		wnd.known_surfaces[vid] = true

-- send our preset position, might not matter if it is override-redirect
-- this was removed as it caused a race condition, 'create' doesn't mean that
-- the window is realized yet, so defer that until it happens
--
--		local msg = string.format("kind=move:x=%d:y=%d", x, y)
--		wnd.log("wl_x11", msg)
--		target_input(vid, msg)
--		show_image(vid)

		x11.vid = vid
		x11.cookie = cookie
		image_tracetag(vid, "x11_unknown_type")
		image_inherit_order(vid, true)
		link_image(vid, wnd.anchor)

		return x11, cookie

	elseif status.kind == "resized" then
		tl_wnd_resized(wnd, source, status)
		wnd:realize()

-- let the caller decide how we deal with decoration
		if wnd.realized and wnd.use_decor then
			local t, l, d, r = wnd.wm.decorate(wnd, wnd.vid, wnd.w, wnd.h)
			wnd.pad_x = t
			wnd.pad_y = l
		end

	elseif status.kind == "message" then
		local opts = string.split(status.message, ':')
		if not opts or not opts[1] or not x11_lut[opts[1]] then
			wnd.wm.log("wl_x11", wnd.wm.fmt("unhandled_message=%s", status.message))
			return
		end
		wnd.wm.log("wl_x11", wnd.wm.fmt("message=%s", status.message))
		return x11_lut[opts[1]](wnd, source, unpack(opts, 2))

	elseif status.kind == "registered" then
		wnd.guid = status.guid

	elseif status.kind == "viewport" then
		x11_viewport(wnd, source, status)

	elseif status.kind == "terminated" then
		wnd:destroy()
	end
end

local function bridge_handler(ctx, source, status)
	if status.kind == "terminated" then
		ctx:destroy()
		return

-- message on the bridge is also used to pass metadata about the 'data-device'
-- properties like selection changes and type
	elseif status.kind == "message" then
		local cmd, data = string.split_first(status.message, ":")
		ctx.log("bridge", ctx.fmt("message:kind=%s", cmd))
		if cmd == "offer" then
			if table.find_i(ctx.offer, data) then
				return
			end

-- normal 'behavior' here is that the data source provides a stream of types that
-- supposedly is mime, in reality is a mix of whatever, on 'paste' or drag-enter
-- you forward these to the destination, it says which one it is, then send
-- descriptors in both directions. Since the WM might want to do things with the
-- clipboard contents - notify here and provide the methods to forward / trigger
-- an offer.
			table.insert(ctx.offer, data)

		elseif cmd == "offer-reset" then
			ctx.offer = {}
		end

		return
	elseif status.kind ~= "segment_request" then
		return
	end

	local permitted = {
		cursor = on_cursor,
		application = on_toplevel,
		popup = on_popup,
		multimedia = on_subsurface, -- fixme: still missing
		["bridge-x11"] = on_x11
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
		ctx.windows[cookie] = wnd
	end
end

local function set_rate(ctx, period, delay)
	message_target(ctx.bridge,
		string.format("seat:rate:%d,%d", period, delay))
end

-- first wayland node, limited handler that can only absorb meta info,
-- act as clipboard and allocation proxy
local function set_bridge(ctx, source)
	local w = ctx.disptbl.width
	local h = ctx.disptbl.height

	target_displayhint(source, w, h, 0, ctx.disptbl)

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
	image_tracetag(ctx.anchor, "wl_bridge_anchor")
	image_mask_set(ctx.anchor, MASK_UNPICKABLE)

	show_image(ctx.anchor)
	ctx.mh = {
		name = "wl_bg",
		own = self_own,
		vid = ctx.anchor,
		click = function()
			ctx.focus()
		end,
	}
	mouse_addlistener(ctx.mh, {"click"})

--	ctx:repeat_rate(ctx.cfg.repeat, ctx.cfg.delay)
end

local function resize_output(ctx, neww, newh, density, refresh)
	if density then
		ctx.disptbl.vppcm = density
		ctx.disptbl.hppcm = density
	end

	if neww then
		ctx.disptbl.width = neww
	else
		neww = ctx.disptbl.width
	end

	if newh then
		ctx.disptbl.height = newh
	else
		newh = ctx.disptbl.height
	end

	if refresh then
		ctx.disptbl.refresh = refresh
	end

	if not valid_vid(ctx.bridge) then
		return
	end

	ctx.log("bridge", ctx.fmt("output_resize=%d:%d", ctx.disptbl.width, ctx.disptbl.height))
	target_displayhint(ctx.bridge, neww, newh, 0, ctx.disptbl)

-- tell all windows that some of their display parameters have changed,
-- if the window is in fullscreen/maximized state - the surface should
-- be resized as well
	for _, v in pairs(ctx.windows) do
-- this will fetch the refreshed display table
		if v.reconfigure then
			if v.states.fullscreen or v.states.maximized then
				v:reconfigure(neww, newh)
			else
				v:reconfigure(v.w, v.h)
			end
		end
	end
end

local function reparent_rt(ctx, rt)
	ctx.disptbl.rt = rt
	for k,v in pairs(ctx.known_surfaces) do
		rendertarget_attach(ctx.disptbl.rt, k, RENDERTARGET_DETACH)
	end
	if valid_vid(ctx.anchor) then
		rendertarget_attach(ctx.disptbl.rt, ctx.anchor, RENDERTARGET_DETACH)
	end
end

local window_stack = {}
local function restack(ctx)
	local cnt = 0
	for _, v in pairs(ctx.windows) do
		cnt = cnt + 1
	end
-- re-order
	for i,v in ipairs(ctx.window_stack) do
		order_image(v.vid, i * 10);
	end
end

local function bridge_table(cfg)
	local res = {
-- vid to the client bridge
		control = BADID,

-- The window stack is (default) global for all bridges for ordering to work,
-- each window is reserved 10 order slots.
		window_stack = window_stack,

-- key indexed on window identifier cookie
		windows = {},

-- tracks all externally allocated VIDs
		known_surfaces = {},

-- currently active cursor on seat
		cursor = {
			vid = BADID,
			hotspot_x = 0,
			hotspot_y = 0,
			width = 1,
			height = 1
		},

		offer = {
		},

-- user table of settings
		cfg = cfg,

-- last known 'output' properties (vppcm, refresh also possible)
		disptbl = {
			rt = WORLDID,
			width = VRESW,
			height = VRESH,
			ppcm = VPPCM
		},

-- call when output properties have changed
		resize = resize_output,

-- call to update keyboard state knowledge
		repeat_rate = set_rate,

-- called internally whenever the window stack has changed
		restack = restack,

-- call to switch attachment to a specific rendertarget
		set_rt = reparent_rt,

-- swap out for logging / tracing function
		log = print,
		fmt = string.format
	}

-- let client config override some defaults
	if cfg.width then
		res.disptbl.width = cfg.width
	end

	if cfg.height then
		res.disptbl.height = cfg.height
	end

	if cfg.fmt then
		res.fmt = cfg.fmt
	end

	if cfg.log then
		res.log = cfg.log
	end

	if type(cfg.window_stack) == "table" then
		res.window_stack = cfg.window_stack
	end

-- add client defined event handlers, provide default inplementations if missing
	if type(cfg.move) == "function" then
		res.log("wlwm", "override_handler=move")
		res.move = cfg.move
	else
		res.log("wlwm", "default_handler=move")
		res.move =
		function(wnd, x, y, dx, dy)
			return x, y
		end
	end

	if type(cfg.context_menu) == "function" then
		res.log("wlwm", "override_handler=context_menu")
		res.context_menu = cfg.context_menu
	else
		res.context_menu = function()
		end
	end

	res.configure =
	function(...)
		local w, h, x, y
		if cfg.configure then
			w, h, x, y = cfg.configure(...)
		end
		w = w and w or res.disptbl.width * 0.5
		h = h and h or res.disptbl.height * 0.3
		if not x or not y then
			x, y = mouse_xy()
		end
		return w, h, x, y
	end

	if type(cfg.focus) == "function" then
		res.log("wlwm", "override_handler=focus")
		res.focus = cfg.focus
	else
		res.log("wlwm", "default_handler=focus")
		res.focus =
		function()
			return true
		end
	end

	if type(cfg.decorate) == "function" then
		res.log("wlwm", "override_handler=decorate")
		res.decorate = cfg.decorate
	else
		res.log("wlwm", "default_handler=decorate")
		res.decorate =
		function()
		end
	end

	if type(cfg.mapped) == "function" then
		res.log("wlwm", "override_handler=mapped")
		res.mapped = cfg.mapped
	else
		res.log("wlwm", "default_handler=mapped")
		res.mapped =
		function()
		end
	end

	if type(cfg.state_change) == "function" then
		res.log("wlwm", "override_handler=state_change")
		res.state_change = cfg.state_change
	else
		res.state_change =
		function(wnd, state)
			if not state then
				wnd:revert()
			end

		end
	end

	if (cfg.resize_request) == "function" then
		res.log("wlwm", "override_handler=resize_request")
		res.resize_request = cfg.resize_request
	else
		res.log("wlwm", "default_handler=resize_request")
		res.resize_request =
		function(wnd, new_w, new_h)
			if new_w > ctx.disptbl.width then
				new_w = ctx.disptbl.width
			end

			if new_h > ctx.disptbl.height then
				new_h = ctx.disptbl.height
			end

			return new_w, new_h
		end
	end

-- destroy always has a builtin handler and then cfg is optionally pulled in
	res.destroy =
	function()
		local rmlist = {}

-- convert to in-order and destroy all windows first
		for k,v in pairs(res.windows) do
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
			cfg.destroy(res)
		end
		if valid_vid(res.bridge) then
			delete_image(res.bridge)
		end
		if valid_vid(res.anchor) then
			delete_image(res.anchor)
		end

		mouse_droplistener(res)
		local keys = {}
		for k,v in pairs(res) do
			table.insert(keys, v)
		end
		for _,k in ipairs(keys) do
			res[k] = nil
		end
	end

	return res
end

local function client_handler(nested, trigger, source, status)
-- keep track of anyone that goes through here
	if not bridges[source] then
		bridges[source] = {}
	end

	if status.kind == "registered" then
-- happens if we are forwarded from the wrong type (api error)
		if status.segkind ~= "bridge-wayland" then
			delete_image(source)
			return
		end

-- we have a wayland bridge, and need to know if it is used to bootstrap other
-- clients or not - we see that if it requests a non-bridge-wayland type on its
-- next segment request
	elseif status.kind == "segment_request" then

-- nested, only allow one 'level'
		if status.segkind == "bridge-wayland" then
			if nested then
				return false
			end

-- next one will be the one to ask for 'real' windows
		local vid =
		accept_target(32, 32,
			function(...)
				return client_handler(true, trigger, ...)
			end)

-- and those we just forward to the wayland factory
		else
			local bridge = trigger(source, status)
			if bridge then
				table.insert(bridges[source], bridge)
				rendertarget_attach(bridge.disptbl.rt, vid, RENDERTARGET_DETACH)
			end
		end

-- died before getting anywhere meaningful - or is the bridge itself gone?
-- if so, kill off every client associated with it
	elseif status.kind == "terminated" then
		for k,v in ipairs(bridges[source]) do
			v:destroy()
		end
		delete_image(source)
		bridges[source] = nil
	end
end

local function connection_mgmt(source, trigger)
	target_updatehandler(source,
		function(source, status)
			client_handler(false, trigger, source, status)
		end
	)
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
end, connection_mgmt
