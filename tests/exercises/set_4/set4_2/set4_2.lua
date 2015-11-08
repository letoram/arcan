function set4_2()
	local rbox = color_surface(200, 200, 255, 0, 0);
	local bbox = color_surface(200, 200, 0, 0, 255);
	show_image({rbox, bbox});
	move_image(rbox, 100, 100);
	move_image(bbox, 10, 10);
	link_image(rbox, bbox);
-- step 2, link_image(bbox, rbox);
	move_image(WORLDID, 50, 0, 100);
	nudge_image(rbox, 0, 50, 100);
	rotate_image(rbox, 50, 100);
end
