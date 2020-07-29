-- load_asample
-- @short: Preload an audio sample for later/repeated playback.
-- @inargs: string:resource, number:gain
-- @inargs: int:channels=2, tblfloat:values
-- @inargs: int:channels=2, int:rate=48000, tblfloat:values
-- @inargs: int:channels=2, int:rate=48000, string:format="stereo", tblfloat:values
-- @outargs: aid
-- @group: audio
-- @longdescr:
-- This function is used to creata short audio samples that can be triggered
-- repeatedly, usable for sound effects and audio feedback to user events.
-- There are two forms to this function, the first one where a resource with a
-- RIFF/WAV file backing where the format defines the parameters.
-- The other is for caller supplied buffer of normalised, interleaved float values
-- in the -1..1 range. The optional 'format' controls the interpretation of the
-- values, where current possible formats are 'stereo' and 'mono'.
-- @cfunction: loadasample
-- @related: play_audio
function main()
#ifdef MAIN
	aid = load_asample("test.wav", 0.5);
	play_audio(aid);
#endif
end
