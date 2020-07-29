-- play_audio
-- @short: Play an audio sample
-- @inargs: aid:sample
-- @inargs: aid:sample, number:gain
-- @inargs: aid:sample, number:gain, function:callback()
-- @inargs: aid:sample, function:callback()
-- @longdescr: This function is used to control audio playback. When called
-- it issues a new playback of the specified audio sample that has previously
-- been loaded or synthesised using ref:load_asample.
--
-- The argument form where a *gain* is supplied will override any global gain
-- settings on the output device through WORLDID.
--
-- If a callback is provided, it will be triggered as soon as the underlying
-- audio stack tells us that playback of the sample has finished. This is
-- intended as a way of sequencing playback samples together.
--
-- Multiple playbacks of the same samples can be running at the same time,
-- limited by the mixing capabilities of the underlying driver stack as well
-- as a compile-time engine limit (32 by default).
--
-- If a sample fails to queue or mix properly, the function will return false.
-- @group: audio
-- @cfunction: playaudio
-- @related: pause_audio, delete_audio, load_asample, audio_gain
function main()
#ifdef MAIN
	local aid = load_asample("test.wav");
	play_audio(aid, 0.5);
	play_audio(aid, function() print("done"); end)
#endif

#ifdef ERROR
	play_audio(fill_surface(32, 32, 0, 0, 0), 0.5);
#endif
end
