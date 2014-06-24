-- game_info
-- @short: Return a list of game entries that match the specified title.
-- @inargs: titlestr
-- @outargs: strtbl or nil
-- @longdesc: Query the database for all entries that match the title.
-- Returns a table of tables, where the innermost table has the following
-- fields:
--  gameid, targetid, title, genre, subgenre, setname, buttons, manufacturer,
--  players, input, year, target, launch_counter, system
--
-- @note: the wildcard '%' symbol can be used here.
-- @note: the table is manily populated in (arcan_lua.c:void pushgame())
-- @group: database
-- @cfunction: arcan_lua_getgame
-- @flags:
function main()
#ifdef MAIN
	local res = game_info("A%");
	if (res) then
		for k,v in ipairs(res) do
			print(v.gameid, v.title);
		end
	end
#endif
end
