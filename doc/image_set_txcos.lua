-- image_set_txcos
-- @short: Override the default texture coordinates for an object.
-- @inargs: vid, txco_t
-- @longdescr: Some specific effects and tricks (or manually maintaining
-- spritesheets or similar image packing options) require that texture
-- coordinates are skewed. This can be achieved either in the vertex shader
-- stage or by statically overriding the default.
-- @group: image
-- @cfunction: settxcos
-- @related: image_get_txcos, image_set_txcos_default, image_scale_txcos
function main()
#ifdef MAIN
	a = load_image("test.png");
	show_image(a);
	image_set_txcos(a, {0.5, 0.5, 1.0, 0.5, 1.0, 1.0, 1.0, 0.5});
#endif
end
