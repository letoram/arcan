-- image_texfilter
-- @short: Switch object video filtering mode.
-- @inargs: vid, mode
-- @outargs:
-- @longdescr: Each object inherits a global default filtering mode upon creation.
-- This mode can be overridden for individual objects through this function.
-- Valid filtering modes are: FILTER_NONE, FILTER_LINEAR, FILTER_BILINEAR, FILTER_TRILINEAR
-- @note: Filtering mode is connected to the gl storage, and the options to share storage
-- between objects through instancing or explicit sharing will retain this property.
-- @group: image
-- @cfunction: changetexfilter
-- @related: switch_default_texfilter
function main()
#ifdef MAIN
	a = load_image("test.png");
	b = load_image("test.png");
	c = load_image("test.png");
	d = load_image("test.png");

	w = VRESW * 0.5;
	h = VRESW * 0.5;
	resize_image({a,b,c,d}, w, h);
	show_image({a,b,c,d});
	move_image(b, w, 0);
	move_image(c, 0, h);
	move_image(d, w, h);

	image_texfilter(a, FILTER_NONE);
	image_texfilter(b, FILTER_LINEAR);
	image_texfilter(c, FILTER_BILINEAR);
	image_texfilter(d, FILTER_TRILINEAR);
#endif

#ifdef ERROR
	image_texfilter(BADID, FILTER_NONE);
#endif

#ifdef ERROR2
	image_texfilter(fill_surface(32, 32, 255, 0, 0), FILTER_NONE);
#endif

#ifdef ERROR3
	image_texfilter(color_surface(32, 32, 255, 0, 0), FILTER_LINEAR);
#endif
end
