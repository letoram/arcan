-- image_sharestorage
-- @short: Setup two VIDs to use the same texture store.
-- @inargs: vid:src, vid:dst
-- @outargs: bool
-- @longdescr: A vid contains a number of metadata states such as position and
-- orientation, along with the idea of a 'storage' which is the textual, image
-- or external source tied to the vid. As a means of preventing multiple views
-- of the same storage, this function can be used to share the storage of vid
-- as the storage of dst.
-- @note: Texture coordinates are initially copied over but are otherwise
-- managed separately in each object.
-- @note: WORLDID is a valid src argument, (WORLDID as dst is undefined) but
-- any surface that shares storage with WORLDID should not be part of a visible
-- rendertarget.
-- @note: Video image post processing (scale, flips and filtermode) are bound
-- to the texture store and not to any- single object.
-- @note: Using a broken or empty vstore as src will convert dst into the
-- equivalent of a null_surface. Using a color surface will copy the colour
-- values and the assigned shader.
-- @note: Sharing into a *dst* that is also used as the storage for a
-- rendertarget will invalidate the state of the rendertarget and an explicit
-- ref:rendertarget_forceupdate will be called.
-- @note: There is no ordering imposed in rendertarget updates, which means
-- that a store that is used as the destination for a rendertarget will need
-- to have all dependent rendertargets manually updated in the preframe
-- stage or the result of using vid that shares backing store with a
-- rendertarget will be undefined.
-- @note: persistent objects and instances cannot be used as dst.
-- @errata: prior to 0.6.3 src to dst transfer with a colour or null surface
-- would transform both src and dst to null surface state.
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
