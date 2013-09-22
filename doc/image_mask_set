-- image_mask_set
-- @short: Set a status flag on the specified object 
-- @inargs: vid, maskval
-- @group: image 
-- @cfunction: arcan_lua_setmask
-- @note: an invalid maskval is considered a terminal state transition.
-- @related: image_mask_toggle, image_mask_clear, image_mask_clearall
-- @reference: image_mask
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	b = instance_image(a);
	show_image({a, b});
	move_image(a, 32, 32);
	rotate_image(a, 120);
	image_mask_clearall(b);
	image_mask_set(b, MASK_ORIENTATION);
#endif

#ifdef ERROR1
	image_mask_set(WORLDID, math.random(1000));
#endif
end
