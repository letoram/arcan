-- image_origo_offset
-- @short: Shift the current object rotation offset
-- @longdescr: By default, the rotation origo for each object
-- is set to its lokal center (0.5*w, 0.5*h). This function can
-- shift this to (0.5*w+ofs_x, 0.5*h+ofs_y).
-- @note: There is still no automatic way to have a dynamic
-- offset that is set relative to the center of the area of the
-- entire object hierarchy.
-- @inargs: vid, xofs, yofs, *zofs
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
