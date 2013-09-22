-- image_framecyclemode
-- @short: Switch how object frameset properties are managed.
-- @inargs: vid, *mode* 
-- @outargs: Framesets associated with an object can have its active_frame 
-- property vary with other engine states. By setting *mode* till 0 (disable)
-- only activeframe can alter the active frame property. With mode < 0 the
-- active frame will be cycled (rotate-right) every n logical frames. With
-- mode > 0, the active frame will be cycled (rotate-right) every n rendered
-- frame.
-- @longdescr
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
