-- image_children
-- @short: List the objects in a context that has the specified object as a direct parent
-- @inargs: vid, *searchvid*
-- @outargs: vidtbl or bool
-- @longdescr: This function provides either a list of immediate descendants
-- (images linked TO vid) or recursively scans and tests if vid is related to
-- *searchvid* (when provided).
-- @group: image
-- @cfunction: imagechildren
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

#ifdef MAIN2
	a = null_surface(1, 1);
	b = null_surface(1, 1);
	c = null_surface(1, 1);
	d = null_surface(1, 1);

	link_image(c, b);
	link_image(b, a);

	local positive = image_children(c, a);
	local negative = image_children(d, a);

	print(positive, negative);
#endif

#ifdef ERROR
	image_childen(BADID);
#endif
end
