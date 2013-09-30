-- max_current_image_order
-- @short: Find the highest ordervalue in use in the current context. 
-- @outargs: orderval 
-- @group: image 
-- @cfunction: arcan_lua_maxorderimage
-- @related: order_image, image_inherit_order 
function main()
#ifdef MAIN
	print(max_current_image_order());
	a = fill_surface(32, 32, 0, 0, 0);
	order_image(a, 65500);
	print(max_current_image_order());
#endif
end
