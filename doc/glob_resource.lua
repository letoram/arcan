-- glob_resource
-- @short: Search the different datastores for resources matching a pattern.
-- @inargs: string:pattern
-- @inargs: string:pattern, int:domain
-- @inargs: string:pattern, string:namespace
-- @outargs: strtbl
-- @longdescr: There are a number of different statically defined namespaces
-- (distinct group where a certain resource key corresponds to a file or
-- similar data-source). This function allows you to query parts of these namespaces
-- (indicated by a search path, *pattern*).
-- By specifying a *domain* you can limit the search to a specific set of namespaces.
-- This domain can be a predefined bitmap of numeric constants, or a user-defined
-- dynamic namespace tag. Valid constants for domain (can be ORed) are APPL_RESOURCE,
-- APPL_TEMP_RESOURCE, SHARED_RESOURCE, SYS_APPL_RESOURCE, SYS_FONT_RESOURCE,
-- APPL_STATE_RESOURCE, The dynamic namespace tag has to match a valid name from
-- ref:list_namespaces.
-- @note: the default domain is the compile-time defined (DEFAULT_USERMASK)
-- which is comprised of (application- specific, application shared,
-- application temporary)
-- @note: The results contain only filename and, possibly, extension.
-- @note: The scan is shallow, it will not recurse into subdirectories.
-- Therefore, more complex patterns, e.g. /*/a* will not work.
-- @note: SYS_APPL_RESOURCE is special and relates to the list of application
-- targets that can be used as argument to system_collapse.
-- @group: resource
-- @cfunction: globresource
-- @related: resource, system_collapse
-- @flags:
function main()
#ifdef MAIN
	local tbl = glob_resource("*");
	for i,v in ipairs(tbl) do
		print(v);
	end
#endif

#ifdef MAIN2
	local tbl = glob_resource("*", SYS_APPL_RESOURCE);
	for i,v in ipairs(tbl) do
		print(v);
	end
#endif

#ifdef ERROR
	local tbl = glob_resource(0);
	if (type(tbl) ~= "table") then
		abort();
	end
#endif
end
