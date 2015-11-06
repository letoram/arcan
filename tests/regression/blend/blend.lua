function blend(arg)
	arguments = arg
	local bgsurf = fill_surface(VRESW, VRESH, 32, 64, 96);
	show_image(bgsurf);
	local bnorm  = fill_surface(64, 64, 255, 0, 0);
	local bforce = fill_surface(64, 64, 255, 0, 0);
	local bmult  = fill_surface(64, 64, 255, 0, 0);
	local badd   = fill_surface(64, 64, 255, 0, 0);
	move_image(bforce, 64, 0);
	move_image(bmult, 64, 64);
	move_image(badd, 0, 64);
	move_image(bnorm, 0, 0);
	force_image_blend(bnorm, BLEND_NORMAL);
	force_image_blend(badd, BLEND_ADD);
	force_image_blend(bmult, BLEND_MULTIPLY);
	force_image_blend(bforce, BLEND_FORCE);
	blend_image({bnorm, badd, bmult, bforce}, 0.5);
end

clock = 0;
function blend_clock_pulse()
	clock = clock + 1;
	if (clock == 25) then
		save_screenshot(arguments[1]);
		return shutdown();
	end
end
