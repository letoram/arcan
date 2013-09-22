-- image_children
-- @short: List the objects in a context that has the specified object as a direct parent
-- @inargs: vid
-- @outargs: vidtbl
-- @longdescr: 
-- @note: The scan is not recursive, so only first-level children will be listed.
-- @group: image 
-- @cfunction: arcan_lua_imagechildren
-- @related: image_parent
function main()
#ifdef MAIN
	a = null_surface(1, 1);
	b = null_surface(1, 1);
	c = null_surface(1, 1);
	link_image(b, a);
	link_image(c, b);
	tbl = image_children(a);
	for i,v in ipairs(tbl) do
		print(v);
	end
#endif

#ifdef ERROR1
	image_childen(BADID);
#endif
end
