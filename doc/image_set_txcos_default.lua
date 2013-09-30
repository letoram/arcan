-- image_set_txcos_default
-- @short: Revert to the default set of texture mapping coordinates.
-- @inargs: vid 
-- @group: image 
-- @cfunction: arcan_lua_settxcos_default
-- @related: image_set_txcos, image_get_txcos
function main()
#ifdef MAIN
	a = random_surface(64, 64);
	b = null_suface(32, 32);
	image_set_txcos(a, {0.1, 0.5, 0.2, 0.4, 0.8, 0.2, 0.6, 0.7});
	show_image({a, b});
	image_sharestorage(a, b);
	image_set_txcos_default(b);
#endif
end
