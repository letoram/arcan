-- game_family
-- @short: Return a list of titles that are marked as related to a specific gameid.
-- @inargs: gameid
-- @outargs: strtbl or nil
-- @longdescr:
-- @group: database
-- @cfunction: arcan_lua_gamefamily
-- @related: game_cmdline, list_games, list_targets, game_info, game_genres
-- @flags:
function main()
#ifdef MAIN
	local res = game_family(list_games({})[1].gameid);
	if (res) then
		for k,v in ipairs(res) do
			print(v);
		end
	end
#endif

#ifdef ERROR1
	game_family();
#endif
end
