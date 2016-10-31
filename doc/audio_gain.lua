-- audio_gain
-- @short: Retrieve and/or update the audio gain for a specific audio object.
-- @inargs: aid, *gain*, *time*
-- @outargs: aid_gain
-- @longdescr: Each audio object has a separate gain property clamped to the 0..1 range,
-- set to 1.0 by default when an object is loaded or created. The optional *gain* argument
-- will update this for a specific audio source. The optional *time*
-- argument applies a fade from the old gain to the new one, the interpolation function
-- used is implementation defined.
-- @note: Any value outside the particular range will be clamped.
-- @note: AID 0 is reserved for changing the default gain for new sources.
-- @note: For the cases where the engine is responsible for pushing the audio
-- @note: The gain value returned is the target gain, with a pending transformation,
-- this state may not have been reached yet.
-- to the target device, even a gain of 0.0 will generate data due to some
-- buffering restrictions with underlying APIs.
-- @note: There's a logarithmic distribution applied internally to better
-- mimic the linear appearance used in other sound interfaces.
-- @group: audio
-- @cfunction: gain
-- @flags:
function main()
	local asrc = load_asample("sample.wav");

#ifdef MAIN
	audio_gain(asrc, 0.0, 100);
#endif

#ifdef ERROR
	audio_gain(asrc, -1.0, -1);
#endif

	play_audio(asrc);
end
