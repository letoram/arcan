-- image_sharestorage
-- @short: Setup two VIDs to use the same texture store. 
-- @inargs: src, dst 
-- @longdescr: Multiple objects can be set to use the same underlying 
-- texture storage (internally reference counted) to work around some
-- of the restrictions inherent to instance_image and similar functions.
-- @note: texture coordinates are initially copied over but are otherwise
-- managed separately in each object. 
-- @note: video image post processing (scale, flips and filtermode) are bound
-- to the texture store and not to any- single object.
-- @note: non-textured objects (null, color, instances and persistant) cannot
-- bu used as src.
-- @note: persistent objects and instances cannot be used as dst.
-- @group: image 
-- @cfunction: arcan_lua_sharestorage
-- @related: instance_image, null_surface
function main()
#ifdef MAIN
	a = load_image("test.png");
	b = null_surface(64, 64);
	move_image(b, 100, 100);
	show_image({a, b});
#endif MAIN

#ifdef MAIN
	image_sharestorage(a, b);
#endif

#ifdef ERROR1
	image_sharestorage(b, a);
#endif

#ifdef ERROR2
	persist_image(a);
	image_sharestorage(a, b);
#endif
end
