-- simple script to test most cases of movie management;
-- a. playback -> end -> cleanup ev.
-- b. playback -> loop (inf.) (try to kill the frameserver process)
-- c. multiple playback (press 's' to spawn a movie (with low gain, 0.1) at the mouse-cursor
-- d. pause / resume, press 'p' to pause last spawned movie id
--
-- "movietest" files to try;
-- common containers -- avi, mpg, mng, mkv, flv
-- hires source (1080p is max)
-- silent source (no audio stream)
-- invisible source (no video stream)
--
-- note that the movie support here is really intended for preview- style playback,
-- anything else should be done through a proper player as an external launch
--
-- frameserver should be expanded to cover webcam devices as well, along with "inverse"
-- frameserving, meaning to send a specific vid/aid at a fixed sample-rate to the frameserver
--
img = {};
cursor = {x = 0, y = 0};
symtable = {}

function movietest()
	local symfun = system_load("builtin/keyboard.lua");
	symtable = symfun();

	local text_vid = render_text( [[\ffonts/default.ttf,14\#ffffffMovietest:\n\r\bKey:\tAction:\!b\n\r]] ..
	[[\is\t\b\!is\!bpawn movie instance at cursor\n\r]] ..
	[[p\t\b\!ip\!bause last spawned movie\n\r]] ..
	[[r\t\b\!ir\!besume playback on last spawned movie\n\r]] ..
	[[w\t\b\!iw\!bebcam session\n\r]] ..
	[[\iESCAPE\t\!ishutdown\n\r]] );

	sprop = image_surface_properties(text_vid);
	move_image(text_vid, VRESW - sprop.width, 0, 0);
	show_image(text_vid);

	webcam_ind = 0

	vid = launch_decode("movietest.avi",
	function(source, statustbl)
		if (statustbl.kind == "resized") then
			show_image(source)
			resize_image(source, statustbl.width, statustbl.height);
		end
	end);
	img.last = vid;
	img.cursor = fill_surface(16, 16, 200, 50, 50);
	order_image(img.cursor, 255);
	show_image(img.cursor);

	if (vid == 0) then
		print("movietest.avi not found -- shutting down");
		shutdown();
	end
end

function movietest_on_show()
end

function movietest_frameserver_event(source, tbl)
	print("uncatched frameserver event(",source,tbl.kind,")");
	if (tbl.kind == "bufferstatus") then
		resize_image(debugbar_vid, VRESW * (ev.curv / ev.maxv), 64);
		resize_image(debugbar_aid, VRESW * (ev.cura / ev.maxa), 64);
	elseif (tbl.kind == "resized") then
		resize_image(source, tbl.width * 0.3, tbl.height * 0.3);
		show_image(source);
		play_movie(source);
	end
end

function movietest_input( inputtbl )

	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		local label = symtable.tolabel(inputtbl.keysym)
		if (label == "d") then

		elseif (label == "s") then
			vid, aid = launch_decode("movietest.avi");
			img.last = vid;
			move_image(vid, cursor.x, cursor.y);
			show_image(vid);

		elseif (label == "p") then
			pause_movie(img.last);

		elseif (label == "w") then
			width = 128 + math.random(1024);
			height = 128 + math.random(1024);
			print("Requesting:", "capture:" .. webcam_ind, tostring(width) .. "x" .. tostring(height));
vid, aid = launch_decode("capture:device=" .. webcam_ind .. ":width=" .. tostring(width) .. ":height=" .. tostring(height), FRAMESERVER_NOLOOP,
function(source, status)
	print("webcam status:", status.kind);
	if (status.kind == "resized") then
		print("resize to: ", status.width, status.height);
		resize_image(source, status.width, status.height);
	end
end );
			webcam_ind = webcam_ind + 1;
			move_image(vid, cursor.x, cursor.y);
			show_image(vid);

		elseif (label == "r") then
			resume_movie(img.last);
		elseif (label == "ESCAPE") then
			shutdown();
		end

	elseif (inputtbl.kind == "analog" and inputtbl.source == "mouse") then
		if inputtbl.subid == 0 then
		    cursor.x = inputtbl.samples[1];
		else
		    cursor.y = inputtbl.samples[1];
		end
	end
end

function movietest_clock_pulse()
    move_image(img.cursor, cursor.x, cursor.y);
end

