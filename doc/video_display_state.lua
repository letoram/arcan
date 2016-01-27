-- video_display_state
-- @short: Change power state for a display
-- @inargs: id, *state*
-- @outargs: statestr
-- @longdescr: This function is intended for nativ video platforms that expose
-- raw video display control (and for _lwa builds, a switch to enable/disable
-- render passes while maintaining other parts of the pipeline). Note that the
-- function returns a human readable string representing the current state,
-- but the optional *state* argument expects one of the following constants:
-- DISPLAY_OFF, DISPLAY_ON, DISPLAY_SUSPEND, DISPLAY_STANDBY
-- any other value is a terminal state transition. The *id* value for a display
-- can be retrieved in the event handler for _display_state(action, id).
-- @group: vidsys
-- @cfunction: videodpms
-- @related:
function main()
#ifdef MAIN
	print(video_display_state(0));
	print(video_display_state(0, DISPLAY_OFF));
	print(video_display_state(0, DISPLAY_ON));
#endif

#ifdef ERROR1
	video_display_state(0, -123);
#endif
end
