-- zap_resource
-- @short: Unlink a file in the applpath.
-- @inargs: resstr
-- @outargs: boolres
-- @group: resource
-- @cfunction: arcan_lua_zapresource
-- @flags:
function main()
#ifdef MAIN
	open_rawresource("test.out");
	zap_rawresource("test.out");

	if (resource("test.out")) then
		warning("something went horribly wrong.");
	end
#endif

#ifdef ERROR1
	zap_rawresource("/../../../../../../usr/bin/arcan");
#endif

#ifdef ERROR2
	zap_rawresource("/../resources/scripts/mouse.lua");
#endif
end
