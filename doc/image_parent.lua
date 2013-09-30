-- image_parent
-- @short: Return a reference to the parent object.
-- @inargs: vid 
-- @outargs: parentvid
-- @group: image 
-- @related: image_children, link_image, valid_vid  
-- @cfunction: arcan_lua_imageparent
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = instance_image(a);
	c = fill_surface(32, 32, 255, 0, 0);
	link_image(c, a);
	image_tracetag(a, "(a)");
	print(image_tracetag(image_parent(b)));
	print(image_tracetag(image_parent(c)));
	print(image_tracetag(image_parent(a)));
#endif

#ifdef ERROR1
	print(image_parent(BADID));
#endif

#ifdef ERROR2
	print(image_parent(WORLDID));
#endif
end
