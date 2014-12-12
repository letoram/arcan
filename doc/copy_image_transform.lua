-- copy_image_transform
-- @short: Duplicate the transform chain of one VID and transfer it to another.
-- @inargs: srcvid, dstvid
-- @longdescr: This function traverses the entire transform chain of the srcvid, copying each transform step and attaches it to a new chain in dstvid.
-- @note: This will also initiate a recursive rendering re-order.
-- @note: This will irrevocably alter the origw,origh properties in the destination order (in order for the scale transform to be usable).
-- @note: The original transform chain in the destination VID will be removed.
-- @note: src and dst cannot be the same VID.
-- @note: Transformations are stored relative of the source objects coordinate space and, with the exception of scale, won't be translated.
-- @group: image
-- @cfunction: copytransform
-- @related: copy_surface_properties
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	blend_image(a, 0.5);
	move_image(a, 200, 200, 100);
	rotate_image(a, 350, 100);
	blend_image(a, 1.0, 100);

	b = fill_surface(32, 32, 0, 255, 0);
	copy_image_transform(a, b);
	instant_image_transform(a);
#endif

#ifdef ERROR
	a = fill_surface(32, 32, 0, 255, 0);
	copy_image_transform(a, a);
#endif

#ifdef ERROR2
	copy_image_transform(-10, nil);
#endif
end
