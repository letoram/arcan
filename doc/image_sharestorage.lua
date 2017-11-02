-- image_sharestorage
-- @short: Setup two VIDs to use the same texture store.
-- @inargs: src, dst
-- @longdescr: Multiple objects can be set to use the same underlying
-- texture storage (internally reference counted) to work around some
-- of the restrictions inherent to instance_image and similar functions.
-- @note: texture coordinates are initially copied over but are otherwise
-- managed separately in each object.
-- @note: WORLDID is a valid src argument, (WORLDID as dst is undefined) but any surface that shares storage with WORLDID should not be part of a visible rendertarget.
-- @note: video image post processing (scale, flips and filtermode) are bound
-- to the texture store and not to any- single object.
-- @note: non-textured objects (null, color, instances and persistant) cannot
-- bu used as src.
-- @note: There is no ordering imposed in rendertarget updates, which means
-- that a store that is used as the destination for a rendertarget will need
-- to have all dependent rendertargets manually updated in the preframe
-- stage or the result of using vid that shares backing store with a
-- rendertarget will be undefined.
-- @note: persistent objects and instances cannot be used as dst.
-- @group: image
-- @cfunction: sharestorage
-- @related: instance_image, null_surface
function main()
#ifdef MAIN
	a = load_image("test.png");
	b = null_surface(64, 64);
	move_image(b, 100, 100);
	show_image({a, b});
#endif

#ifdef MAIN
	image_sharestorage(a, b);
#endif

#ifdef ERROR
	image_sharestorage(b, a);
#endif

#ifdef ERROR2
	persist_image(a);
	image_sharestorage(a, b);
#endif
end
