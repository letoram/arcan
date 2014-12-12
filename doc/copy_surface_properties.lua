-- copy_surface_properties
-- @short: Copy key surface properties from one VID to another.
-- @inargs: srcvid, dstvid
-- @outargs:
-- @longdescr: This function will first resolve the current surface properties of *srcvid* into world space and then store the result in *dstvid*. This covers position, orientation, opacity and scale.
-- @note: The resolved properties will not be translated into the local coordinate space of *dstvid*, thus the results may be undesired if *dstvid* has its dimensions linked relative to another object than worldid.
-- @note: Scale is treated differently due to its relation with the initial width,height of the source. This is solved by translating the resolved dimension into a scale factor.
-- @note: The rotation transfer does not take any rotation origo offset into account.
-- @note: Using the same object for src and for dst is prohibited.
-- @group: image
-- @related: copy_image_transform
-- @cfunction: copyimageprop
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	blend_image(a, 0.5);
	move_image(a, 100, 100);
	rotate_image(a, 300);
	resize_image(a, 128, 128);

	b = fill_surface(16, 16, 0, 255, 0);
	copy_surface_properties(a, b);

	move_image(a, 0, 0);
#endif

#ifdef ERROR
	a = fill_surface(32, 32, 255, 0, 0);
	copy_surface_properties(a, a);
#endif

#ifdef ERROR2
	copy_surface_properties(nil, 1);
#endif
end
