-- image_tracetag
-- @short: Set or retrieve a tracing tag for the specified video object.
-- @inargs: vid
-- @inargs: vid, string:tag
-- @inargs: vid, string:tag, string:alt
-- @outargs:
-- @outargs: string:tag, string:alt
-- @longdescr:
-- This function is used to associate user defined strings to a video object.
-- The *tag* form is used to define a tracetag that can be used to assist
-- with debugging or as ephemeral storage for persisting data across _reset
-- calls.
--
-- The *alt* form is alt-text to mark that the video object is useful for
-- assistive devices such as screen-readers.
--
-- If no *tag* or *alt* is provided, the currently set value will be returned.
-- If there is no tag set, the returned string will be '(no tag)' and the alt
-- text will be empty.
--
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
