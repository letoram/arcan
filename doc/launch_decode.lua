-- launch_decode
-- @short: Launch a video decoding frameserver
-- @inargs: resstr, [optarg], callback(source,status)
-- @outargs: vid, aid
-- @longdescr: Spawn a new video decoding frameserver in a separate process
-- and request that resstr should be opened and decoded. If *optarg* is not
-- set to an argument string to pass to the decode frameserver, the second
-- argument to launch_decode will be the callback function.
-- The possible contents of the status argument to the *callback* function
-- are described in ref:launch_target.
-- @note: resstr can also be device:, capture: and stream: arguments.
-- @note: for details on optarg, see the man page for afsrv_decode or run
-- it without any arguments from the command-line.
-- @group: targetcontrol
-- @cfunction: loadmovie
-- @related:
function main()
#ifdef MAIN
	vid = launch_decode("test.avi", function(source, status)
		print(status.kind);
	end);
	show_image(vid);
	resize_image(vid, VRESW, VRESH);
#endif
#ifdef ERROR1
	vid = launch_decode("test.avi", launch_decode);
#endif
end
