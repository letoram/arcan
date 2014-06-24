-- audio_gain
-- @short: Changes the audio gain for a specific audio object.
-- @inargs: aid, gain, *time
-- @outargs:
-- @longdescr: Each audio object has a separate gain property clamped to the 0..1 range,
-- which is set to 1.0 by default when an object is loaded or created. The optional *time*
-- argument applies a fade from the old gain to the new one, the interpolation used is
-- undefined and implementation specific.
-- @note: Any value outside the particular range will be clamped.
-- @note: For the cases where the engine is responsible for pushing the audio to the target device, even a gain of 0.0 will generate data due to some buffering restrictions with underlying APIs.
-- @note: There's a logarithmic distribution applied internally to better mimic the linear appearance used in other sound interfaces.
-- @group: audio
-- @cfunction: arcan_lua_gain
-- @flags:
function main()
	local asrc = load_asample("sample.wav");

#ifdef MAIN
	audio_gain(asrc, 0.0, 100);
#endif

#ifdef ERROR1
	audio_gain(asrc, -1.0, -1);
#endif

	play_audio(asrc);
end
