-- image_framecyclemode
-- @short:  Enable/Disable time-triggered active frameset frame cycling.
-- @inargs: vid:dst
-- @inargs: vid:dst, int:time_steps
-- @longdescr: Every video object with a textured backing store has an
-- active frame defined, which usually refers to the backing store that
-- is allocated during object creation or explicitly updated via
-- ref:image_sharestorage. This frame can also be picked from a larger
-- set that is allocated via ref:image_framesetsize and populated via
-- ref:set_image_as_frame. The active frame property can then be
-- managed manually via ref:image_activeframe or automatically via this
-- function. If called without any *time_steps* argument, the feature
-- will be disabled, otherwise the active frame will be cycled in a
-- (n + 1) % count order at a rate of *time_steps* ticks on the logic
-- clock.
-- @group: image
-- @cfunction: framesetcycle
-- @related: image_framesetsize, image_activeframe, set_image_as_frame
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(64, 64, 0, 255, 0);
	c = fill_surface(64, 64, 0, 0, 255);

	image_framesetsize(a, 3);
	set_image_as_frame(a, b, 1);
	set_image_as_frame(a, c, 2);
	image_framecyclemode(a, 1);
#endif
end
