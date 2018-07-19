function vidtag()
	fname = arguments[1];
	vfc = 0;
	symtable = system_load("builtin/keyboard.lua")();
	timestamp = benchmark_timestamp();

	movie = load_movie(fname, FRAMESERVER_NOLOOP, function(source, status)
		if (status.kind == "resized") then
			play_movie(movie);
			show_image(movie);
			resize_image(movie, VRESW, VRESH);
		end
	end);

end

function vidtag_frame_pulse()
	vfc = vfc + 1;

	if (valid_vid(textstr)) then
		delete_image(textstr);
	end

-- vfc + 1 as the textstr won't be visible until next frame
	textstr = render_text(string.format(
		[[\ffonts/default.ttf,18\#ffffff frame: %d\n\rtimestamp: %d]], vfc+1,
			benchmark_timestamp() - timestamp)
	);

	show_image(textstr);
	if (valid_vid(rendertgt)) then
		rendertarget_attach(rendertgt, textstr, RENDERTARGET_DETACH);
	end
end

function start_recording()
	if (valid_vid(rendertgt)) then
		warning("Already recording.\n");
		return;
	end

	local ind   = 0;
	local outfn = "";

	repeat
		outfn = string.format("%s_%d.mkv", arguments[1], ind);
		ind = ind + 1;
	until (not resource( outfn ));

	rendertgt = fill_surface(VRESW, VRESH, 0, 0, 0, VRESW, VRESH);
	define_recordtarget(rendertgt, outfn,
		"container=mkv:vcodec=H264:fps=60:vpreset=8:noaudio",
		{movie}, {}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1);

	show_image(rendertgt);
end

function vidtag_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.translated and iotbl.active) then
		sym = symtable[iotbl.keysym];

		if (sym == " ") then
			start_recording();

		elseif (sym == "ESCAPE") then
			shutdown();
		end
	end
end
