-- list_games
-- @short: Query the database for launchable games.
-- @inargs: argtable
-- @outargs: gametable_tbl
-- @note: (possible *argtable* fields: year, limit, offset, input, players, buttons,
-- title, genre, subgenre, target, system, manufacturer)
-- @note: (possible *gametable* fields: gameid, targetid, title, genre, subgenre,
-- setname, buttons, manufacturer, players, input, year, target, launch_counter, system)
-- @longdescr: Query the currently active database for games that match a certain
-- set of filtering terms. % character can be used to mark wildchars. Return value
-- is a numbe-indexed table of gametable entries.
-- @group: database
-- @cfunction: filtergames
-- @related:
function main()
#ifdef MAIN
	a = list_games({title = "a%"});
	print(#a);
#endif
end
