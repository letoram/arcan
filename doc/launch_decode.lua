-- launch_decode
-- @short: Launch a video decoding frameserver
-- @inargs: string:resource, func:callback(vid:source,strtbl:status)
-- @inargs: string:resource, string:opts, func:callback(vid:source,strtbl:status)
-- @inargs: nil, string:opts, func:callback(vid:source, strtbl:status)
-- @outargs: vid, aid
-- @longdescr: Spawn a new decode frameserver process, with input resource
-- defined by *resource*. the *callback* function behaves similarly to that
-- of ref:launch_target. If *opts* is provided it will be processed based on
-- the capabilities of the decode frameserver. These can be viewed by runnning
-- it from a command-line, like: ARCAN_ARG=help afsrv_decode.
--
-- Due to an unfortunate legacy, certain *resource* names are reserved for
-- special purposes and are prefixed as device:, capture: and stream:.
-- @group: targetcontrol
-- @cfunction: launchdecode
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
