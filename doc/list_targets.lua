-- list_targets
-- @short: List all available targets by their shortname.
-- @inargs: *tag*
-- @longdescr: Query the database for all targets in the current database,
-- or all targets in the database with a tag that match the optional *tag*.
-- @outargs: targettbl
-- @related: target_configurations, list_target_tags
-- @group: database
-- @cfunction: gettargets
function main()
#ifdef MAIN
	for i,v in ipairs(list_targets()) do
		print(v);
	end
#endif
end
