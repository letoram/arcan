-- game_genres
-- @short: Return a list of unique names from the genre field in the datastore.
-- @inargs:
-- @outargs: tbl or nil
-- @longdescr:
-- @group: database
-- @cfunction: arcan_lua_getgenres
-- @flags:
-- @related: game_cmdline, list_games, list_targets, game_info, game_genres
function main()
#ifdef MAIN
	local res = game_genres();
	if (res) then
		for k, v in ipairs(res) do
			print(v);
		end
	end
#endif
end
