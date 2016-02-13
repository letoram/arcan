-- image_parent
-- @short: Return a reference to the parent object.
-- @inargs: vid
-- @longdescr: This function is used to figure out if *vid* is
-- linked to another object from a previous call to ref:link_image
-- and which primary attachement the image has (typically WORLID
-- unless it has been explicitly attached to another rendertarget).
-- @outargs: parentvid, attachvid
-- @group: image
-- @related: image_children, link_image, valid_vid
-- @cfunction: imageparent
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

#ifdef ERROR
	print(image_parent(BADID));
#endif

#ifdef ERROR2
	print(image_parent(WORLDID));
#endif
end
