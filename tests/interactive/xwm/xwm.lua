-- event handler tables
local root_dispatch = {}
local surf_dispatch = {}

function xwm()
	xwm_listen()
	image_color(WORLDID, 64, 96, 64)
end

function xwm_listen()
-- Input will be routed to the connection root and it will act as an anchor
-- but will not actually be visible itself
	local vid = target_alloc("xwm",
		function(source, status)
			if root_dispatch[status.kind] then
				return root_dispatch[status.kind](source, status)
			end
		end
	)
	image_mask_set(vid, MASK_UNPICKABLE)
end

-- just forward verbatim to focused bridge
function xwm_input(iotbl)
	if not valid_vid(x11_bridge, TYPE_FRAMESERVER) then
		return
	end

	target_input(x11_bridge, iotbl)
end

local function drop_client(vid)
	delete_image(vid)
	x11_bridge = nil
	xwm_listen()
end

root_dispatch.terminated = drop_client
function root_dispatch.registered(source, status)
	if status.segkind ~= "bridge-x11" then
		warning("connection from non-x11 primary segment rejected")
		drop_client(source)
	end
	x11_bridge = source
end

function root_dispatch.preroll(source, status)
-- send information about desired output display properties
-- permit color management transfers and so on
	target_flags(source, TARGET_DRAINQUEUE)
end

-- just resize the surface regardless of what
function root_dispatch.resized(source, status)
	resize_image(source, status.width, status.height)
end

function root_dispatch.segment_request(source, status)

-- this only happens if the xorg instance is ran with 'rootless' mode (or if we
-- explicitly ask for something to be redirected, but that is not the case here)
	if status.segkind == "bridge-x11" then
		local surf = accept_target(
			status.width, status.height,
			function(source, status)
				if surf_dispatch[status.kind] then
					return surf_dispatch[status.kind](source, status)
				end
			end
		)

-- all mouse input still happens on the virtual super surface
		link_image(surf, source)
		image_mask_set(surf, MASK_UNPICKABLE)
		image_mask_clear(surf, MASK_OPACITY)

	elseif status.segkind == "cursor" then
		if valid_vid(root_cursor) then
			delete_image(root_cursor)
		end

-- accelerated cursor, warping is done through viewport events - calls to map
-- display layer would also work.
		root_cursor =
			accept_target(status.width, status.height,
			function(source, status)
				if status.kind == "resized" then
					show_image(source)
					resize_image(source, status.width, status.height)
				elseif status.kind == "viewport" then
					move_image(source, status.rel_x, status.rel_y)
				end
			end
		)

		order_image(root_cursor, 65535)
		show_image(root_cursor)
	end

-- reject the others as we don't need clipboard, could be useful still for synching
-- clipboard between different x instances but since this is an example/test appl
-- that is outside scope.
end

function root_dispatch.message(source, status)
-- don't have much use here
end

function surf_dispatch.viewport(source, status)
	blend_image(source, status.invisible and 0 or 1)
	move_image(source, status.rel_x, status.rel_y)
end

function surf_dispatch.resized(source, status)
	resize_image(source, status.width, status.height)
	show_image(source)
end

function surf_dispatch.terminated(source, status)
	delete_image(source)
end
