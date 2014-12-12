-- system_snapshot
-- @short: Create a debugging snapshot
-- @inargs: outres
-- @note: refuses to overwrite outres if it exists
-- (only appl- destination accepted).
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
