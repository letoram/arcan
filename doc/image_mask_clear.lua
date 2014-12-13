-- image_mask_clear
-- @short: Clear a status flag on the specified object
-- @inargs: vid, maskval
-- @group: image
-- @cfunction: clearmask
-- @note: an invalid maskval is considered a terminal state transition.
-- @related: image_mask_toggle, image_mask_set, image_mask_clearall
-- @reference: image_mask
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = instance_image(a);
	show_image({a, b});
	move_image(a, 32, 32);
	image_mask_clear(b, MASK_POSITION);
#endif

#ifdef ERROR
	image_mask_clear(null_surface(32, 32, 0, 0, 0), math.random(1000000));
#endif
end
