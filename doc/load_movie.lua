-- load_movie
-- @short: Launch a video decoding frameserver 
-- @inargs: resstr, looparg, callback
-- @outargs: vid, aid
-- @longdescr: Spawn a new video decoding frameserver in a separate process and request that
-- resstr should be opened and decoded. Looparg can be either FRAMESERVER_LOOP or FRAMESERVER_NOLOOP, and determines what the frameserver should do when playback is finished or terminated abruptly. 
-- With LOOP, a new process will be launched, 
-- re-using as much resources of the old one as possible. 
-- @note: If the frameserver dies too quickly (threshold on a second or two repeatedly), the looping behavior will stop.
-- @note: this function also accepts device:, capture: and stream: arguments. 
-- @group: targetcontrol 
-- @cfunction: arcan_lua_loadmovie
-- @related: play_movie
function main()
#ifdef MAIN
	vid = load_movie("test.avi", FRAMESERVER_LOOP, function(source, status)
		print(status.kind);
		play_movie(source);
	end);
	show_image(vid);
	resize_image(vid, VRESW, VRESH);
#endif
end
