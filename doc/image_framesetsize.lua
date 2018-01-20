-- image_framesetsize
-- @short: Allocate slots for multi-frame objects.
-- @inargs: vid, int:count
-- @inargs: vid, int:count, int:mode
-- @outargs:
-- @longdescr: Objects can have a frameset associated with them.
-- A frameset is comprised of references to vstores that have been acquired
-- from other pre-existing objects, including the source object itself. This
-- mechanism works similarly to image_sharestorage and the lifecycle of the
-- frameset association is tied to the supplied *vid*.
-- This can be used for applications e.g. multitexturing, animations,
-- texturing complex 3D models and as a round-robin storage for dynamic
-- data sources (effectively giving access to previous frames).
-- mode is FRAMESET_SPLIT, other options are FRAMESET_MULTITEXTURE.
-- FRAMESET_SPLIT only has one active frame, like any other video object
-- (and then relies on framecyclemode or manually selecting visible frame by
-- explicitly calling image_active_frame).
-- FRAMESET_MULTITEXTURE tries to split the frameset across multiple
-- texture units. These can be accessed in a shader through the samplers
-- map_tu0, map_tu1 etc.
-- @group: image
-- @note: A frameset associated with a 3D model will be split across each
-- mesh, where a single mesh can consume multiple frameset slots, unless
-- the source is a cubemap.
-- @note: Once initialized with a frameset, the size of the frameset can
-- only increase during the life-cycle of the object with the special case
-- of setting a frameset to 1 which will drop and reset the object to only
-- have one active frame and revert to normal mapping mode.
-- @note: The initial state of frameset slots for *vid* is that all
-- reference the default vstore for the object.
-- @note: A persistant object cannot have a frameset, associating a frameset
-- with an objects disqualifies the object to be marked as persistant.
-- @note: frameset support only applies to objects with a normal, textured
-- backing store.
-- @related: set_image_as_frame, image_framesetsize, image_framecyclemode, image_active_frame
-- @cfunction: framesetalloc
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
