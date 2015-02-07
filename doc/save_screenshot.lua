-- save_screenshot
-- @short: Store a copy of the current display to a file.
-- @inargs: dstres, *fmt*, *srcid*
-- @longdescr: This function creates a file of the latest drawn
-- output on the primary display or of the contents of a specific
-- VID of specified in *srcid*.
-- The format setting is by default FORMAT_PNG but can also be
-- FORMAT_PNG_FLIP, FORMAT_RAW8, FORMAT_RAW24 or FORMAT_RAW32 though
-- the RAW formats are primarily for advanced use and debugging purposes.
-- @group: resource
-- @cfunction: screenshot
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
