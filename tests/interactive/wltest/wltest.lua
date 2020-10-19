local symtbl             -- keyboard layout table
local cli_shell          -- reference to command-line shell to launch wayland clients from
local clients = {}       -- count number of live clients, shutdown on 0
local focus              -- current wayland input focus window
local wl_config = {      -- configuration / event mapping for each wayland client
	log = print
}
local add_client         -- function for taking a fsrv-vid + event-table and adding as a window
local decorator          -- function to add window decorations, we add our own titlebar
local decor_config = {
	border = {2, 2, 2, 2},
	pad    = {12,0, 0, 0},
}
local rendertarget       -- If set, an off-screen composition buffer will be used for all
                         -- clients tied to a bridge.  For the sake of testing, this will
												 -- be animated and is triggered by providing a 'rendertarget' arg
												 -- on the command line

-- wl_config.mouse_focus = true

function wltest(args)
-- need mouse and keyboard
	symtbl = system_load("builtin/keyboard.lua")()
	system_load("builtin/mouse.lua")()

-- load placeholder mouse cursors for border actions
	local cursor = fill_surface(8, 8, 0, 255, 0)
	mouse_setup(cursor, 65535, 1, true, false)
	mouse_add_cursor("rz_diag_l", fill_surface(8, 8, 255, 0, 0), 0, 0)
	mouse_add_cursor("rz_diag_r", fill_surface(8, 8, 255, 0, 0), 0, 0)
	mouse_add_cursor("rz_left", fill_surface(8, 8, 255, 0, 0), 0, 0)
	mouse_add_cursor("rz_right", fill_surface(8, 8, 255, 0, 0), 0, 0)
	mouse_add_cursor("rz_up", fill_surface(8, 8, 255, 0, 0), 0, 0)
	mouse_add_cursor("rz_down", fill_surface(8, 8, 255, 0, 0), 0, 0)

-- extend string. and table. with some helpers
	system_load("builtin/string.lua")()
	system_load("builtin/table.lua")()
	local factory, connection = system_load("builtin/wayland.lua")()

-- we need window decorations for x11 clients
	decorator = system_load("builtin/decorator.lua")()(decor_config)

	add_client =
	function(source, status)
		local cl = factory(source, status, wl_config)
		if cl then
			table.insert(clients, cl)
		end
		if rendertarget then
			print("set rendertarget to", rendertarget, source, cl.vid)
			cl:set_rt(rendertarget)
		end
	end

-- setup an external connection point for attaching clients as well, helps
-- debugging to be able to run ARCAN_CONNPATH=wltest arcan-wayland -exec...
	local listen
	listen = function()
		target_alloc("wltest",
			function(source, status)
				if status.kind == "connected" then
					listen()
				elseif status.kind == "terminated" then
					delete_image(source)
					listen()
				else
					connection(source, add_client)
				end
			end
		)
	end
	listen()

-- spawn the CLI in WL mode so that the next command would map into the wlwm
-- if we have the argument on the command-line, just forward that, otherwise
-- route input
	cli_shell = launch_avfeed("cli:mode=wayland:exec=/usr/bin/weston-terminal", "terminal",
	function(source, status)
		if status.kind == "segment_request" then

-- this will become the wayland bridge through wayland clients come running,
-- the handler will be updated through the connection function.
			if status.segkind == "handover" then
				local res = accept_target(32, 32, function() end)
				connection(res, add_client)
			end

		elseif status.kind == "preroll" then
			target_displayhint(source, VRESW, VRESH)

		elseif status.kind == "resized" then
			resize_image(source, status.width, status.height)
			show_image(source)

		elseif status.kind == "terminated" then
			delete_image(source)
			cli_shell = nil
			ccount = ccount - 1
			if ccount == 0 then
				return shutdown(EXIT_SUCCESS)
			end
		end
	end)

	if args[1] == "rendertarget" then
		print("enabling rendertarget indirection")
		rendertarget = alloc_surface(VRESW, VRESH)
		define_rendertarget(rendertarget, {})
		mouse_querytarget(rendertarget)
		show_image(rendertarget)
		move_image(rendertarget, 100, 100, 1000)
		move_image(rendertarget, 0, 0, 1000)
		image_transform_cycle(rendertarget, true)
	end
end

function wl_config.focus(wnd)
	if focus == wnd then
		return
	end

	if focus then
		focus:unfocus()
		focus = nil
	end

	if not wnd then
		return
	end

	focus = wnd
	order_image(wnd.vid, max_current_image_order() + 1)
	wnd:focus()
end

function decor_config.select(decor, active, source)
	if active then
		wl_config.focus(decor.self)
	end
	mouse_switch_cursor(source)
end

function decor_config.drag_rz(decor, cont, dx, dy, mx, my)
	if not cont then
		decor.self:drag_resize()
	else
		decor.self:drag_resize(dx, dy, -mx, -my)
	end
end

function wl_config.mapped(wnd)
	if not focus then
		wnd.wm.focus(wnd)
	end
end

function wl_config.destroy(wnd)
	table.remove_match(clients, wnd)
	if wnd.decorator then
		wnd.decorator:destroy()
	end

	if wnd == focus then
		focus = nil
	end
end

-- request move, constrain to fit within screen
function wl_config.move(wnd, x, y)
	local min_x = 0
	local min_y = 0

	if wnd.decorator then
		min_x = decor_config.border[2] + decor_config.pad[2]
		min_y = decor_config.border[1] + decor_config.pad[1]
	end

	if x < min_x then
		x = min_x
	end

	if y < min_y then
		y = min_y
	end

	if x + wnd.w > VRESW then
		x = VRESW - wnd.w
	end

	if y + wnd.h > VRESH then
		y = VRESH - wnd.h
	end

	return x, y
end

-- "maximize", "fullscreen", not set == default
function wl_config.state_change(wnd, state)
	if not state then
		wnd:revert()
	end

-- the rest are only allowed if we have focus
	if wnd ~= focus then
		return
	end

	if state == "maximize" then
		wnd:maximize()
	elseif state == "fullscreen" then
		wnd:fullscreen()
	end
end

-- switch between composited rendertarget and fullscreen client vid
function wl_config.output(vid)
end

-- some windows want server side decorations
function wl_config.decorate(wnd, vid, w, h, anim_dt, anim_interp)
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

		if rendertarget then
			wnd.decorator:switch_rt(rendertarget)
			rendertarget_attach(rendertarget, tb, RENDERTARGET_DETACH)
		end

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

-- what size should the newly created window have
function wl_config.configure(wnd, typestr)
	return 300, 300, 10, 10
end

-- to the wm that currently has focus
function wltest_input(iotbl)
	if iotbl.mouse or iotbl.touch then
		mouse_iotbl_input(iotbl)
		return
	end

-- apply keymap
	if iotbl.translated then
		symtbl:patch(iotbl)
	end

-- rest forward to the focused window
	if not focus then
		if cli_shell then
			target_input(cli_shell, iotbl)
		end
		return
	end

	focus:input_table(iotbl)
end

function wltest_display_state(source)
-- if the output resizes all clients should know that
	if source ~= "reset" then
		return
	end

	print("display reset", VRESW, VRESH, #clients)
	mouse_querytarget(rendertarget)
	for _,v in ipairs(clients) do
		v:resize(VRESW, VRESH)
	end

	if valid_vid(rendertarget) then
		image_resize_storage(rendertarget, VRESW, VRESH)
	end
end
