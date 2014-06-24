-- image_color
-- @short: Update the color values for a color_surface
-- @inargs: id, red, green, blue
-- @outargs: true or false
-- @group: image
-- @cfunction: arcan_lua_imagecolor
-- @related:
function main()
#ifdef MAIN
	local a = color_surface(64, 64, 255, 0, 0);
	show_image(a);
	image_color(a, 0, 255, 0);
#endif

#ifdef ERROR1
	image_color(BADID);
#endif
end
