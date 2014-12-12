-- image_set_txcos_default
-- @short: Revert to the default set of texture mapping coordinates.
-- @inargs: vid, *mirror*
-- @group: image
-- @longdescr:
-- The engine, by default, manages texture coordinates for video objects.
-- In some rare instances however, the developer may want to hand-tune
-- these in the pre-rendering stages rather than modifying the coordinates
-- in a shader. To revert back to the default behavior, this function can
-- be used. If mirror is set to a non-zero integer,
-- the mapping generate will be flipped along the Y axis to compensate
-- for the arcan coordinate system having origo in the upper left corner
-- whileas OpenGL uses the lower left.
-- @cfunction: settxcos_default
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
