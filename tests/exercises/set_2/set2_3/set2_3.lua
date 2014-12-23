--
-- We solve this exercise twice,
-- using two different approaches
-- note the latency!
--
function set2_3()
	local b1 = color_surface(64, 64, 255, 0, 0);
	local b2 = color_surface(64, 64, 0, 255, 0);
	move_image(b2, 100, 0);

	blend_image(b1, 1.0, 50);
	move_image(b1, 0, 0, 50);
	move_image(b1, 100, 100, 50);
	rotate_image(b1, 0, 100);
	rotate_image(b1, 90, 50);
	resize_image(b1, 64, 64, 150);
	resize_image(b1, 128, 128, 50);

	blend_image(b2, 0.5, 50);
	tag_image_transform(b2, MASK_OPACITY, step_blend);
end

function step_blend(source)
	move_image(source, 200, 100, 50);
	tag_image_transform(source, MASK_POSITION, step_move);
end

function step_move(source)
	rotate_image(source, 90, 50);
	tag_image_transform(source, MASK_ORIENTATION, step_rotate);
end

function step_rotate(source)
	resize_image(source, 128, 128, 50);
end
