-- set_image_as_frame
-- @short: Specify the contents of a multi-frame object.
-- @inargs: contvid, srcvid, index
-- @longdescr: Objects can be turned into multi-frame objects by calling
-- image_framesetsize which will allocate a static number of slots for
-- attaching objects. By default, these refer back to the source object,
-- but each slot can be filled with an object using the set_image_as_frame
-- function. The behavior and restrictons for *srcvid* are similar to
-- image_sharestorage with the addition that the texture coordinate set
-- in use will also carry over.
-- @note: attempts at setting the image to a value larger than the number
-- of available slots will be ignored with a warning.
-- @group: image
-- @cfunction: imageasframe
-- @related: image_framesetsize, image_framecyclemode, image_active_frame,
-- image_sharestorage
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	image_framesetsize(a, 3);
	b = fill_surface(32, 32, 0, 255, 0);
	c = fill_surface(32, 32, 0, 0, 255);
	set_image_as_frame(a, b, 1);
	set_image_as_frame(a, c, 2);
	image_framecyclemode(1, 1);
	show_image(a);
#endif
end
