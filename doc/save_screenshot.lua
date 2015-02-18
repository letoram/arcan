-- save_screenshot
-- @short: Store a copy of the current display to a file.
-- @inargs: dstres, *fmt*, *srcid*, *local*
-- @longdescr: This function creates a file of the latest drawn
-- output on the primary display or of the contents of a specific
-- VID of specified in *srcid*. Local (default, false) set to
-- true or non-zero hints that the local storage should be used.
-- This is important when there is a discrepancy between what is
-- stored as the objects video backing store (implementation defined)
-- and the local copy as they are not always in synch.
-- The format setting is by default FORMAT_PNG but can also be
-- FORMAT_PNG_FLIP, FORMAT_RAW8, FORMAT_RAW24 or FORMAT_RAW32 though
-- the RAW formats are primarily for advanced use and debugging purposes.
-- @note: For specific contexts, primarly calctargets, the contents of
-- the non-local storage is not accessible on all graphic subsystems
-- for all *srcids* as the calctarget may occupy or bind the same slot.
-- Either do the call outside such a scope or force local readback.
-- @group: resource
-- @cfunction: screenshot
function main()
#ifdef MAIN
	show_image(fill_surface(64, 64, 255, 0, 0));
	local a = fill_surface(64, 64, 0, 255, 0);
	move_image(a, VRESW - 64, 0);
	local b = fill_surface(64, 64, 0, 0, 255);
	move_image(b, 0, VRESH - 64);
	local c = fill_surface(64,  64, 0, 255, 255);
	move_image(c, VRESW - 64, VRESH - 64);
	show_image({a, b, c});
#endif
end
