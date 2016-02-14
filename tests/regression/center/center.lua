function center(arg)
	arguments = arg;
-- link some to different spaces so we know the translation works
	local arb = null_surface(1, 1);
	local arb2 = null_surface(1, 1);
	local o = fill_surface(127, 63, 0, 255, 0);

-- create one for each possible anchor point
	local a = fill_surface(16, 32, 255, 0, 0);
	local b = fill_surface(32, 16, 255, 0, 0);
	local c = fill_surface(32, 32, 255, 0, 0);
	local d = fill_surface(32, 32, 255, 0, 0);
	local e = fill_surface(32, 32, 255, 0, 0);

	move_image(arb, 64, 48);
	move_image(arb2, 77, 69);
	link_image(o, arb);
	link_image(e, arb2);
	show_image({a,b,c,d,e,o,arb,arb2});

	center_image(a, o, ANCHOR_UL);
	center_image(b, o, ANCHOR_LL);
	center_image(c, o, ANCHOR_LR);
	center_image(d, o, ANCHOR_UR);
	center_image(e, o, ANCHOR_C);
end

clock = 0;
function center_clock_pulse()
	clock = clock + 1;
	if (clock == 25) then
		save_screenshot(arguments[1]);
		return shutdown();
	end
end
