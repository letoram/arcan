local symtbl     -- keyboard layout table
local cli_shell  -- reference to command-line shell to launch wayland clients from
local wlfact     -- factory function for building a meta-wm around a wayland client
local ccount = 1 -- count number of live clients, shutdown on 0
local focus      -- current wayland input focus window

function wltest()
-- need mouse and keyboard
	symtbl = system_load("builtin/keyboard.lua")()
	system_load("builtin/mouse.lua")()
	local cursor = fill_surface(8, 8, 0, 255, 0)
	mouse_setup(cursor, 65535, 1, true, false)

-- extend string. and table. with some helpers
	system_load("builtin/string.lua")()
	system_load("builtin/table.lua")()

-- used once per client, takes a client-bound allocation bridge
	wlfact = system_load("builtin/wayland.lua")()

-- spawn the CLI in WL mode so that the next command would map into the wlwm
-- if we have the argument on the command-line, just forward that, otherwise
-- route input
	cli_shell = launch_avfeed("cli:mode=wayland", "terminal",
	function(source, status)
		if status.kind == "segment_request" then

-- this will become the 'bridge' that a client will allocate its resources on
			if status.segkind == "handover" then
				local res = accept_target(32, 32,
					function(...)
						return client_handler(false, ...)
					end
				)
			end
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
end

local function add_wayland_client(source, status)
	local wlcfg = {
		mouse_focus = true
	}

-- reequest focus state to change
	wlcfg.focus =
	function(wnd)
		if not wnd then
			if focus then
				focus:unfocus()
				focus = nil
			end
			return
		end

		focus = wnd
		order_image(wnd.vid, max_current_image_order() + 1)
		wnd:focus()
	end

-- no window focused when the client gets mapped? focus it
	wlcfg.mapped =
	function(wnd)
		if not focus then
			wnd.wm.focus(wnd)
		end
	end

	wlcfg.destroy =
	function(wnd)
		if not wnd then
			ccount = ccount - 1
		end

		if ccount < 1 then
			shutdown(EXIT_SUCCESS)
		end

		if wnd == focus then
			focus = nil
		end
	end

	wlfact(source, status, wlcfg)
end

function client_handler(nested, source, status)
	if status.kind == "registered" then

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

			ccount = ccount + 1

-- next one will be the one to ask for 'real' windows
			accept_target(32, 32,
			function(...)
				return client_handler(true, ...)
			end)

-- and those we just forward to the wayland factory
		else
			add_wayland_client(source, status)
		end
	end

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

function wltest_display_state(status)
-- if the output resizes all clients should know that
end
