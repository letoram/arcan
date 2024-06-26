-- simple script to set music / audio playback
-- keys used:
-- a. fade background music to 0
-- b. fade background music to 1
-- c. quick- play sample
-- d. spawn 'background.ogg' stream
-- e. kill background music

sample_countdown = 0;
sample = load_asample("soundtest.wav");
playback = sample;
audio_ref = WORLDID
position = {0, 0, 0}

bgmusic_id = 0;
symtable = {}
local tones = {
	440.0,
	466.16,
	493.88,
	523.25,
	554.37,
	587.33,
	622.25,
	659.26,
	698.46,
	739.99,
	783.99,
	830.61
}

local function build_sine(freq, length)
	local step = 2 * math.pi * freq / 48000.0
	local samples = length * 48000.0
	local res = {}
	local val = 0

	for i=1,samples,1 do
		res[i] = math.sin(val)
		val = val + step
	end

	return res
end

function soundtest()
	local sfun = system_load("builtin/keyboard.lua");
	symtable = sfun();

	for i=1,#tones do
		local tbl = build_sine(tones[i], 10)
		tones[i] = load_asample(1, 48000, tbl)
	end

	vid = render_text(
	[[\ffonts/default.ttf,14\#ffffffSoundtest:\n\r\bKey:\tAction:\!b\n\r]] ..
	[[(1..9)\tset sample to tone\n\r]] ..
	[[c     \tset sample to wav\n\r]] ..
	[[d     \tqueue sample\n\r]] ..
	[[p     \tplaback sample\n\r]] ..
	[[f     \tenable positional audio\n\r]] ..
	[[arrows\tmove sample position in XZ plane\n\r]] ..
	[[m     \tplay background music (test.mp3)\n\r]] ..
	[[g     \tfix audio at 0,0,0\n\r]],
	[[ESCAPE\tshutdown\n\r]]
	);

	playback = sample
	show_image(vid);
end

local function move_audio(dx, dy, dz)
	position[1] = position[1] + dx
	position[2] = position[2] + dy
	position[3] = position[3] + dz
	if audio_ref ~= WORLDID then
		move3d_model(audio_ref, position[1], position[2], position[3])
	end
	print(position[1], position[2], position[3])
end

local queue = {}
function queue_next()
	print("sample over, queue: ", #queue)
	local ent = table.remove(queue)
	if not ent then
		return
	end
	play_audio(ent, queue_next)
end

function soundtest_input( inputtbl )
	if (inputtbl.kind == "digital" and inputtbl.active and inputtbl.translated) then
		local sym = symtable.tolabel(inputtbl.keysym)
		local num = tonumber(sym)

		if num and tones[num] then
			playback = tones[num]
			print("playback set to", num)
			if #queue > 0 then
				print("queued")
				table.insert(queue, playback)
			end

		elseif sym == "UP" then
			move_audio(0, 0, 10)
		elseif sym == "DOWN" then
			move_audio(0, 0, -10)
		elseif sym == "LEFT" then
			move_audio(-10, 0, 0)
		elseif sym == "RIGHT" then
			move_audio(10, 0, 0)

		elseif sym == "c" then
			playback = sample

		elseif sym == "d" then
			table.insert(queue, playback)

		elseif sym == "f" then
			if audio_ref ~= WORLDID then
				print("disable positional audio")
				delete_image(audio_ref)
				audio_ref = WORLDID
				position = {0, 0, 0}
			else
				audio_ref = null_surface(1, 1)
				move_audio(0, 0, 0)
			end

		elseif sym == "p" then
			audio_position(playback, audio_ref)
			play_audio(playback, 1.0, queue_next)

		elseif sym == "m" then
			print("enable bgm")
			local vid, aid = launch_decode("test.mp3", function() end)
			if valid_vid(vid) then
				audio_position(aid, audio_ref)
				move_audio(0, 0, 0)
			end

		elseif (sym == "f") then
		    if (sample_countdown > 0) then
			sample_countdown = 0;
			print("disabling sample spam");
		    else
			print("enabling sample spam");
			sample_countdown = 15;
		    end

		elseif  (sym == "ESCAPE") then
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
