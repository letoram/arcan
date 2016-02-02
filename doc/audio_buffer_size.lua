-- audio_buffer_size
-- @short: Change the default audio buffering size
-- @inargs: newsz
-- @outargs: oldsz
-- @longdescr: Some audio sources in combination with some audio outputs
-- may lead to undesirable audio artifacts (noise, cracking or poping) or
-- unbearably long latency when synchronized with a video source. This can
-- be regulated to some degree by suggesting a different size for chunks
-- being passed to the audio output. This value is applied whenever a
-- frameserver performs a resize operation. *newsz* is specified in bytes.
-- @note: Trying to set a low size may cause a warning in the log and the
-- actual value set being changed somewhat. Same applies to values that do
-- not align with underlying audio sample size.
-- @note: Setting *newsz* to 0 will not change the buffer size, only return the
-- current value.
-- @group: audio
-- @cfunction: abufsz
-- @related:
function main()
#ifdef MAIN
#endif

#ifdef ERROR1
#endif
end
