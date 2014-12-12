-- get_key
-- @short: Retrieve a key/value pair from the database.
-- @inargs: Requested key
-- @outargs: string or nil
-- @longdescr:
-- @group: database
-- @cfunction: getkey
-- @related: store_key
-- @flags:
function main()
#ifdef MAIN
	local test = store_key("test", "result");
	local value = load_key("test");
	if (value == "result") then
		print("OK");
	end
#endif
end
