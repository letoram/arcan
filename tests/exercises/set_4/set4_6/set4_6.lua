function set4_6()
	local bbox = color_surface(200, 200, 0, 0, 255);
	local gbox = color_surface(200, 200, 0, 255, 0);
	local rbox = color_surface(200, 200, 255, 0, 0);

	blend_image({rbox, bbox, gbox}, 1.0);
	move_image(rbox, 100, 100);
	move_image(bbox, 10, 10);
	link_image(rbox, bbox);
	link_image(bbox, gbox);
	rotate_image(bbox, 45);

	move_image(gbox, 0.5*VRESW-50, 0.5*VRESH-50);

	image_clip_on(rbox, CLIP_ON);
--	image_clip_on(rbox, CLIP_SHALLOW);
end
