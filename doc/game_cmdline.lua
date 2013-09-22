-- game_cmdline
-- @short: Compute the command-line used to launch the specified target
-- @inargs: gameid or gametitle, *internal
-- @outargs: strtbl or nil 
-- @longdescr: For external launch and internally launched hijack-library targets,
-- a command-line is generated based on the entries in the current database, with certain
-- template tags expanded. If *internal is not specified or set to !0, the engine 
-- assumes internal-launch arguments.
-- @group: database
-- @related: list_games, list_targets, game_info, game_family, game_genres
-- @cfunction: arcan_lua_getcmdline
-- @flags: 
function main()
	#ifdef MAIN
		tbl = game_cmdline(1);
		if (tbl) then
			for i,v in ipairs(tbl) do
				print(v);
			end
		end
	#endif

	#ifdef ERROR1
		a = game_cmdline(nil);
	#endif
end
