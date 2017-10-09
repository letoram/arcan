--
-- enable the subsystem, display system events and map
-- limb orientations to cubes
--

function vrtest()
	camera = null_surface(1, 1);
	camtag_model(camera, 0.1, 100.0, 45.0, 1.33, 1, 1);
	forward3d_model(camera, -10.0);

	local tex = fill_surface(32, 32, 0, 255, 0);

	cube = build_3dbox(1, 1, 1);
	blend_image(cube, 0.5, 10);
	image_sharestorage(tex, cube);

	vr_setup("", function(source, status)
		if (status.kind == "limb_added") then
			print("got limb", status.name);
			if (status.name == "neck") then
				vr_map_limb(source, cube, status.id);
			end
		elseif (status.kind == "limb_removed") then
			print("lost limb", status.name);
		end
	end);
end
