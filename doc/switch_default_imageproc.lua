-- switch_default_imageproc
-- @short: Set the default image post-processing mode.
-- @inargs: procmode
-- @longdescr: accepted values are IMAGEPROC_NORMAL where loaded image
-- will be stored without any additional postprocessing, and IMAGEPROC_FLIPH
-- where the image will be flipped over the x-axis (so y- row order will be
-- inverted).
-- @group: vidsys
-- @cfunction: setimageproc
-- @flags:
function main()
#ifdef MAIN
	switch_default_imageproc(IMAGEPROC_FLIPH);
	a = load_image("test.png");
	switch_default_imageproc(IMAGEPROC_NORMAL);
	b = load_image("test.png");
	show_image({a,b});
	local props = image_surface_properties(b);
	move_image(b, b.width, b.height);
#endif

#ifdef ERROR
	switch_default_imageproc("test1");
#endif

#ifdef ERROR2
	switch_default_imageproc(200);
#endif
end
