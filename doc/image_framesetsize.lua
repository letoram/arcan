-- image_framesetsize
-- @short: Allocate slots for multi-frame objects. 
-- @inargs: vid, count, *mode*
-- @outargs: 
-- @longdescr: Objects can have a frameset associated with them. A frameset is
-- comprised of references to other objects, including itself. This can be used
-- for anything from multitexturing to animations to round-robin storage. Default
-- mode is FRAMESET_SPLIT, other options are FRAMESET_MULTITEXTURE. FRAMESET_SPLIT
-- only has one active frame, like any other video object (and then relies on framecyclemode
-- or manually selecting visible frame), whileas FRAMESET_MULTITEXTURE tries to split
-- the frameset on multiple texture units. This requires that the shader access the samplers
-- through symbols map_tu0, map_tu1 etc.
-- @group: image
-- @note: When calling allocframes for an object that already has a defined frameset,
-- the objects that would be orphaned (only attached to the frameset) will be 
-- deleted.
-- @note: An instance of another object cannot have a frameset associated with it. 
-- @note: A persistant object cannot have a frameset or be linked to one. 
-- @note: When deleting an object with frames attached, the deletion will also
-- cascade to cover frameset objects unless MASK_LIVING is cleared.
-- @note: Specialized surface types e.g. color_surface, null_surface cannot have a frameset
-- or be linked to one.
-- @note: providing unreasonable (0 < n < 256, outside n) values to count are treated as a 
-- terminal state.
-- @related: set_image_as_frame, image_framesetsize, image_framecyclemode, image_active_frame 
-- @cfunction: arcan_lua_framesetalloc
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	image_framesetsize(a, 3);
	b = fill_surface(32, 32, 0, 255, 0);
	c = fill_surface(32, 32, 0, 0, 255);
	set_image_as_frame(a, b, 1);  
	set_image_as_frame(a, c, 2);
	image_framecyclemode(1, -1);
	show_image(a);
#endif
end
