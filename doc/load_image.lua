-- load_image
-- @short: synchronously load supported images
-- @inargs: resource, *startzv, *desired width, *desired height
-- @outargs: VID, fail:BADID
-- @longdescr: Sets up a new video object container and attempts to
-- load and decode an image from the specified resource.
-- @note: The new VID has its opacity set to 0 (hidden)
-- @note: This routine is synchronous, so it will block until the image
-- has been loaded
-- @note: desired width/desired height are capped to the engine compile-time
-- values CONST_MAX_SURFACEW, CONST_MAX_SURFACEH (2048x2048)
-- @note: If the engine is running in conservative mode, no local copy
-- will be kept in memory and the resource will be reloaded on every
-- operation that manipulates the current rendering context (e.g. stack
-- push / pop or launch_target(external).
-- @note: supported file formats vary with platform and engine build, only
-- ones that are guaranteed to work are PNG and JPEG.
-- @group: image
-- @cfunction: loadimage
-- @related: load_image_asynch
-- @flags:
function main()
#ifdef MAIN
	vid = load_image("test.png");
	show_image(vid);

	vid2 = load_image("test.png", 2, 48, 48);
	show_image(vid);
#endif

#ifdef ERROR
	vid = load_image();
#endif

#ifdef ERROR2
	vid = load_image("test.png", -1, -1, -1);
#endif
end
