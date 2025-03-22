-- system_snapshot
-- @short: Create a debugging snapshot or open live access to attach a debugger
-- @inargs: string:outres
-- @inargs: string:outres, bool:debug=false
-- @longdescr: This creates a snapshot of the lua scenegraph and stores as a
-- lua script in the APPLTEMP namespace as *outres* or, if *debug* is set the
-- engine will pause and wait for a debugger to attach to *outres*.
-- @outarg: bool:ok, [string:error]
-- @note: the format used is the same as used for
-- crash reports and serialization in monitoring mode.
-- @group: system
-- @cfunction: syssnap
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 255, 0);
	move_image(a, 100, 100);
	zap_resource("testdump.lua");
	system_snapshot("testdump.lua");
	tbl = system_load("testdump.lua")();
#endif
end
