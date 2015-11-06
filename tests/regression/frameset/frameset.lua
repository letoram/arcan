function frameset(args)
	arguments = args
	f1 = fill_surface(32, 32, 255,   0,   0);
	f2 = fill_surface(32, 32, 255, 255, 255);
	f3 = fill_surface(32, 32, 0,   255,   0);
	f4 = fill_surface(32, 32, 0,   255,   0);

	s1 = fill_surface(64, 64, 127, 127, 127);

	image_framesetsize(s1, 5);
	set_image_as_frame(s1, f1, 1);
	set_image_as_frame(s1, f2, 2);
	set_image_as_frame(s1, f3, 3);
	set_image_as_frame(s1, f4, 4);

	show_image(s1);
	image_framecyclemode(s1, 10);
	s2 = instance_image(s1);
	image_framecyclemode(s2, 5);

	move_image(s2, 64, 64);
	show_image(s2);
end
