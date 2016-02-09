-- get_keys
-- @short: Retrieve all keys associated with a target or target/config
-- @inargs: targetname, *configname*
-- @outargs: kvtbl
-- @longdescr: This function is intended to be used for the corner cases where
-- one need to explicitly enumerate / filter all key:value pairs associated
-- with a target or a target+config pair, where explicit get_key calls or
-- match_keys calls wouldn't work.
-- @note: output *kvtbl* will always be a table even if the *targetname* or
-- *targetname* + *configname* do not resolve to a valid target and config,
-- but the table itself will be empty. Therefore it is not possible to
-- distinguish between valid/invalid targets here.
-- @group: database
-- @cfunction: getkeys
-- @related:
function main()
#ifdef MAIN
	local tbl = list_targets();
	if (#tbl == 0) then
		warning("get_keys test must be run on a database with a valid target");
		return shutdown();
	end
	store_key("test1", "testval", tbl[1]);
	store_key("test2", "testval", tbl[2]);
	for k,v in ipairs(get_keys(tbl[1])) do
		print(k, v);
	end
#endif

#ifdef ERROR1
#endif
end
