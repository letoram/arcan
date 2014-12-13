-- system_load
-- @short: Load and parse additional scripts.
-- @inargs: resstr, *dieonfail*
-- @note: If dieonfail is set (default is on) to 0,
-- failure to load (parse errors etc.) will only yield a nil result,
-- not a terminal state transition.
-- @note: Trying to load a non-existing script is a terminal state transition.
-- @group: system
-- @cfunction: dofile
function main()
#ifdef MAIN
	system_load("test.lua")();
	system_load("test_bad.lua", 0);
#endif

#ifdef ERROR
	system_load("missing")();
#endif
end
