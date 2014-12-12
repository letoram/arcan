-- pause_audio
-- @short: Temporarily pause device playback from the stream connected with an AID.
-- @inargs: aid
-- @group: audio
-- @cfunction: pauseaudio
-- @related: play_audio
-- @note: the streaming audio behavior is deprecated and replaced with the
-- use of regular video decoding frameservers (load_movie etc.) that comes
-- with its own playback control functions.
-- @flags: deprecated
function main()
#ifdef MAIN
#endif
end
