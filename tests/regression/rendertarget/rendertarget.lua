function rendertarget()
	vid1 = fill_surface(32, 32, 255, 0, 0);
	vid2 = fill_surface(32, 32, 0, 255, 0);
	vid3 = fill_surface(32, 32, 0, 0, 255);
	vid4 = fill_surface(32, 32, 255, 255, 255),
	vid5 = fill_surface(32, 32, 255, 255, 0);

	show_image({vid1, vid2, vid3});
	move_image(vid1, VRESW - 32, VRESH - 32);
	move_image(vid2, VRESW - 32, VRESH - 32);
	move_image(vid3, 0, VRESH - 32);

	rotate_image(vid2, 45);

	surf = alloc_surface(VRESW, VRESH);
	define_rendertarget(surf,
		{vid1, vid2, vid3},
		RENDERTARGET_NODETACH, RENDERTARGET_NOSCALE
	);
	show_image(surf);
	move_image(surf, VRESW, VRESH, 100);
--	resize_video_canvas(VRESW * 2, VRESH * 2);

	surf = alloc_surface(VRESW * 0.5, VRESH * 0.5);
	define_rendertarget(surf,
		{vid1, vid2, vid3},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE
	);
	show_image(surf);
	move_image(vid3, VRESW - 32, 0, 100);

	surf = alloc_surface(VRESW, VRESH);
	show_image(surf);
	resize_image(surf, VRESW * 0.25, VRESH * 0.25);
	move_image(surf, 0, VRESH * 0.5);
	define_rendertarget(surf,
		{vid1, vid4, vid5},
		RENDERTARGET_DETACH, RENDERTARGET_NOSCALE);
	show_image(surf);

	rendertarget_noclear(WORLDID, true);
end
