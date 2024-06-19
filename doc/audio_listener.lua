-- audio_listener
-- @short: Bind the current device listener to a positioner video object
-- @inargs: vid:reference
-- @outargs:
-- @note: The actual effect will depend on your hardware and audio platform build
-- configuration.
-- @longdescr: This is used in tandem with ref:audio_position to provide spatial audio.
-- The referenced object position, orientation and transforms will translate
-- and apply to the listener position in the audio space.
-- @group: audio
-- @cfunction: audiolisten
-- @related: audio_position
function main()
#ifdef MAIN
	local ref = null_surface(1, 1)
	local aid = load_asample("test.wav")

	move3d_model(ref, 0, 100, 0, 500)
	rotate3d_model(ref, 45, 45, 45, 500)
	audio_listener(ref)

#endif

#ifdef ERROR1
#endif
end
