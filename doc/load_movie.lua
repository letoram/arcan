-- load_movie
-- @short: Launch a video decoding frameserver
-- @inargs: resstr, [optarg], callback
-- @outargs: vid, aid
-- @longdescr: Spawn a new video decoding frameserver in a separate process
-- and request that resstr should be opened and decoded. If *optarg* is
-- not set to an argument string to pass to the decode frameserver,
-- the second argument to load_movie will be the callback function.
-- @note: resstr can also be device:, capture: and stream: arguments.
-- @note: for details on optarg, see the man page for arcan_frameserver_decode
-- @group: targetcontrol
-- @cfunction: arcan_lua_loadmovie
-- @related: launch_avfeed
function main()
#ifdef MAIN
	vid = load_movie("test.avi", function(source, status)
		print(status.kind);
	end);
	show_image(vid);
	resize_image(vid, VRESW, VRESH);
#endif
end
