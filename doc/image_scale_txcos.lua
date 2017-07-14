-- image_scale_txcos
-- @short: Multiply the current set of texture coordinates uniformly
-- @inargs: vid, fact_s, fact_t
-- @group: image
-- @cfunction: scaletxcos
-- @related: image_set_txcos, image_get_txcos, image_set_txcos_default
function main()
#ifdef MAIN
	a = load_image("test.png");
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT, a);
	show_image(a);
	resize_image(a, VRESW, VRESH);
	props = image_suface_properties(a);
	image_scale_txcos(a, VRESW / props.width, VRESH / props.height);
#endif
end
