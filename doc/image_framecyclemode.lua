-- image_framecyclemode
-- @short: Switch how object frameset properties are managed.
-- @inargs: vid, *mode* 
-- @longdescr: Framesets associated with an object can have its active_frame 
-- property vary with other engine states. By setting *mode* till 0 (disable)
-- only activeframe can alter the active frame property. With mode < 0 the
-- active frame will be cycled (rotate-right) every n logical frames. 
-- Mode > 0 is only defined for images with a feed function attached (e.g.
-- frameserver connections) and means to step every n times the feed function
-- provides an update. 
-- @note: If you want the behavior of stepping each rendered frame, do this 
-- manually by implementing the themename_frame_pulse and calling image_activeframe 
-- rather than relying on a framecyclemode.
-- @group: image
-- @cfunction: arcan_lua_framesetcycle
-- @related: image_framesetsize, image_activeframe, set_image_as_frame
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(64, 64, 0, 255, 0);
	c = fill_surface(64, 64, 0, 0, 255);
	
	image_framesetsize(a, 3);
	set_image_as_frame(a, b, 1);
	set_image_as_frame(a, c, 2);
	image_framecyclemode(a, -1);
#endif
end
