-- image_mask_toggle
-- @short: Invert a status flag on the specified object
-- @inargs: vid, maskval
-- @group: image
-- @cfunction: togglemask
-- @note: an invalid maskval is considered a terminal state transition.
-- @related: image_mask_set, image_mask_clear, image_mask_clearall
-- @reference: image_mask
function main()
#ifdef MAIN
	a = fill_surface(32, 32, 255, 0, 0);
	for i=1,4 do
		if (image_hit(a, 0, 0)) then
			print("pickable");
		else
			print("unpickable");
		end
		image_mask_toggle(a, MASK_UNPICKABLE);
	end
#endif

#ifdef ERROR
	image_mask_set(WORLDID, math.random(1000));
#endif
end
