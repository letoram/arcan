-- image_scale_txcos
-- @short: Revert basic texture coordinates to the default, then apply two scale factors.
-- @inargs: vid, fact_s, fact_t
-- @group: image
-- @cfunction: arcan_lua_scaletxcos
-- @related: image_set_txcos, image_get_txcos, image_set_txcos_default
function main()
#ifdef MAIN
	a = load_image("test_pattern.png");
	switch_default_texmode(TEX_REPEAT, TEX_REPEAT, a);
	show_image(a);
	resize_image(a, VRESW, VRESH);
	props = image_suface_properties(a);
	image_scale_txcos(a, VRESW / props.width, VRESH / props.height);
#endif
end
