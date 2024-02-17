function vidtag()
	local arguments = appl_arguments()
	fname = arguments[1];
	vfc = 0;
	symtable = system_load("builtin/keyboard.lua")();
	timestamp = benchmark_timestamp();

	movie = launch_decode(fname,
	function(source, status)
		if (status.kind == "resized") then
			show_image(source);
			resize_image(source, VRESW, VRESH);
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

function start_recording(hw)
	if (valid_vid(rendertgt)) then
		warning("Already recording.\n");
		return;
	end

	local ind   = 0;
	local outfn = "";

	repeat
		outfn = string.format("%s_%d.mkv", fname, ind);
		ind = ind + 1;
	until (not resource( outfn ));

	rendertgt = fill_surface(640, 480, 0, 0, 0, 640, 480);
	local store = null_surface(640, 480);
	image_sharestorage(movie, store);

	local olay = color_surface(64, 64, 128, 255, 0);
	move_image(olay, 0, 0, 100);
	move_image(olay, 100, 0, 100);
	image_transform_cycle(olay, true);

	define_recordtarget(rendertgt, outfn,
		"container=mkv:vcodec=H264:fps=60:vpreset=8:noaudio",
		{store, olay}, {}, RENDERTARGET_DETACH, RENDERTARGET_NOSCALE, -1);

	if hw then
		rendertarget_forceupdate(rendertgt, -1, -1, true);
	end

	show_image(store);
	show_image(olay);
	order_image(olay, 10);
	show_image(rendertgt);
end

function vidtag_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.translated and iotbl.active) then
		sym = symtable.tolabel(iotbl.keysym);
		print(sym)

		if (sym == "F1") then
			print("request record");
			start_recording();

		elseif (sym == "F2") then
			print("request record with hwhandle");
			start_recording(true);

		elseif (sym == "ESCAPE") then
			shutdown();
		end
	end
end
