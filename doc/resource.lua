-- resource
-- @short: Check if the requested resource path exists.
-- @inargs: name, *domain*
-- @outargs: longname. typedescr
-- @longdescr: This function tries to resolve the path description indicated by
-- name and optionally filtered by domain. The accepted *domain* values follow
-- the same rules as other resource related functions, see ref:glob_resource.
-- By default, all user- accessible domains are scanned and the resolved result
-- (or nil) is returned as *longname*. *typedescr* will be set to "folder",
-- "file" or "not found".
-- @group: resource
-- @cfunction: resource
function main()
#ifdef MAIN
	print( resource("images/icons/arcanicon.png") );
	print( resource("test.png", APPL_RESOURCE) );
#endif
end
