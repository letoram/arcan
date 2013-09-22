-- launch_target
-- @short: Setup and launch an external program.
-- @inargs: gameid, mode, *handler*
-- @outargs: *vid*
-- @longdescr: This function first resolves properties (execution environment),
-- and, depending on if mode is set to LAUNCH_EXTERNAL or LAUNCH_INTERNAL:
-- (EXTERNAL) deallocate as much resources as possible by saving the current
-- context (push to the context stack), disables audio/video/event subsystems, etc. 
-- executes the target and waits for it to finish.
-- (INTERNAL) setup a shared memory- based interface and map that as a frameserver
-- that feeds a video object. Launch the specified target (either as a semi-trusted
-- frameserver process or as a hijacked process), poll for changes / updates and feed the
-- *handler* (source, statustbl) callback function on notable changes in state.
-- See notes below for details on statustbl contents.
-- @notes: Possible statustbl.kind values; "resized", "ident", "message", "failure",
-- "frameserver_terminated", "frame", "state_size", "resource_status", "unknown".
-- @notes: for kind == "resized", width, height 
-- @notes: for kind == "frame", frame
-- @notes: for kind == "message", message
-- @notes: for kind == "ident", message
-- @notes: for kind == "failure", code
-- @notes: for kind == "state_size", state_size
-- @notes: for kind == "unknown", unknown
-- @notes: for kind == "resource_status", "message"
-- @group: targetcontrol 
-- @alias: target_launch
-- @cfunction: arcan_lua_targetlaunch
function main()
#ifdef MAIN
	a = list_games({});
	if (a == nil or #a == 0) then
		warning("empty database, giving up.");
		shutdown();
	end

	for i=1,#a do
		if (launch_target_capabilities(a[i].target).external_launch) then
			launch_target(a[i], LAUNCH_EXTERNAL);
		end
	end

	warning("no launchable target found.");
	shutdown();
#endif

#ifdef MAIN2
	a = list_games({});
	if (a == nil or #a == 0) then
		warning("empty database, giving up.");
		shutdown();
	end

	local cbh = function(source, status)
		if (status.kind == "resized") then
			resize_image(source, status.width, status.height);
		else
			print(status.kind);
		end
	end

	for i=1,#a do
		if (launch_target_capabilities(a[i].target).internal_launch) then
			vid = launch_target(a[i], LAUNCH_INTERNAL, cbh);
			show_image(vid);
		end
	end

	if (vid == nil) then
		warning("no launchable target found.");
		shutdown();
	end
#endif
end

