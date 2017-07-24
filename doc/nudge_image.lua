-- nudge_image
-- @short: Set new coordinates for the specified object based on current position.
-- @inargs: vid, newx, newy, *time*, *interp*
-- @longdescr: This is a convenience function that ultimately resolves to a
-- move_image call internally. The difference is that the current image
-- properties are resolved without a full resolve-call and the overhead that entails.
-- @note: the properties are resolved at invocation time,
-- this means that chaining transformations as with multiple move
-- calls will not have the same effect as each new position will
-- be relative the current one rather than at the one at the end
-- of the transformation.
-- Interp can be set to one of the constants (INTERP_LINEAR, INTERP_SMOOTHSTEP,
-- INTERP_SINE, INTERP_EXPIN, INTERP_EXPOUT, INTERP_EXPINOUT).
-- @group: image
-- @cfunction: nudgeimage
-- @related: move_image
function main()
	a = fill_surface(32, 32, 255, 0, 0);

#ifdef MAIN
	show_image(a);
	move_image(a, VRESW, VRESH);
	nudge_image(a, 10, -10, 100);
#endif

#ifdef ERROR
	nudge_image(BADID, 0, 0, 100);
#endif

#ifdef ERROR2
	nudge_image(a, 0, 0, -100);
#endif
end
