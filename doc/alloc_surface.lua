-- alloc_surface
-- @short: Create an empty, non-visible surface with a preset storage.
-- @inargs: width, height, *noalpha*, *quality*
-- @outargs: vid
-- @longdescr: Some operations, particularly record and rendertargets need
-- a storage buffer to work with. While ref:fill_surface could also be used
-- for such operations, this function implies one less transfer operation
-- and, optionally, through *noalpha* and *quality*, hint to the storage
-- format. If *noalpha* is set (true, !0) the texture format for the underlying
-- backing store will be set to one where the alpha channel corresponds to
-- fullbright (ignore/nobright). Quality can be ignored (normal) or set to
-- ALLOC_LODEF or ALLOC_HIDEF if the underlying display platform supports
-- lower precision color formats (such as RGBA5650) or higher precision
-- formats (such as RGBA1010102).
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
