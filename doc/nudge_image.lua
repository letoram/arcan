-- nudge_image
-- @short: Set new coordinates for the specified object based on current position.
-- @inargs: vid, newx, newy, *time*
-- @longdescr: This is a convenience function that ultimately resolves to a move_image call internally. The difference is that the current image properties are resolved without a full resolve-call and the overhead that entails. 
-- @group: image 
-- @cfunction: arcan_lua_nudgeimage
-- @related: move_image
function main()
	a = fill_surface(32, 32, 255, 0, 0);

#ifdef MAIN
	show_image(a);
	move_image(a, VRESW, VRESH);
	nudge_image(a, 10, -10, 100);
#endif

#ifdef ERROR1
	nudge_image(BADID, 0, 0, 100);
#endif

#ifdef ERROR2
	nudge_image(a, 0, 0, -100);
#endif
end
