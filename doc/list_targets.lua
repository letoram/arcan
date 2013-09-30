-- list_targets
-- @short: List all available targets by their shortname. 
-- @outargs: targettbl 
-- @group: database 
-- @cfunction: arcan_lua_gettargets
function main()
#ifdef MAIN
	for i,v in ipairs(list_targets()) do
		print(v);
	end
#endif
end
