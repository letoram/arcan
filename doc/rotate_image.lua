-- rotate_image
-- @short: Rotate the image around its own center.
-- @inargs: vid, newang, *dt*
-- @note: For transformation hierarchies where the orientation will depend on
-- that of a parent, grandparent etc. the desired effect might require that
-- you define an origo translation through the use of image_origo_offset.
-- @longdescr:
-- @group: image
-- @cfunction: rotateimage
-- @inargs: vid, newx, newy, *time*
-- @cfunction: moveimage
-- @related: image_origo_shift
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	show_image(a);
	rotate_image(a, 180, 200);
	rotate_image(a, 270, 100);
	rotate_image(a, 380, 100);
	rotate_image(a,   0, 100);
#endif
end
