-- zap_resource
-- @short: Unlink a file in the appltemp path or writable user namespace.
-- @inargs: string:res
-- @inargs: string:res, string:namespace
-- @outargs: bool:success
-- @longdescr:
-- This function can be used to delete a file. By default this will apply only
-- to the appl-temp namespace. If *namespace* is provided and mathces a user-
-- defined writable namespace ID (see ref:list_namespaces), the deletion will
-- apply to a file in that namespace instead. Returns whether the file was
-- successfully deleted or not.
-- @outargs: boolres
-- @group: resource
-- @cfunction: zapresource
-- @flags:
function main()
#ifdef MAIN
	open_rawresource("test.out");
	zap_resource("test.out");

	if (resource("test.out")) then
		warning("something went horribly wrong.");
	end
#endif

#ifdef ERROR
	zap_resource("/../../../../../../usr/bin/arcan");
#endif

#ifdef ERROR2
	zap_resource("/../resources/scripts/mouse.lua");
#endif
end
