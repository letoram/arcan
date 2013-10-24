-- image_origo_offset
-- @short: Shift the current object rotation offset 
-- @inargs: vid, xofs, yofs, *zofs 
-- @group: image 
-- @cfunction: arcan_lua_origoofs
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	show_image({a, b});
	move_image(a, 50, 100);
	move_image(b, 100, 100);
	rotate_image(a, 45);
	rotate_image(b, 45);
	image_origo_shift(b, -10, -10);
#endif
end
