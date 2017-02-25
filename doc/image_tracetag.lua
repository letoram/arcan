-- image_tracetag
-- @short: Set or retrieve a tracing tag for the specified video object.
-- @inargs: vid, *tag*
-- @outargs: tag
-- @longdescr:
-- It is possible to attach a user-defined string to any vid. This tag will
-- be used in debug/tracing output and crash- dumps in order to more easily
-- identify various objects, or be used as a custom metadata key for appl-
-- specific purposes.
-- If no *tag* is provided, the currently set value will be returned.
-- If there is no tag set, the returned string will be '(no tag)'.
-- @group: debug
-- @cfunction: tracetag
-- @flags: debugbuild
function main()
#ifdef MAIN
	a = color_surface(32, 32, 255, 0, 0);
	image_tracetag(a, "test");
	print(image_tracetag(a));
#endif
end
