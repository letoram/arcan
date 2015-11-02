function set4_1()
	local rbox = color_surface(200, 200, 255, 0, 0);
	local bbox = color_surface(200, 200, 0, 0, 255);
	blend_image({rbox, bbox}, 0.5);
	move_image(rbox, 100, 100);
	move_image(bbox, 10, 10);
	blend_image(WORLDID, 0.1, 100);
	blend_image(WORLDID, 1.0, 100);
	move_image(WORLDID, 100, 100, 100);
end
