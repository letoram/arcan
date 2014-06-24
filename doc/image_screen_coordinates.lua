-- image_screen_coordinates
-- @short: Resolve the current transformation change for the object in question and return the coordinates of the four corners in screen space.
-- @inargs: vid
-- @outargs: x1,y1,x2,y2,x3,y3,x4,y4
-- @group: image
-- @cfunction: arcan_lua_screencoord
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	show_image(a);
	move_image(a, 32, 32);
	rotate_image(a, 145);
	print( image_screen_coordinates(a) );
#endif
end
