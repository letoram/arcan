-- image_framecyclemode
-- @short: Switch how object frameset properties are managed.
-- @inargs: vid, *mode*
-- @longdescr: Framesets associated with an object can have its active_frame
-- property vary with other engine states. By setting *mode* to 0 (disable)
-- only activeframe can alter the active frame property. Otherwise,
-- the active frame will be cycled (increment active index) every n logical
-- frames. For framesets where the containing object, this means that the
-- destination store will change every n new frames instead.
-- @note: If you want the behavior of stepping each rendered frame, do this
-- manually by implementing the applname_frame_pulse and calling
-- image_activeframe rather than relying on a framecyclemode.
-- @group: image
-- @cfunction: framesetcycle
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
