function set4_3()
	local rbox = color_surface(200, 200, 255, 0, 0);
	local bbox = color_surface(200, 200, 0, 0, 255);
	local gbox = color_surface(200, 200, 0, 255, 0);

	show_image({rbox, bbox, gbox});
	move_image(rbox, 100, 100);
	move_image(bbox, 10, 10);
	link_image(rbox, bbox);
	link_image(bbox, gbox);

	move_image(gbox, 0.5*VRESW-50, 0.5*VRESH-50, 200);
	expire_image(gbox, 180);
end
