-- load_image_asynch
-- @short: asynchronously load an image from a resource
-- @inargs: resource, *callback
-- @arg(*callback): a lua function that takes two arguments (sourcevid, statustbl)
-- if the image succeeded, the "kind" field of "statustbl" will be set to "loaded"
-- if the image couldn't be loaded, the "kind" field of "statustbl" will be set to "load_failed"
-- and the "resource" field will be set to indicate the resource string that failed to load.
-- in both cases, "width" and "height" will be set (as the video object will still be valid,
-- just set to a placeholder source.
-- @outargs: VID, fail:BADID
-- @longdescr: Sets up a new video object container and attempts to load and
-- decode an image from the specified resource.
-- @note: The new VID has its opacity set to 0, meaning that it will start out hidden.
-- @note: The operation can be forced asynchronous by either doing an operation which requires
-- a stable state for the current context (e.g. push/pop_video_context) or by explicitly calling
-- image_pushasynch.
-- @group: image
-- @cfunction: loadimageasynch
-- @related: image_pushasynch load_image
function main()
#ifdef MAIN
	vid = load_image_asynch("test.png", function(source, tbl)
	    if (tbl.kind == "loaded") then
		resize_image(source, tbl.width, tbl.height);
		warning("image loaded\n");
	    elseif (tbl.kind == "load_failed") then
		warning("couldn't load:" .. tbl.resource .. "\n");
	end);

	show_image(vid);
#endif

#ifdef ERROR
	vid = load_image_asynch("test.png", load_image_asynch);
#endif

#ifdef ERROR2
	vid = load_image_asynch("test.png", -1);
#endif
end
