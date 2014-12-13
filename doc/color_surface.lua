-- color_surface
-- @short: Create a vobj with a single- color storage
-- @inargs: w, h, r, g, b
-- @outargs: VID or BADID
-- @note: These use a different backing store and a single-color
-- non-textured shader with the color values shader-accessible as a vec3 obj_col uniform.
-- @note: No texture units will be mapped for these objects.
-- @group: image
-- @cfunction: colorsurface
-- @related:
function main()
#ifdef MAIN
	a = color_surface(32, 32, 255, 0, 0);
	show_image(a);
#endif
end
