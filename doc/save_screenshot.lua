-- save_screenshot
-- @short: Store a copy of the current display to a file.
-- @longdescr: This function takes the last front buffer rendered,
-- reads back and stores into dstres as a 32bit- RGB PNG.
-- If flip is set to any integer other than 0, the final image will be flipped
-- around the Y axis.
-- If a srcid is specified and that id is associated with a
-- textured backing store, that will be read-back instead of the front buffer.
-- @inargs: dstres, *flip*, *srcid*
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
