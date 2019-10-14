function test()
	local maxw = 72 * 5;
	local maxh = 72 * 3;
	local buf = alloc_surface(maxw, maxh);

	local a = fill_surface(maxw, maxh, 64, 64, 64);
	image_shader(a,
		build_shader(nil, [[
		varying vec2 texco;
		void main()
		{
			gl_FragColor = vec4(0.0, texco.s, 0.0, 1.0);
		}
	]], "col"));

	show_image(a);
	define_rendertarget(buf, {a});
	move_image(a, 100, 50, 100);
	move_image(a, 0, 0, 100);
	image_transform_cycle(a, true);

	local vid = target_alloc("test", maxw, maxh,
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
