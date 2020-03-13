-- intercept input events and convert mouse samples to touch- based ones
local ep = _G[APPLID .. "_input"]

if not ep then
	return
end

-- accumulator for relative- only mouse devices, as a legacy issue, mouse
-- samples can come both absolute and relative depending on os/input platform
local acc_x = 0
local acc_y = 0

-- some visible cursor to show where we are before clicking
local cursor = fill_surface(8, 8, 0, 127, 0)
image_mask_set(cursor, MASK_UNPICKABLE)
show_image(cursor)
order_image(cursor, 65535)

_G[APPLID .. "_input"] =
function(iotbl, ...)
	if not iotbl.mouse then
		return ep(iotbl, ...)
	end

	if iotbl.digital then
		ep({
			kind = "touch",
			touch = true,
			devid = 0,
			active = iotbl.active,
			subid = 127 + iotbl.subid,
			size = 1,
			pressure = 1,
			x = acc_x,
			y = acc_y
		}, ...)
		return;
	end

	local vid = set_context_attachment(BADID)
	local aw, ah
	if vid == WORLDID then
		aw = VRESW
		ah = VRESH
	else
		local props = image_storage_properties(vid)
		aw = props.width
		ah = props.height
	end

	if iotbl.relative then
		if iotbl.subid == 0 then
			acc_x = acc_x + iotbl.samples[1]
		else
			acc_y = acc_y + iotbl.samples[1]
		end
	else
		if iotbl.subid == 0 then
			acc_x = iotbl.samples[1]
		else
			acc_y = iotbl.samples[1]
		end
	end

-- clamp the accumulators
	acc_x = acc_x < 0 and 0 or acc_x
	acc_y = acc_y < 0 and 0 or acc_y
	acc_x = acc_x > aw and aw or acc_x
	acc_y = acc_y > ah and ah or acc_y
	move_image(cursor, acc_x, acc_y)

	assert(acc_x ~= nil);
	assert(acc_y ~= nil);
end
