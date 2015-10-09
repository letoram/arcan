-- frameserver_debugstall
-- @short: change the global delay before a frameserver executes
-- @inargs: time
-- @outargs:
-- @longdescr: This function is only exposed in debug builds of the
-- engine where it can be assumed other relevant instrumentation
-- is in place. It changes the inherited environment variable
-- ARCAN_FRAMESERVER_DEBUGSTALL=time (where time is >= 0, 0 clears)
-- that controls how long newly spawned frameservers should delay
-- before continuing execution. This is to allow the developer to
-- attach to the process at a safe spot in order to set breakpoints
-- or control stepping.
-- @longdescr:
-- @group: system
-- @cfunction: debugstall
-- @related:
function main()
#ifdef MAIN
	if (frameserver_debugstall) then
		frameserver_debugstall(10);
		launch_avfeed();
	end
#endif
end
