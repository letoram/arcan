function rendertarget()
-- default pipeline existing both in world and scaled RTs
	local orw = VRESW;
	local orh = VRESH;
	resize_video_canvas(VRESW * 0.5, VRESH * 0.5);
	local a = color_surface(64, 64, 255, 0, 0);
	local b = color_surface(64, 64, 0, 255, 0);
	local c = color_surface(64, 64, 0, 64,255);
	move_image(b, 0, VRESH * 0.5 - 64);
	move_image(c, 0, VRESH - 64);
	show_image({a, b, c});
	nudge_image(a, VRESW - 64, 0, 100, INTERP_EXPINOUT);
	nudge_image(b, VRESW - 64, 0, 100, INTERP_SINE);
	nudge_image(c, VRESW - 64, 0, 100, INTERP_EXPIN);
	nudge_image(a, -1 * (VRESW - 64), 0, 100, INTP_EXPOUT);
	nudge_image(b, -1 * (VRESW - 64), 0, 100, INTERP_LINEAR);
	nudge_image(c, -1 * (VRESW - 64), 0, 100, INTERP_SINE);
	image_transform_cycle(a, true);
	image_transform_cycle(b, true);
	image_transform_cycle(c, true);

	rt1 = alloc_surface(VRESW, VRESH);
	rt2 = alloc_surface(VRESW, VRESH);
	rt3 = alloc_surface(VRESW, VRESH);

	show_image({rt1, rt2, rt3});

	define_rendertarget(rt1, {a, b, c},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, 0);
	define_rendertarget(rt2, {a, b, c},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, -1);
	define_rendertarget(rt3, {a, b, c},
		RENDERTARGET_NODETACH, RENDERTARGET_SCALE, 1);

	resize_video_canvas(orw, orh);

	move_image(rt1, VRESW - image_surface_properties(rt1).width, 0);
	move_image(rt2, VRESW - image_surface_properties(rt2).width,
		VRESH - image_surface_properties(rt2).height);
	move_image(rt3, 0, VRESH - image_surface_properties(rt3).height);

	d = color_surface(64, 64, 255, 255, 255);
	show_image(d);

-- scaled being updated on a tick basis 'manually'
-- normal being updated on a tick basis automatically
	push_video_context();
	pop_video_context();
end

local in_world = true;
function rendertarget_preframe_pulse()
	if (in_world) then
		in_world = false;
		rendertarget_attach(rt3, d, RENDERTARGET_DETACH);
	else
		in_world = true;
		rendertarget_attach(rt2, d, RENDERTARGET_DETACH);
	end
end

function rendertarget_clock_pulse()
	if (0 == CLOCK % 2) then
		rendertarget_forceupdate(rt1);
	end
end
