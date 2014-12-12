-- image_get_txcos
-- @short: Get the active texture settings for the specified object.
-- @inargs: vid
-- @outargs: numary
-- @longdescr: Each object, by default, has a texture transformation that maps
-- its coordinate in 0,0,1,1 space. In some circumstances, however, it may be
-- different or you may want to change parts.
-- @group: image
-- @cfunction: gettxcos
-- @related: image_set_txcos, image_set_txcos_default
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 0, 0, 0);
	b = image_get_txcos(a);
	print( table.concat(b, ",") );
#endif
end
