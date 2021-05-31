-- image_parent
-- @short: Return a reference to the parent object.
-- @inargs: vid:src
-- @inargs: vid:src, vid:reference
-- @longdescr: This function is used to figure out if *vid* is
-- linked to another object from a previous call to ref:link_image
-- and which primary attachement the image has. This is normally
-- WORLDID, but can be another vid through any of the
-- ref:define_rendertarget class of functions.
-- If the *reference* argument is provided, the function will
-- only return if *src* is a decendent of *reference*. and the
-- *parentvid* will match *reference*.
-- @group: image
-- @related: image_children, link_image, valid_vid
-- @cfunction: imageparent
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = fill_surface(32, 32, 255, 0, 0);
	c = fill_surface(32, 32, 255, 0, 0);
	link_image(c, a);
	image_tracetag(a, "(a)");
	print(image_tracetag(image_parent(b)));
	print(image_tracetag(image_parent(c)));
	print(image_tracetag(image_parent(a)));
#endif

#ifdef MAIN2
 a = fill_surface(32, 32, 255, 0, 0)
 b = fill_surface(32, 32, 255, 0, 0)
 c = fill_surface(32, 32, 255, 0, 0)
 d = fill_surface(32, 32, 255, 0, 0)
 link_image(a, b)
 link_image(b, c)
 print(image_parent(a, b))
 print(image_parent(a, c))
 print(image_parent(a, d)) -- not a parent
#endif

#ifdef ERROR
	print(image_parent(BADID));
#endif

#ifdef ERROR2
	print(image_parent(WORLDID));
#endif
end
