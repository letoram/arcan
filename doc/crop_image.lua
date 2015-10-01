-- crop_image
-- @short: Crop image to specific dimensions
-- @inargs: width, height
-- @outargs:
-- @longdescr: For some cases, primarily resizing text, the default scale- and
-- resize- function behavior is unappealing because any under or oversampling
-- will rapidly decrease quality. This function act as a resize down to 1:1
-- scale for values larger than the initial size, and changes effective texture
-- coordinates for values larger than the initial size. This will have the side
-- effect of reverting other texture sampling manipulations like mirroring, and
-- it will reset any pending resize transformation chains.
-- @note: Another option to obtain the same effect is to create a null_surface,
-- link the image to this surface and enable shallow clipping but it results in
-- a more complex structure to render and more code to properly set up.
-- @group: image
-- @cfunction: cropimage
-- @related:
function main()
#ifdef MAIN
	local img = load_image("test.png");
	local props = image_surface_properties(img);
	crop_image(img, 0.5 * props.width, 0.5 * props.height);
	show_image(img);
#endif

#ifdef MAIN2
	local img = render_text([[\ffonts/default.ttf,18\#ffffff HELLO WORLD]]);
	local props = image_surface_properties(img);
	crop_image(img, 0.5 * props.width, 0.5 * props.height);
	show_image(img);
#endif

#ifdef ERROR1
#endif
end
