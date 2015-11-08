function set4_4()
	local rbox = color_surface(200, 200, 255, 0, 0);
	local bbox = color_surface(200, 200, 0, 0, 255);
	local gbox = color_surface(200, 200, 0, 255, 0);

	blend_image({rbox, bbox, gbox}, 1.0, 200);
	move_image(rbox, 100, 100);
	move_image(bbox, 10, 10);
	link_image(rbox, bbox);
	link_image(bbox, gbox);
	rotate_image(bbox, 45, 200);

	move_image(gbox, 0.5*VRESW-50, 0.5*VRESH-50, 200);
	expire_image(gbox, 180);

	image_mask_clear(rbox, MASK_LIVING);

-- experiment with these toggles
-- image_mask_clear(gbox, MASK_LIVING);
-- image_mask_clear(bbox, MASK_LIVING);

-- image_mask_clear(rbox, MASK_OPACITY);
-- image_mask_clear(rbox, MASK_ORIENTATION);
end
