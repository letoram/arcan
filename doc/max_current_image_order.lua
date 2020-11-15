-- max_current_image_order
-- @short: Find the highest ordervalue in use in the current context.
-- @inargs: *rtgt*
-- @outargs: orderval
-- @longdescr: Scan a specific (default: worldid) rendertarget for the
-- highest drawing order value used. Note that the range 65531..65535 is
-- explicitly ignored to be able to use relative operations e.g.
-- order_image(a, max_current_image_order() + 1); without objects used
-- as overlays, cursors or similar special targets interfering.
-- @group: image
-- @cfunction: maxorderimage
-- @related: order_image, image_inherit_order
function main()
#ifdef MAIN
	print(max_current_image_order());
	a = fill_surface(32, 32, 0, 0, 0);
	order_image(a, 65500);
	print(max_current_image_order());
	order_image(a, 65535);
	print(max_current_image_order());
#endif
end
