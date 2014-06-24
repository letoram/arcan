-- scale_image
-- @short: Set the current scale-factor for the specified image.
-- @inargs: vid, sx, sy, *dt*
-- @longdescr: Alter the scale transform for *vid*. These values
-- are relative to the initial dimensions for the object in question,
-- while function such as resize_image internally converts the absolute
-- values to relative scale.
-- @group: image
-- @cfunction: arcan_lua_scaleimage
-- @related: resize_image
function main()
#ifdef MAIN
	a = fill_surface(128, 128, 0, 255, 0, 64, 64);
	scale_image(a, 2.0, 2.0, 100);
	show_image(a);
#endif
end
