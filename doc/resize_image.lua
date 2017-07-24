-- resize_image
-- @short: Change object dimensions based on absolute pixel values.
-- @inargs: vobj, new_w, new_h, *time*, *interp*
-- @longdescr: This transformation, internally remapped to the
-- scale_image call but with scale values based on the initial dimensions
-- of the object, sets a new desired output dimension.
-- Interp can be set to one of the constants (INTERP_LINEAR, INTERP_SINE,
-- INTERP_EXPIN, INTERP_EXPOUT, INTERP_EXPINOUT, INTERP_SMOOTHSTEP).
-- @note: the end dimensions can still be manipulated through the
-- vertex shader stage, but such changes do not affect other engine
-- features (like picking and other forms of collision detection).
-- @group: image
-- @cfunction: scaleimage2
-- @related: scale_image
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 0, 255, 0);
	resize_image(a, 128, 128, 100);
	show_image(a);
#endif
end
