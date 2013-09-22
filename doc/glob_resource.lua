-- glob_resource
-- @short: Search the different datastores for resources matching a certain pattern. 
-- @inargs: pattern, *domain
-- @outargs: strtbl
-- @longdescr: 
-- @note: By default, both the THEME and RESOURCE domain are searched, starting
-- with THEME.
-- @note: The results contain only filename and, possibly, extension. 
-- Everything before the last / delimiter will be tripped.
-- @note: The scan is shallow, meaning that it will not recurse into subdirectories.
-- @group: resource 
-- @cfunction: arcan_lua_globresource
-- @related: resource
-- @flags: 
-- 1 0: 
function main()
#ifdef MAIN
	local tbl = glob_resource("*");
	for i,v in ipairs(tbl) do
		print(v);
	end
#endif

#ifdef ERROR1
	local tbl = glob_resource(0);
	if (type(tbl) ~= "table") then
		abort();
	end
#endif
end
