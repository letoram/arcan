-- image_screen_coordinates
-- @short: Lookup screen space coordinates for the specified object.
-- @longdescr: This function resolves the screen space coordinates
-- of the four corners of the specified vid, taking position,
-- scale and rotation transform into account.
-- @note: This does not include any vertex- stage transformations
-- that may be applied by a non-standard shader.
-- @inargs: vid
-- @outargs: x1,y1,x2,y2,x3,y3,x4,y4
-- @group: image
-- @cfunction: screencoord
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	show_image(a);
	move_image(a, 32, 32);
	rotate_image(a, 145);
	print( image_screen_coordinates(a) );
#endif
end
