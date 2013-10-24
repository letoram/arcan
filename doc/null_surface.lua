-- null_surface
-- @short: Create a minimalistic video object.
-- @inargs: startw, starth 
-- @outargs: vid
-- @longdescr: Null surfaces is a special object container, similar to instances
-- but with less restrictions. They can be used as a lower level clone through
-- image_sharestorage or as attribute containers for larger hierarchies of 
-- objects used for clipping or movable anchors without the cost of hidden
-- fill_surface style objects.
-- @note: intial starting dimensions still need to be specified in order for 
-- other lookup functions e.g. image_surface_initial_properties to work 
-- without workarounds.
-- dependencies 
-- @group: image 
-- @cfunction: arcan_lua_nullsurface
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

#ifdef ERROR1
	a = null_surface();
#endif

#ifdef ERROR1
	a = null_surface(-1, -1);
#endif
end
