-- list_audio_inputs
-- @short: Retrieve a list of available audio input devices. 
-- @outargs: ainptbl 
-- @group: audio 
-- @cfunction: arcan_lua_capturelist
-- @related: capture_audio
function main()
#define MAIN
	print("begin list of audio devices");
	for i,v in ipairs(list_audio_inputs()) do
		print(v);
	end
	print("end of list of audio devices");
#endif
end
