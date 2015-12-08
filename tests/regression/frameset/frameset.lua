function frameset(args)
	arguments = args
	f1 = fill_surface(32, 32, 255,   0,   0);
	f2 = fill_surface(32, 32, 255, 255, 255);
	s1 = fill_surface(64, 64, 127, 127, 127);

	image_framesetsize(s1, 5);
	set_image_as_frame(s1, f1, 1);
	set_image_as_frame(s1, f2, 2);

	local img = load_image("arcanicon.png");
	local t1 = null_surface(64, 64);
	image_sharestorage(img, t1);
	image_set_txcos(t1, {
		0.0, 0.0, 0.5, 0.0,
		0.5, 0.5, 0.0, 0.5
	});
	delete_image(img);
	set_image_as_frame(s1, t1, 3);
	image_set_txcos(t1, {
		0.5, 0.5, 1.0, 0.5,
		1.0, 1.0, 0.5, 1.0
	});
	set_image_as_frame(s1, t1, 4);
	delete_image(t1);

	show_image(s1);
	image_framecyclemode(s1, 10);
end
