-- get_key
-- @short: Retrieve a key/value pair from the database.
-- @inargs: key, *opttgt*, *optcfg*
-- @outargs: string or nil
-- @longdescr: Return a single value associated with a *key*
-- from either the appl global space, or from an optional
-- target or optional target/configuration.
-- @group: database
-- @cfunction: getkey
-- @related: store_key
-- @flags:
function main()
#ifdef MAIN
	local test = store_key("test", "result");
	local value = get_key("test");
	if (value == "result") then
		print("OK");
	end
#endif
end
