--
-- this should mostly look like a simplified version of tests/interactive/wltest
--

local tbar_sz = 12
local focus_color = {127, 127, 127, 255}
local unfocus_color = {64, 64, 64, 255}

local decor_config = {
	border = {2, 2, 2, 2},
	pad    = {tbar_sz, 0, 0, 0},
}

local size_top = decor_config.border[1] + decor_config.pad[1]

local decorator = system_load("builtin/decorator.lua")()(decor_config)

function decor_config.select(decor, active, source)
	if active then
		decor.self.wm.focus(decor.self)
	end
end

function decor_config.drag_rz(decor, cont, dx, dy, mx, my)
	if not cont then
		decor.self:drag_resize()
	else
		decor.self:drag_resize(dx, dy, -mx, -my)
	end
end

local function focus(ws, wnd)
	if ws.focus then
		if ws.focus.decorator then
			local decor = ws.focus.decorator

			decor:border_color(unpack(unfocus_color))
			image_color(decor.titlebar, unpack(unfocus_color))
		end
		ws.focus:unfocus()
	end

	ws.focus = wnd
	if not wnd then
		return
	end

	wnd:focus()
	if wnd.decorator then
		wnd.decorator:border_color(unpack(focus_color))
		image_color(wnd.decorator.titlebar, unpack(focus_color))
	end
end

local function destroy(ws, wnd)
	if ws.focus == wnd then
		ws.focus = nil
	end

-- destroying the bridge itself?
	if not wnd.wm then
		delete_workspace(ws.workspace_index)
	end
end

local function mapped(ws, wnd)
	if not focus then
		wnd.wm.focus(wnd)
	end
end

local function state_change(ws, wnd, state)
	if not state then
		wnd:revert()
	end

-- the rest are only allowed if we have focus
	if wnd ~= ws.focus then
		return
	end

	if state == "maximize" then
		wnd:maximize()

	elseif state == "fullscreen" then
		wnd:fullscreen()
	end
end

local function move(ws, wnd, x, y, dx, dy)
-- make sure decorated windows don't spawn or drag outside
	if wnd.decorator then
		if y < size_top then
			y = size_top
		end
	end

	return x, y
end

local function decorate(ws, wnd, vid, w, h, anim_dt, anim_interp)
	if not wnd.decorator then
		local msg
		wnd.decorator, msg = decorator(vid)
		if not wnd.decorator then
			return
		end

		wnd.decorator.self = wnd
		wnd.decorator:border_color(32, 255, 32, 1)

-- add our own titlebar to the pad area
		local tb = color_surface(32, 32, 64, 127, 32)
		link_image(tb, wnd.decorator.vids.l, ANCHOR_UR)
		image_inherit_order(tb, true)
		order_image(tb, 1)
		show_image(tb)
		wnd.decorator.titlebar = tb
		local mh = {
			name = "tbar_mh",
			own = function(ctx, vid) return vid == tb; end,
			drag =
			function(ctx, vid, dx, dy)
				wnd:nudge(dx, dy)
			end
		}
		table.insert(wnd.decorator.mhs, mh)
		mouse_addlistener(mh, {"drag"})
	end

	wnd.decorator:update(w, h, anim_dt, anim_interp)
	resize_image(wnd.decorator.titlebar, w, decor_config.pad[1])

	return
		decor_config.pad[1] + decor_config.border[1],
		decor_config.pad[2] + decor_config.border[2],
		decor_config.pad[3] + decor_config.border[3],
		decor_config.pad[4] + decor_config.border[4]
end

local function configure(ws, wnd, typestr)
-- we don't know if the client will want decorations or not so add some safety
	if typestr == "toplevel" then
		return
			VRESW - decor_config.border[2] - decor_config.border[4],
			VRESH - tbar_sz - decor_config.border[3], 10, 10
	end
end

local function wrap(ws, func)
	return function(...)
		return func(ws, ...)
	end
end

local function input_table(ws, table)
	if not ws.focus then
		return
	end

	ws.focus:input_table(table)
end

return
function(ws)
	ws.input = input_table
	local cfg = {
	focus = wrap(ws, focus),
	destroy = wrap(ws, destroy),
	mapped = wrap(ws, mapped),
	state_change = wrap(ws, state_change),
	move = wrap(ws, move),
	configure = wrap(ws, configure),
	decorate = wrap(ws, decorate),
	mouse_focus = true,
	}
	if DEBUGLEVEL < 1 then
		cfg.log = function()
		end
		cfg.fmt = function()
		end
	end

	return cfg
end
