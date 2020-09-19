colors = {
	{255, 0, 0},
	{0, 255, 0},
	{0, 0, 255},
}

color_ind = 1

function rgbswitch(args)
	bg = color_surface(VRESW, VRESH, unpack(colors[color_ind]))
	show_image(bg)

	if args[1] then
		local num = 0
		local num = tonumber(args[1])
		if not num or num <= 0 then
			return
		end

		local counter = num
		rgbswitch_clock_pulse =
		function()
			counter = counter - 1
			if counter == 0 then
				counter = num
				step()
			end
		end
	end
end

function step()
	color_ind = color_ind + 1
	if color_ind > #colors then
		color_ind = 1
	end
	image_color(bg, unpack(colors[color_ind]))
	print(color_ind, unpack(colors[color_ind]))
end

function rgbswitch_input(iotbl)
	if iotbl.digital and iotbl.active then
		step()
	end
end

function rgbswitch_display_state()
	resize_image(bg, VRESW, VRESH)
end
