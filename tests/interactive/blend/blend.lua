local function build_triplet(w, h, x, y, mode)
	local r = color_surface(w, h, 255, 0, 0)
	local g = color_surface(w, h, 0, 255, 0)
	local b = color_surface(w, h, 0, 0, 255)

	move_image(r, x, y)
	move_image(g, x, y + 0.5 * h)
	move_image(b, x + 0.5 * w, y + 0.25 * h)

	blend_image({r, g, b}, 1.0, 400)
	blend_image({r, g, b}, 0.0, 400)

	image_transform_cycle(r, true)
	image_transform_cycle(g, true)
	image_transform_cycle(b, true)

	force_image_blend(r, mode)
	force_image_blend(g, mode)
	force_image_blend(b, mode)
end

function blend()
	image_color(WORLDID, 127, 127, 127)

	build_triplet(32, 32, 32, 32, BLEND_NORMAL)
	build_triplet(32, 32, 78, 32)

	build_triplet(32, 32, 32, 78, BLEND_ADD)
	build_triplet(32, 32, 78, 78, BLEND_MULTIPLY)
	build_triplet(32, 32, 122, 32, BLEND_SUB)
end
