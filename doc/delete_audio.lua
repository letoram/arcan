-- delete_audio
-- @short: Remove the audio source
-- @inargs: aid
-- @outargs:
-- @note: This is undefined for frameserver audio sources as
-- frameserver lifecycle management is tied to the video id
-- @group: audio
-- @cfunction: dropaudio
-- @related: play_audio, pause_audio, audio_gain
function main()
#ifdef MAIN
	a = load_asample("test.wav");
	play_audio(a);
	audio_gain(a, 0.0);
	audio_gain(a, 1.0, 20);
#endif
#ifdef ERROR
	a = load_movie("test.avi", FRAMESERVER_NOLOOP, function(source, stat)
		if (stat.kind == "resized") then
			delete_audio(stat.source_audio);
		end
	end);
#endif
end
