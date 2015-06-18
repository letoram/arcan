-- store_key
-- @short: Store one or several key-value pairs in the database.
-- @inargs: argtbl or [key, val], *opttgt*, *optcfg*
-- @outargs: true or false
-- @longdescr: There are multiple key- value stores that can be used for
-- keeping track of specific key value pairs. The normal one is bound to the
-- currently running appl, but there is also one connected to each execution
-- target that is accessed by setting *opttgt* to any value from ref:list_targets.
-- There is also a execution target configuration specific key- value store if
-- both *opttgt* and *optcfg* are set to a valid target- configuration pair.
-- Only characters in the set [a-Z][0-9]_ are valid *key* values.
-- To set multiple pairs at once, pack them in a key- indexed table.
-- @group: database
-- @cfunction: storekey
-- @related: get_key, match_keys, list_targets, target_configurations
function main()
#ifdef MAIN
	tbl = {key_a = "ok", key_b = "ok"};
	store_key(tbl);
	store_key("key_c", "ok");

	print(get_key("key_a"));
	print(get_key("key_b"));
	print(get_key("key_c"));

	local tgtlist = list_targets();
	if (#tgtlist > 0) then
		store_key(tbl, tgtlist[1]);
		store_key(tbl, tgtlist[1], target_configurations(tgtlist[1])[1]);
	end
#endif
end
