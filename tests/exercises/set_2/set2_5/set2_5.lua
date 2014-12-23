function set2_5()
	local a = fill_surface(32, 32, 0, 255, 0);
	show_image(a);

	move_image(a, VRESW - 32, 0, 50);
	move_image(a, VRESW - 32, VRESH - 32, 50);
	move_image(a, 0, VRESH - 32, 50);
	move_image(a, 0, 0, 50);

	image_transform_cycle(a, 1);
end
