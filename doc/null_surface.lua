-- null_surface
-- @short: Create a minimalistic video object.
-- @inargs: startw, starth
-- @outargs: vid
-- @longdescr: Null surfaces creates a normal textured video object that
-- lacks a backing store and will therefore not be rendered in the normal
-- draw pass, although it can be used for clipping operations. It is
-- primarily used as an intermediate stage before using ref:image_sharestorage
-- to share the backing storage between two objects. The null_sueface is
-- also useful as a property anchor for creating object hierarchies.
-- @note: intial starting dimensions still need to be specified in order for
-- other lookup functions e.g. image_surface_initial_properties to work
-- properly.
-- dependencies
-- @group: image
-- @cfunction: nullsurface
-- @related: fill_surface, image_sharestorage
function main()
#ifdef MAIN
	a = null_surface(32, 32);
	b = fill_surface(32, 32, 255, 0, 0);
	show_image(b);
	link_image(b, a);
	moev_image(a, 100, 100, 100);
	blend_image(a, 1.0, 100);
#endif

#ifdef ERROR
	a = null_surface();
#endif

#ifdef ERROR
	a = null_surface(-1, -1);
#endif
end
