-- play_audio
-- @short: Playback a preloaded sample 
-- @inargs: aid, *gain*
-- @longdescr: Samples can be preloaded through the use load_asample. These
-- can then be played back using this function. Multiple play calls on the same
-- aid in rapid succession will have the sample playback being repeated.
-- @note: While the sample may have a different gain associated with it
-- or with audio transformations queued. If a gain value is specified as second
-- argument, that gain will take precendence.
-- @planned: A/V synch issues in framebuffer may lead to situations where
-- video lags behind audio. Calling play_audio on the aid with a frameserver
-- connection, or similar, should have the internal buffer flushed.
-- @group: audio 
-- @cfunction: arcan_lua_playaudio
-- @related: pause_audio, delete_audio, load_asample, audio_gain
function main()
#ifdef MAIN
	local aid = load_asample("test.wav");
	play_audio(aid, 0.5);
#endif

#ifdef ERROR1
	play_audio(fill_surface(32, 32, 0, 0, 0), 0.5);
#endif
end
