function test()
	local buf = alloc_surface(128, 128);
	local a = color_surface(64, 64, 0, 255, 0);
	show_image(a);
	move_image(a, 64, 64, 100);
	move_image(a, 0, 0, 100);
	image_transform_cycle(a, true);

	define_rendertarget(buf, {a});

	print("waiting forclient on test");

	local vid = target_alloc("test", 128, 128,
	function(source, status)
		if status.kind == "registered" then
			if status.segkind ~= "encoder" then
				delete_image(source);
				print("unexpected segment type:", status.segkind);
				return shutdown();
			end

			print("binding new encode to renderbuffer");
			rendertarget_bind(buf, source);
			delete_image(source);

		elseif status.kind == "terminated" then
			print("terminated");
			delete_image(source);
			return shutdown();
		end
	end);
end
