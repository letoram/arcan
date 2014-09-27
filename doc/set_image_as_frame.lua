-- set_image_as_frame
-- @short: Specify the contents of a multi-frame object.
-- @inargs: contvid, srcvid, index, *detach*
-- @longdescr: Objects can be turned into multi-frame objects by calling
-- image_framesetsize which will allocate a static number of slots for
-- attaching objects. By default, these refer back to the source object,
-- but each slot can be filled with an object using the set_image_as_frame
-- function. If detach is set to FRAMESET_NODETACH (default) srcvid will
-- behave as a normal object. If detach is set to FRAMESET_DETACH however,
-- its hierarchical parent will be set to contvid and will no-longer be
-- rendered on its own.
-- @group: image
-- @cfunction: arcan_lua_imageasframe
-- @related: image_framesetsize, image_framecyclemode, image_active_frame
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	image_framesetsize(a, 3);
	b = fill_surface(32, 32, 0, 255, 0);
	c = fill_surface(32, 32, 0, 0, 255);
	set_image_as_frame(a, b, 1);
	set_image_as_frame(a, c, 2);
	image_framecyclemode(1, -1);
	show_image(a);
#endif
end
