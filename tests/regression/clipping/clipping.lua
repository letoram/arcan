function clipping(args)
	arguments = args
	p1 = fill_surface(64, 64, 255, 0, 0);
	c1 = fill_surface(64, 64, 0, 255, 0);
	local d1 = render_text([[\fdefault.ttf,20\#ffffff abcdefhijklmnopqrstuvwxyz123456789abcdefhijklmnopqrstuvwxyz]]);

	move_image(c1, 32, 32);
	move_image(p1, 32, 32);
	image_clip_on(c1, CLIP_SHALLOW);
	image_clip_on(d1, CLIP_SHALLOW);
	link_image(d1, p1);
	link_image(c1, p1);

	p2 = fill_surface(64, 64, 255, 0, 0);
	c2 = fill_surface(64, 64, 0, 255, 0);
	move_image(p2, 128, 32);
	rotate_image(c2, 45);
	image_clip_on(c2, CLIP_SHALLOW);
	link_image(c2, p2);

	p3 = fill_surface(64, 64, 255, 0, 0);
	c3 = fill_surface(64, 64, 0, 255, 0);
	move_image(p3, 32, 128);
	rotate_image(c3, 45);
	rotate_image(p3, -60);
	image_clip_on(c3, CLIP_SHALLOW);
	link_image(c3, p3);

	p4 = fill_surface(64, 64, 0, 0, 255);
	c4 = fill_surface(64, 64, 255, 0, 0);
	c5 = fill_surface(64, 64, 0, 255, 0);
	move_image(p4, 128, 128);
	move_image(c4, 30, 30);
	rotate_image(c4, 45);
	rotate_image(c5, 45);
	image_clip_on(c5, CLIP_ON);
	link_image(c4, p4);
	link_image(c5, c4);

	p5 = fill_surface(64, 64, 0, 0, 255);
	c6 = fill_surface(64, 64, 255, 0, 0);
	c7 = fill_surface(64, 64, 0, 255, 0);
	move_image(p5, 280, 128);
	move_image(c6, 10, 10);
	rotate_image(p5, 20);
	rotate_image(c6, 45);
	rotate_image(c7, -45);
	image_clip_on(c6, CLIP_ON);
	image_clip_on(c7, CLIP_ON);
	link_image(c6, p5);
	link_image(c7, c6);

	show_image({p1, c1, d1, p2, c2, p3, c3, p4, c4, c5, p5, c6, c7});
end

count = 1;
function clipping_clock_pulse()
	count = count + 1;
	if (count > 100) then
		save_screenshot(arguments[1]);
		return shutdown("");
	end
end
