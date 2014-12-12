-- capture_audio
-- @short: Setup an audio device capture stream
-- @inargs: devstr
-- @outargs: AID or NIL
-- @longdescr: This function is used for mapping an external capture device (e.g. a microphone) to an AID that can be used for monitoring (like forwarding to a recordtarget or a frameserver that does audio processing for voice recognition and similar features).
-- @group: audio
-- @note: The device must be supported by the underlying sound support system (and emitt audio data that matches the compile-time defined format, e.g. 44100/16bit/2ch LE 16 samples) and must match a valid entry as provided by list_audio_inputs
-- @cfunction: captureaudio
-- @related: list_audio_inputs
-- @flags:
function main()
#ifdef MAIN
	a = list_audio_inputs();
	b = capture_audio(a[1]);
#endif

#ifdef ERROR
	b = capture_audio(-1);
#endif
end
