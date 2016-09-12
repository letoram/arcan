-- controller_leds
-- @short: Query or rescan for LED controllers
-- @inargs: *ctrlid*
-- @outargs: [nleds, variable, rgb] or [nctrls, low32, high32]
-- @longdescr: If *ctrlid* is set, the values for the specified controller
-- are returned. The id of a controller can be retrieved as part of the _input
-- event handler on status == "added" events either directly on
-- devkind == "led" or for some other devices through the devref field.
-- _display_state events may also provide a ledctrl,ledind.
-- If *ctrlid* is not set or set to -1, a rescan will be queued that might
-- generate additional device status events. It also returns the number of
-- active controllers and two bitmasks (capped to 64 controllers)
-- @group: iodev
-- @cfunction: n_leds
-- @flags:
function main()
#ifdef MAIN
	local do_ctrl = function(i)
		local nleds, shift, rgb = controller_leds(i);
		print("controller", i, "leds:", nleds,
			"intensity:", intensity and "yes" or "no",
			"rgb:", rgb and "yes" or "no");
	end

-- due to the double size restriction, this had to be split
	local count, first, second = controller_leds();
	print("# controllers:", count);
	for i=0, 31 do
		if (bit.band(first, bit.lshift(1, i))) then
			do_ctrl(i);
		end
	end

	for i=0, 31 do
		if (bit.band(first, bit.lshift(1, i))) then
			do_ctrl(32, i);
		end
	end
#endif
end
