-- order_image
-- @short: Alter the drawing order of the specified image.
-- @inargs: vid or tblvid, newzv 
-- @longdescr: The internal rendering pipeline treats images in a linear fashion
-- and each rendering context is maintained as a list sorted on the current order value.
-- This will detach the object from the main pipeline and then reattach at the new position.
-- @note: This only applies to the active owner of an image, for images attached to
-- multiple rendertarget, such changes won't take place until you forcibly attach/detach
-- for each specified rendertarget.
-- @note: newzv is internally capped to 65535
-- @note: newzv cannot be lower than 0
-- @note: Order can also be relative to the world- order of the resolved parent,
-- see image_inherit_order.
-- @group: image 
-- @cfunction: arcan_lua_orderimage
-- @related: image_inherit_order, max_current_image_order
function main()
#ifdef MAIN
	a = color_surface(32, 32, 255,   0, 0);
	b = color_surface(32, 32,   0, 255, 0);
	move_image(b, 16, 16);

	show_image({a, b});
	order_image(a, 2);
#endif

#ifdef ERROR1
	a = color_surface(32, 32, 255, 0, 0);
	order_image(a, -1);
#endif
end
