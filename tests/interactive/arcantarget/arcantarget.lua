function arcantarget()
	arcantarget_hint("input_label", {labelhint = "hi there"});
	target_input(WORLDID, "testies");
	local col = color_surface(32, 32, 255, 0, 0);
	show_image(col);
	move_image(col, 100, 100, 100);
	move_image(col, 0, 0, 100);
	image_transform_cycle(col, true);

	local buffer = alloc_surface(320, 200);
	local clone = color_surface(32, 32, 0, 255, 0);
	show_image(clone);
	move_image(clone, 100, 100, 100);
	move_image(clone, 0, 0, 100);
	image_transform_cycle(clone, true);

	define_arcantarget(buffer, "media", {clone},
	function(source, status)
		print(status.kind)
	end
	)
--	define_rendertarget(buffer, {clone})
--	show_image(buffer)
--	move_image(buffer, 100, 100)
end
