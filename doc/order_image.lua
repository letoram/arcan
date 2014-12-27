-- order_image
-- @short: Alter the drawing order of the specified image.
-- @inargs: vid or tblvid, newzv
-- @longdescr: Every object has an order property that determines
-- when it should be drawn in respect to other ones. This value
-- can be changed by calling the order_image function on a video
-- object or a table of video objects. The newzv should be within
-- the range 0 <= n < 65535 and will be clamped. The execption to
-- this is objects that are linked to others and have their order
-- being relative to its parent, where negative values are permitted
-- but will be resolved to a value within the specified range.
-- @note: This only applies to the active owner of an
-- image, for images attached to multiple rendertarget,
-- such changes won't take place until you forcibly attach/detach
-- for each specified rendertarget.
-- @note: Order can also be relative to the world- order
-- of the resolved parent, see image_inherit_order.
-- @group: image
-- @cfunction: orderimage
-- @related: image_inherit_order, max_current_image_order
function main()
#ifdef MAIN
	a = color_surface(32, 32, 255,   0, 0);
	b = color_surface(32, 32,   0, 255, 0);
	move_image(b, 16, 16);

	show_image({a, b});
	order_image(a, 2);
#endif

#ifdef ERROR
	a = color_surface(32, 32, 255, 0, 0);
	order_image(a, -1);
#endif
end
