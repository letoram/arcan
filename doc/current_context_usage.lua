-- current_context_usage
-- @short: Return how many cells the current context has, and how many of those cells that are currently unused.
-- @inargs:
-- @outargs: total, used
-- @longdescr: This function sweeps the VID pool of the currently active
-- context and counts O(n) how many of these are in use and subsequently
-- returns how many slots are available in total, and how many are
-- maked as used. The number of free slots can be found by subtracting
-- used from total.
--
-- @group: vidsys
-- @cfunction: contextusage
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 0, 0, 0);
	print(current_context_usage());
	b = fill_surface(32, 32, 0, 0, 0);
	print(current_context_usage());
#endif
end
