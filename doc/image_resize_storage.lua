-- image_resize_storage
-- @short: resize the dimensions of the image backing store
-- @inargs: vid, neww, newh
-- @longdescr: This function is indended for testing streaming
-- transfers and for rendertargets where one may need to permanently
-- or temporarily change backing storage dimensions in order to save
-- memory or deal with rendertarget resize without rebuilding attachment
-- chains.
-- @note: There is no guarantee that the change can be performed as
-- some platforms may impose alignment and padding requirements.
-- @note: The underlying code-path is similar to the resized event
-- for a frameserver, but without the event being emitted. No alert
-- is raised if the change could not be performed due to video hardware
-- issues or memory constraints.
-- @group: image
-- @cfunction: imageresizestorage
-- @related:
function main()
#ifdef MAIN
	local surf = alloc_surface(640, 480);
	local props = image_storage_properties(surf);
	print(props.width, props.height);
	image_resize_storage(surf, 320, 240);
	props = image_storage_properties(surf);
	print(props.width, props.height);
#endif

#ifdef ERROR1
	image_resize_storage(alloc_surface(640, 480), -1, -1);
#endif

#ifdef ERROR2
	image_resize_storage(alloc_surface(640, 840,
		MAX_SURFACEW, MAX_SURFACEH));
#endif
end
