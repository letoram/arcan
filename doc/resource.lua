-- resource
-- @short: Check if the requested resource path exists. 
-- @inargs: name, *domain*
-- @outargs: longname
-- @longdescr: This function tries to resolve the path description
-- indicated by name and optionally filtered by domain (accepted
-- values are RESOURCE_THEME and RESOURCE_SHARED), by default
-- all domains are scanned, and then resolves the resolved path to
-- the resolved object, or nil.
-- @group: resource 
-- @cfunction: arcan_lua_resource
function main()
#ifdef MAIN
	print( resource("test.png") );
	print( resource("test.png", RESOURCE_THEME) );
	print( resource("test.png", RESOURCE_SHARED) );
#endif
end
