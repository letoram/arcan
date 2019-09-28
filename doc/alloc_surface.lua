-- alloc_surface
-- @short: Create an empty, non-visible surface with a preset storage.
-- @inargs: int:width, int:height
-- @inargs: int:width, int:height, bool:noalpha
-- @inargs: int:width, int:height, bool:noalpha, int:quality
-- @outargs: vid
-- @longdescr: Some operations, particularly record and rendertargets need
-- a storage buffer to work with. While ref:fill_surface could also be used
-- for such operations, this function will result in one one less transfer
-- and, optionally, some control over storage format and quality.
-- If *noalpha* is set (true, !0) the texture format for the underlying
-- backing store will be set to one where the alpha channel corresponds to
-- fullbright (ignore/nobright). *quality* can be set to one of the following:
-- ALLOC_QUALITY_LOW, ALLOC_QUALITY_NORMAL, ALLOC_QUALITY_HIGH,
-- ALLOC_QUALITY_FLOAT16, ALLOC_QUALITY_FLOAT32.
-- @note: Only ALLOC_QUALITY_NORMAL is guaranteed to be a valid target for
-- ref:map_video_display and similar operations.
-- @note: Note that not all storage modes will support all forms of filtering,
-- or mipmapping. If in doubt, disable vfilter and manually sample in a shader.
-- @group: image
-- @cfunction: allocsurface
-- @related:
function main()
#ifdef MAIN
	local vid = fill_surface(640, 480);
	assert(vid ~= BADID)
	print("allocated: ", vid, 640, 480);
	show_image(vid);
#endif

#ifdef ERROR
	fill_surface(-1, -1);
#endif

#ifdef ERROR2
	fill_surface(1000000, 100000000);
#endif
end
