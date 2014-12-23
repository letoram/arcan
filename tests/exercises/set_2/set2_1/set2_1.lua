function set2_1()
	local box = color_surface(64, 64, 0, 255, 0);
	show_image(box);
	move_image(box, VRESW * 0.5 - 32, VRESH * 0.5 - 32, CLOCKRATE);
end
