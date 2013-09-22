-- load_asample
-- @short: Preload an audio sample for later/repeated playback. 
-- @inargs: resname, *startgain*  
-- @outargs: aid 
-- @group: audio 
-- @note: only 1,2ch (8,16) RIFF/WAV PCM, (44100, 22050 or 11025) samples supported. 
-- @cfunction: arcan_lua_loadasample
-- @related: play_audio
function main()
#define MAIN
	aid = load_asample("test.wav", 0.5);
	play_audio(aid);
#endif
end
