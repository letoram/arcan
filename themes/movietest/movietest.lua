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
	local symfun = system_load("scripts/symtable.lua");
	symtable = symfun();

	local text_vid = render_text( [[\ffonts/default.ttf,14\#ffffffMovietest:\n\r\bKey:\tAction:\!b\n\r]] ..
	[[\is\t\b\!is\!bpawn movie instance at cursor\n\r]] ..
	[[p\t\b\!ip\!bause last spawned movie\n\r]] ..
	[[r\t\b\!ir\!besume playback on last spawned movie\n\r]] ..
	[[\iESCAPE\t\!ishutdown\n\r]] );

	sprop = image_surface_properties(text_vid);
	move_image(text_vid, VRESW - sprop.width, 0, 0);
	show_image(text_vid);

	debugbar_vid = fill_surface(1, 64, 0, 255, 0);
	debugbar_aid = fill_surface(1, 64, 0, 0, 255);

	move_image(debugbar_vid, 0, VRESH - 128, 0);
	move_image(debugbar_aid, 0, VRESH - 64,  0);
	show_image(debugbar_vid);
	show_image(debugbar_aid);	
	
	vid = load_movie("movietest.avi", 1, function(source, status)
		show_image(source);
		play_movie(source);
		print("callback");
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

function movietest_input( inputtbl )
	
	if (inputtbl.kind == "digital" and inputtbl.translated and inputtbl.active) then
		if (symtable[ inputtbl.keysym ] == "d") then
			
		elseif (symtable[ inputtbl.keysym ] == "s") then
			vid, aid = load_movie("movietest.avi");
			img.last = vid;
			move_image(vid, cursor.x, cursor.y);
			scale_image(vid, 0.3, 0.3);
			show_image(vid);
			
		elseif (symtable[ inputtbl.keysym ] == "p") then
			pause_movie(img.last);
			
		elseif (symtable[ inputtbl.keysym] == "r") then
			resume_movie(img.last);
		elseif (symtable[ inputtbl.keysym] == "ESCAPE") then
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

function movietest_video_event(source, ev)
	if (ev.kind == "moviestatus") then
		resize_image(debugbar_vid, VRESW * (ev.curv / ev.maxv), 64);
		resize_image(debugbar_aid, VRESW * (ev.cura / ev.maxa), 64);
	elseif (ev.kind == "movieready") then
		show_image(source);
		play_movie(source);
	end	
end

function movietest_clock_pulse()
    move_image(img.cursor, cursor.x, cursor.y);
end

