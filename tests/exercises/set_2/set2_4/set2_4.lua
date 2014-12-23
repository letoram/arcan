function set2_4()
	local a1 = color_surface(32, 32, 255, 0, 0);
	local b1 = color_surface(32, 32, 0, 255, 0);

	resize_image(a1, 64, 64, 100);
	move_image(b1, 64, 0);
	scale_image(b1, 2, 2, 100);

	local a2 = color_surface(32, 32, 0, 255, 255);
	local b2 = color_surface(32, 32, 255, 0, 255);

	blend_image({a1, b1, a2, b2}, 1.0);
	move_image(a2, 100, 100);
	move_image(b2, 132, 100);

	move_image(a2, 200, 100, 100);
	nudge_image(b2, 100, 0, 100);
end
