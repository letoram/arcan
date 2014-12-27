-- image_inherit_order
-- @short: Changes the specific object order value to be
-- expressed as relative to its parent.
-- @inargs: vid, bool_state
-- @outargs:
-- @longdescr: Normally, order is expressed as an independent property.
-- For some applications e.g. user-interfaces, it might be more
-- useful and intuitive to express it relative to a linked object
-- to cut down on the amount of tracking and reordering calles needed
-- to reorder an anchor point used for something like a window.
-- By default, order inheritance is disabled, but can be explicitly
-- enabled by calling this function.
-- @note: For long hierarchies, this can be an expensive operation
-- as changes to order implies a detach/attach operation and is
-- implemented recursively.
-- @group: image
-- @cfunction: orderinherit
function main()
	a = fill_surface(32, 32, 255, 0, 0);
#ifdef MAIN
	b = fill_surface(16, 16, 0, 255, 0);
	order_image(a, 2);
	order_image(b, 1);

	image_inherit_order(b, true);
	link_image(b, a);
	show_image({a, b});
#endif

#ifdef ERROR
	order_image(BADID);
#endif

#ifdef ERROR2
	order_image(a, "not a number");
#endif
end
