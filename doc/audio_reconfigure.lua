-- audio_reconfigure
-- @short: Control audio device output parameters
-- @inargs:
-- @inargs: cfgtbl
-- @outargs: int:device
-- @longdescr: This function lets you reconfigure and enable/disable certain
-- audio parameters. This might cause a buffering reset and queued samples
-- might be lost depending on the configuration change.
--
-- The returned *device* specifies new/old audio device identifier that
-- can be used to re-assign audio sources to a newly assigned sink.
--
-- This function is mainly a hrtf toggle for the time being, thus marked
-- experimental. Eventually it will become the control surface for handling
-- hotplug events and enabling/disabling specific audio outputs.
--
-- @tblent: bool:hrtf enable or disable a head related transfer function.
-- This is dependent on the underlying audio platform, so currently no
-- option for specifying a more exact profile.
--
-- @tblent: string:output use a name from ref:audio_outputs and move
-- current context playback to this output. This is dependent on the
-- underlying audio platform, which may or may not support this.
--
-- @experimental
-- @group: audio
-- @cfunction: audioreconf
-- @related:
function main()
#ifdef MAIN
	audio_reconfigure({hrtf = true})
#endif

#ifdef ERROR1
#endif
end
