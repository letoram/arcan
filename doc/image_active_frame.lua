-- image_active_frame
-- @short: Set the active (displayed) frame for an object with an allocated frameset.
-- @inargs: vid, index
-- @outargs:
-- @longdescr:
-- @group: image
-- @cfunction: activeframe
-- @note: if the frameset index exceeds the capacity of the frameset in question,
-- whatever is in the first index (0) will be replaced.
-- @note: the behavior when mixing objects with different storage types (textured,
-- nullsurface or colorsurface) is undefined.
-- @note: there are three principal use-cases for the frameset- class of functions.
-- The first one is the more obvious, static animations (combine with the appropriate
-- framecyclemode). The second one is multitexturing where you want shaders that sample
-- data from multiple video objects. The last one is round-robin storage from frameservers
-- where you need access to previous frames.
-- @related: set_image_as_frame, image_framesetsize, image_framecyclemode
function main()
#ifdef MAIN
	a = fill_surface(320, 200, 0, 0, 0);
	show_image(a);

	b = fill_surface(32, 32, 255,   0, 0);
	move_image(b, 320, 200);

	c = fill_surface(32, 32,   0, 255, 0);
	move_image(c, 352, 232);

	image_framesetsize(a, 3, FRAMESET_SPLIT);
	set_image_as_frame(a, b, 1, FRAMESET_DETACH);
	set_image_as_frame(a, c, 2, FRAMESET_NODETACH);

	image_active_frame(a, 1);
#endif
end
