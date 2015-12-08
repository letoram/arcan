-- image_mask_clearall
-- @short: Set the status of all user-modifiable flags to their off state.
-- @inargs: vid
-- @group: image
-- @cfunction: clearall
-- @related: image_mask_clear, image_mask_set, image_mask_toggle
-- @reference: image_mask
function main()
#ifdef MAIN
	a = fill_surface(64, 64, 255, 0, 0);
	b = fill_surface(32, 32, 0, 255, 0);
	show_image({a, b});
	link_image(b, a);
	image_mask_clearall(b);
	delete_image(a);
#endif

#ifdef ERROR
	image_mask_clearall(WORLDID);
#endif

#ifdef ERROR2
	image_mask_clearall(BADID);
#endif
end
