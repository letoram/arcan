function decortest()
	system_load("builtin/mouse.lua")()
	local cursor = fill_surface(8, 8, 0, 255, 0)

	mouse_setup(cursor, 65535, 1, true, false)

	mouse_add_cursor("rz_diag_l", fill_surface(8, 8, 0, 255, 127), 0, 0)
	mouse_add_cursor("rz_diag_r", fill_surface(8, 8, 0, 255, 127), 0, 0)
	mouse_add_cursor("rz_left", fill_surface(8, 8, 127, 255, 127), 0, 0)
	mouse_add_cursor("rz_right", fill_surface(8, 8, 127, 255, 0), 0, 0)
	mouse_add_cursor("rz_up", fill_surface(8, 8, 127, 255, 0), 0, 0)
	mouse_add_cursor("rz_down", fill_surface(8, 8, 127, 255, 0), 0, 0)

	local wnd = color_surface(320, 200, 127, 127, 127)
	local w = 320
	local h = 200

-- 'worst case' asymetric and animated
	decorator = system_load("builtin/decorator.lua")()({
		border = {2, 4, 6, 8},
		pad = {5, 10, 5, 10},
		select = function(dec, active, source)
			mouse_switch_cursor(source)
		end,
		drag_rz = function(dec, cont, dx, dy, mx, my)
			w = w + dx
			h = h + dy
			resize_image(wnd, w, h)
			decor:update(w, h)
			nudge_image(wnd, dx * mx, dy * my)
		end
	})

	show_image(wnd)
	decor = decorator(wnd)
	move_image(wnd, 100, 100)
	decor:border_color(255, 127, 0, 255)

	resize_image(wnd, 100, 200, 50)
end

function decortest_input(iotbl)
	if iotbl.mouse or iotbl.touch then
		mouse_iotbl_input(iotbl)
		return
	end
end
