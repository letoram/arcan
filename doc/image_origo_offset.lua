-- image_origo_offset
-- @short: Shift the current object rotation offset
-- @inargs: vid:dst, number:xofs, number:yofs
-- @inargs: vid:dst, number:xofs, number:yofs, number:zofs
-- @longdescr: By default, the rotation origo for each object is set to its
-- local center (0.5*w, 0.5*h).
-- @note: This is relative to the local object itself. For complex object
-- hierarchies, the bounding volume would have to be calculated and each
-- object shifted.
-- @group: image
-- @cfunction: origoofs
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	show_image({a, b});
	move_image(a, 50, 100);
	move_image(b, 100, 100);
	rotate_image(a, 45);
	rotate_image(b, 45);
	image_origo_offset(b, -10, -10);
#endif
end
