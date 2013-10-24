-- save_screenshot
-- @short: Store a copy of the current display to a file.
-- @inargs: dstres
-- @group: resource 
-- @cfunction: arcan_lua_screenshot
function main()
#ifdef MAIN
	show_image(fill_surface(64, 64, 255, 0, 0));
	local a = fill_surface(64, 64, 0, 255, 0);
	move_image(a, VRESW - 64, 0);
	local b = fill_surface(64, 64, 0, 0, 255);
	move_image(b, 0, VRESH - 64);
	local c = fill_surface(64,  64, 0, 255, 255);
	move_image(c, VRESW - 64, VRESH - 64);
	show_image({a, b, c});
#endif
end
