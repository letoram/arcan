-- image_tracetag
-- @short: Set or retrieve a tracing tag for the specified video object. 
-- @inargs: vobj, *tag*
-- @outargs: tag
-- @longdescr: Each video object can have a tracetag associated with it. 
-- This tag, intended for debugging purposes and not guaranteed to be 
-- present in release builds, will be added to other debug outputs 
-- (samples in monitoring mode, or when a debuglevel > 0 is set).
-- @group: debug 
-- @cfunction: arcan_lua_tracetag
-- @flags: debugbuild
function main()
#ifdef MAIN
	a = color_surface(32, 32, 255, 0, 0);
	image_tracetag(a, "test");
	print(image_tracetag(a));
#endif
end
