-- rendertarget_range
-- @short: Limit the order- range of objects to render
-- @inargs: vid:rtgt, int:min, int:max
-- @outargs: bool:ok
-- @longdescr: In some render- and optimization scenarios one might want
-- to only allow a certain set of objects to be rendered. Normally object
-- hierarchies are ordered based on an order value, see ref:order_image
-- and the default rendering pipeline will process these objects according
-- to that order, going from low to high.
-- Using this function, a rendertarget (including the special WORLDID)
-- can be set to skip values that fall outside min <= val <= max. The
-- objects will still have external storage and similar processing being
-- synchronized, they will just not be considered when generating the
-- rendertarget output.
-- @note: if min or max is set to < 0 or max < min, the rendertarget
-- will reset to the default mode of everything being processed.
-- @note: if max == min, nothing will be drawn.
-- @group: targetcontrol
-- @cfunction: rendertargetrange
-- @related: define_rendertarget, order_image, image_inherit_order
function main()
#ifdef MAIN
-- in this example, only the green object will be visible
	local red = color_surface(64, 64, 255, 0, 0);
	local green = color_surface(64, 64, 0, 255, 0);
	local blue = color_surface(64, 64, 0, 0, 255);
	show_image({red, green, blue});
	move_image(green, 0, 64);
	move_image(blue, 64, 0);
	order_image(green, 5);

	rendertarget_range(WORLDID, 4, 6);
#endif

#ifdef ERROR1
#endif
end
