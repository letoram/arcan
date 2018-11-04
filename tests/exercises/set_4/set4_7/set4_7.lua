function set4_7()
	local box = color_surface(100, 100, 0, 255, 0)
	show_image(box)

	local anchor = null_surface(VRESW, VRESH)
	center_image(box, anchor)

	local points = {
		ANCHOR_UL, ANCHOR_UR,
		ANCHOR_LL, ANCHOR_LR,
	}

	for _,v in ipairs(points) do
		local r = color_surface(10, 10, 255, 0, 0)
		show_image(r)
		link_image(r, box, v)
	end

	resize_image(box, 200, 200, 100)
end
