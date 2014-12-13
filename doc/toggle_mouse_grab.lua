-- toggle_mouse_grab
-- @short: Switch the lock state of the mouse device.
-- @inargs: *optmode*
-- @outargs: grabstate
-- @longdescr: For some control schemes, it's important to prevent mouse input from
-- being dropped due to window managers in the underlying OS. This function allows
-- you to toggle this state (or explicitly set it to MOUSE_GRABON or MOUSE_GRABOFF).
-- Calling this function always return the current active state.
-- @note: always provide escape options for the user to disable grab in order to
-- allow poor desktop environments to recover in the event of a live-lock.
-- @group: iodev
-- @cfunction: mousegrab
function main()
#ifdef MAIN
	print( tostring( toggle_mouse_grab() ) );
	print( tostring( toggle_mouse_grab() ) );
	print( tostring( toggle_mouse_grab(MOUSE_GRABON) ) );
	print( tostring( toggle_mouse_grab(MOUSE_GRABOFF) ) );
#endif

#ifdef ERROR
	toggle_mouse_grab(100);
#endif
end
