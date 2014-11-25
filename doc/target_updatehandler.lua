-- target_updatehandler
-- @short: Change the active callback for a VID connected to a frameserver.
-- @inargs: vid, *callback_function*
-- @longdescr: Every frameserver can have one active Lua function as a
-- callback. This callback receives events related to the associated
-- frameserver. In some cases, one might want to update or replace
-- the function associated with a specific frameserver connected VID,
-- e.g. when adopting as part of a system collapse or fallback script.
-- @note: if *callback_function* is set to nil, frameserver related
-- events will be silently dropped, except for special cases that
-- are handled internally (see event_queuetransfer in engine/arcan_event.c).
-- @group: targetcontrol
-- @cfunction: targethandler
-- @alias: image_updatehandler
-- @related:
function main()
#ifdef MAIN
	a = launch_avfeed("", "avfeed", function(source, status)
		print("in first handler");
		target_updatehandler(source; function()
			print("in second handler");
		end);
	end);
#endif

#ifdef ERROR1
	a = launch_avfeed("", "avfeed", function() end);
	target_updatehandler(a, target_updatehandler);
#endif
end
