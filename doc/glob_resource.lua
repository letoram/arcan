-- glob_resource
-- @short: Search the different datastores for resources matching a pattern.
-- @inargs: string:pattern
-- @inargs: string:pattern, int:domain
-- @inargs: string:pattern, int:domain, bool:asynch
-- @inargs: string:pattern, string:namespace
-- @inargs: string:pattern, string:namespace, bool:asynch
-- @inargs: string:pattern, int:domain
-- @outargs: strtbl or nbio
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
-- If the *asynch" argument is provided, the function will return a nbio table
-- as if opened with ref:open_nonblock, or nil if there are too many open files
-- or not enough memory. The results readable from open_nonblock will contain
-- the terminating \0 in order to capture file names with special characters.
-- They will also contain the namespace relative path prefix.
-- ref:open_nonblock:lf_strip(true, "\0") can be used to get per-read separation
-- and
-- @note: the default domain is the compile-time defined (DEFAULT_USERMASK)
-- which is comprised of (application- specific, application shared,
-- application temporary)
-- @note: Due to legacy and backwards compatibility, the synchronous results
-- contain only filename and, possibly, extension.
-- @note: SYS_APPL_RESOURCE is
-- special and relates to the list of application
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
