function interp()
	a = fill_surface(64, 64, 255, 0, 0);
	image_transform_cycle(a, 1);
	move_image(a, 100, 100, 50, INTERP_EXPIN);
	move_image(a,   0,   0, 50, INTERP_EXPOUT);
	move_image(a, 100, 100, 50, INTERP_EXPINOUT);
	move_image(a,   0,   0, 50, INTERP_SINE);
	move_image(a, 100, 100, 50, INTERP_LINEAR);
	move_image(a,   0,   0, 50, INTERP_SMOOTHSTEP);
	show_image(a);

	b = fill_surface(64, 64, 0, 0, 255);
	move_image(b, 200, 200);
	image_transform_cycle(b, 1);
	resize_image(b, 128, 128, 50, INTERP_EXPIN);
	resize_image(b,   1,   1, 50, INTERP_EXPOUT);
	resize_image(b, 128, 128, 50, INTERP_EXPINOUT);
	resize_image(b,   1,   1, 50, INTERP_SINE);
	resize_image(b, 128, 128, 50, INTERP_LINEAR);
	resize_image(b,   1,   1, 50, INTERP_SMOOTHSTEP);
	show_image(b);

	d = fill_surface(64, 64, 0, 255, 0);
	move_image(d, 200, 0);
	image_transform_cycle(d, 1);
	blend_image(d, 1.0, 50, INTERP_EXPIN);
	blend_image(d,   0, 50, INTERP_EXPOUT);
	blend_image(d, 1.0, 50, INTERP_EXPINOUT);
	blend_image(d,   0, 50, INTERP_SINE);
	blend_image(d, 1.0, 50, INTERP_LINEAR);
	blend_image(d,   0, 50, INTERP_SMOOTHSTEP);
end
