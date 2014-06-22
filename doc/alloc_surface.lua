-- alloc_surface
-- @short: Create an empty, non-visible surface with a preset storage.
-- @inargs: width, height
-- @outargs: vid
-- @longdescr: Some operations, particularly record and rendertargets need
-- a storage buffer to work with. In the past, this has been done with
-- fill_surface and special arguments added to the end. This function
-- replaces that workaround.
-- @group: image
-- @cfunction: allocsurface
-- @related:
function main()
#ifdef MAIN
	local vid = fill_surface(640, 480);
	assert(vid ~= BADID)
	print("allocated: ", vid, 640, 480);
	show_image(vid); -- shouldn't yield anything
#endif

#ifdef ERROR1
	fill_surface(-1, -1);
#endif

#ifdef ERROR2
	fill_surface(1000000, 100000000);
#endif
end
