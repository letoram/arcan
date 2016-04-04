function recordtest()
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	c = fill_surface(32, 32, 0,   0, 255);

	target_alloc("recordtest", function(source, status)
		if (status.kind == "resized") then
			resize_image(source, status.width, status.height);
			show_image(source);
		end
	end);

	show_image(a);
	show_image(b);
	show_image(c);

	image_transform_cycle(a, 1);
	image_transform_cycle(b, 1);
	image_transform_cycle(c, 1);

	move_image(a, 0, 0);
	move_image(b, VRESW - 32, 0);
	move_image(c, 0, VRESH - 32);

	move_image(a, VRESW - 32, 0, 20);
	move_image(b, 0, VRESH - 32, 20);
	move_image(c, 0, 0, 20);

	move_image(a, 0, VRESH - 32, 20);
	move_image(b, 0, 0, 20);
	move_image(c, VRESW - 32, 0, 20);

	move_image(a, 0, 0, 20);
	move_image(b, VRESW - 32, 0, 20);
	move_image(c, 0, VRESH - 32, 20);

 	microphone = capture_audio("Live! Cam Connect HD VF0750 Analog Mono");

	dstvid = fill_surface(VRESW, VRESH, 0, 0, 0, 320, 240);
	ns = null_surface(VRESW, VRESH);
	image_sharestorage(WORLDID, ns);
	image_set_txcos_default(ns, 1);
	show_image(ns);

	define_recordtarget(dstvid, "testout.mkv", "container=mkv:noaudio:" ..
		"vcodec=H264:fps=60:vpreset=8", {ns}, {},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1,
		function() end
	);
end
