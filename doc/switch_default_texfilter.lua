-- switch_default_texfilter
-- @short: Switch the default texture filtering mode for all newly
-- created objects.
-- @inargs: filtermode
-- @longdescr: This function accepts either FILTER_NONE, FILTER_LINEAR,
-- FILTER_BILINEAR and FILTER_TRILINEAR which are texture post-processing
-- stages usually supported in-hardware. Others will have to be implemented
-- as temporary rendertargets with appropriate shaders.
-- @note: any value to filtermode outside the accepted values is a terminal
-- state transition.
-- @group: vidsys
-- @cfunction: settexfilter
function main()
#ifdef MAIN
	switch_default_texfilter(FILTER_NONE);
	a = load_image("test.png");
	show_image(a);
	scale_image(a, 1.25, 1.25);

	switch default_texfilter(FILTER_TRILINEAR);
	b = load_image("test.png");
	show_image(b);
	scale_image(b, 1.25, 1.25);
	local props = image_surface_properties(a);
	move_image(b, 0, props.height);
#endif

#ifdef ERROR
	switch_default_texfilter("none");
#endif

#ifdef ERROR2
	switch_default_texfilter(1000);
#endif
end
