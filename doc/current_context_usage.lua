-- current_context_usage
-- @short: Return how many cells the current context has, and how many of those cells that are currently unused.
-- @inargs:
-- @outargs: total, n_free
-- @longdescr: This function sweeps the VID pool of the currently active context and counts O(n) how many of these are in use. Thus, the number of used cells are *total* - *n_free*.
-- @group: vidsys
-- @cfunction: arcan_lua_contextusage
-- @flags:
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 0, 0, 0);
	print(current_context_usage());
	b = fill_surface(32, 32, 0, 0, 0);
	print(current_context_usage());
#endif
end
