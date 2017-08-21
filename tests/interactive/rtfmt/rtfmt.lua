-- trying out rendering on different quality surfaces and with MSAA
function rtfmt()
	local rtsurf = alloc_surface(320, 200);

-- build a 3d box and setup in a rendertarget with a MSAA target
	local green = fill_surface(32, 32, 0, 255, 0);
	camera = null_surface(1, 1);
	image_tracetag(camera, "camera");
	forward3d_model(camera, -10.0);

	cube = build_3dbox(1, 1, 1);
	blend_image(cube, 0.7);
	rotate3d_model(cube, 0, 45, 0, 100);
	rotate3d_model(cube, 45, 45, 0, 100);
	rotate3d_model(cube, 45, 456, 45, 100);
	image_transform_cycle(cube, true);
	image_sharestorage(green, cube);
	define_rendertarget(rtsurf, {cube, camera},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1, RENDERTARGET_MSAA);
	camtag_model(camera, 0.01, 100.0, 45.0, 1.33, 1, 1);
	show_image(rtsurf);
	resize_image(rtsurf, 800, 800);
end
