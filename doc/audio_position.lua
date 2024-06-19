-- audio_position
-- @short: Bind an audio source to a positioner video object
-- @inargs: aid:source, vid:reference
-- @outargs:
-- @longdescr: This function provides a binding between an audio source and a
-- video object that will be used to derive world-space position and orientation.
-- Any transforms of the *reference* object will translate to repositioning the
-- audio source as well.
-- @note: Binding to WORLDID will return the object to 0,0,0
-- @note: Referencing a bad audio *source* or video *reference* is a terminal
-- state transition.
-- @group: audio
-- @cfunction: audiopos
-- @related: audio_listener
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
