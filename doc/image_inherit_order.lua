-- image_inherit_order
-- @short: Changes the specific object order value to be expressed as relative to its parent. 
-- @inargs: vid, bool_state 
-- @outargs:  
-- @longdescr: Normally, order is expressed as an independent property. For some applications e.g. user-interfaces, it might be more useful and cleaner to express it relative to a linked object in order to not having to do multiple order calls when an object needs to be pushed to the front (rendered last), this function enabled/disables that behavior.
-- @note: Resolved order values are clamped to parent_order <= object_order <= max_order_val
-- @note: For long hierarchies, this is a notably expensive operation as changes to order 
-- imples a detach/attach operation and is implemented recursively.
-- @group: image 
-- @cfunction: arcan_lua_orderinherit
-- @flags: 
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(16, 16, 0, 255, 0);
	order_image(a, 2);
	order_image(b, 1);

	image_inherit_order(b, true);
	link_image(b, a);
	show_image({a, b});
#endif

#ifdef ERROR1

#endif
end
