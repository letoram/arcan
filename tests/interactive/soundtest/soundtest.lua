-- simple script to set music / audio playback
-- keys used:
-- a. fade background music to 0
-- b. fade background music to 1
-- c. quick- play sample
-- d. spawn 'background.ogg' stream
-- e. kill background music

sample_countdown = 0;
sample = load_asample("soundtest.wav");
bgmusic_fname_ogg = "soundtest.ogg";
bgmusic_id = 0;
symtable = {}

function soundtest()
	local sfun = system_load("builtin/keyboard.lua");
	symtable = sfun();

	vid = render_text( [[\ffonts/default.ttf,14\#ffffffSoundtest:\n\r\bKey:\tAction:\!b\n\r]] ..
	[[a\tfade background music to 0\n\r]] ..
	[[b\tfade background music to 1\n\r]] ..
	[[c\tquick- play sample\n\r]] ..
	[[d\tspawn 'background.ogg' stream\n\r]] ..
	[[e\tkill background music\n\r]] ..
	[[f\tsample spam\n\r]] ..
	[[ESCAPE\tshutdown\n\r]] );

	show_image(vid);
end

function soundtest_on_show()
end

function soundtest_input( inputtbl )
	if (inputtbl.kind == "digital" and inputtbl.active and inputtbl.translated) then
		if (symtable[ inputtbl.keysym ] == "a") then
		    print("audio gain: 0.0 in 100 ticks\n");
		    audio_gain(bgmusic_id, 0.0, 100);

		elseif (symtable[ inputtbl.keysym ] == "b") then
		    print("audio gain: 1.0 in 100 ticks\n");
		    audio_gain(bgmusic_id, 1.0, 100);

		elseif (symtable[ inputtbl.keysym ] == "c") then
		    print("play sample\n");
		    play_audio(sample, 1.0);

		elseif (symtable[ inputtbl.keysym ] == "d") then
		    print("play " .. bgmusic_fname_ogg .. " stream\n");

		    if (bgmusic_id > 0) then
			delete_audio(bgmusic_id);
		    end

		    bgmusic_id = stream_audio(bgmusic_fname_ogg);
		    play_audio(bgmusic_id);
		    print(" => " .. bgmusic_id);

		elseif (symtable[ inputtbl.keysym ] == "f") then
		    if (sample_countdown > 0) then
			sample_countdown = 0;
			print("disabling sample spam");
		    else
			print("enabling sample spam");
			sample_countdown = 15;
		    end

		elseif (symtable[ inputtbl.keysym ] == "e") then
		    print("delete audio id : " ..bgmusic_id .. "\n");
		    delete_audio(bgmusic_id);
		    bgmusic_id = 0;
		elseif  (symtable[ inputtbl.keysym ] == "ESCAPE") then
		    shutdown();
		end
	end
end

function soundtest_clock_pulse()
	if (sample_countdown > 0) then
		sample_countdown = sample_countdown - 1;
		if (sample_countdown == 0) then
			play_audio(sample);
			sample_countdown = 15;
		end
	end
end

function soundtest_audio_event( source, argtbl )
  print(" [ Audio Event ]");
  print("-> source" .. source);
  print("-> kind" .. argtbl.kind);
  print(" [---  End  ---]");
  print(" ");
end
