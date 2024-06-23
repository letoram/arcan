-- audio_outputs
-- @short: Returns a list of possible device names for audio_reconfigure
-- @inargs:
-- @outargs: strtbl
-- @longdescr: This function queries the audio platform for outputs that
-- can be chosen to be the default that the current context plays to.
-- @group: audio
-- @cfunction: audioout
-- @related:
function main()
#ifdef MAIN
	for i,v in ipairs(audio_outputs) do
		print(i, v)
	end
#endif

#ifdef ERROR1
#endif
end
