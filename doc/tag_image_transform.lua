-- tag_image_transform
-- @short: Associate a callback with a transformation chain slot
-- @inargs: vid:dst, number:slot_mask, function:callback
-- @outargs:
-- @longdescr: This function can be used to associate a callback function
-- with the last set transformation for one or several slots (using the
-- slot_mask). When the specified transform has completed, an event will
-- be added to the outgoing queue and activated when dequeued.
-- @note: Only MASK_POSITION, MASK_ORIENTATION, MASK_SCALE and MASK_OPACITY
-- are valid slot_mask values and the engine will warn if other values
-- are provided.
-- @note: If there is no transformation queued in the specified slot,
-- no internal state change will be performed.
-- @note: Depending on synchronization and event- queue polling mechanism,
-- the actual event fire can be off by one or more ticks (unlikely).
-- @note: This should be used sparringly as each transformation completion
-- will emit an event.
-- @note: The callback allocation will not persist across transformation
-- cycles defined via ref:image_transform_cycle.
-- @note: This can also be used as a rough timer.
-- @note: Be careful when combining tagged transforms with calls to
-- ref:instant_image_transform as callbacks might be masked or lose
-- their chained pacing. Test tagged transforms for strong reactions
-- when being omitted or stormed.
-- @group: image
-- @cfunction: tagtransform
-- @related:
function main()
#ifdef MAIN
	local vid = fill_surface(64, 64, 0, 255, 0);
	show_image(vid);

	move_image(vid, 50, 50, 50);
	move_image(vid, 100, 100, 100);
	tag_image_transform(vid, MASK_POSITION, function()
		print("move 2 reached", CLOCK);
	end);

	rotate_image(vid, 45, 75);
	tag_image_transform(vid, MASK_ORIENTATION, function()
		print("rotate 1 reached", CLOCK);
	end);

	blend_image(vid, 0.1, 100);
	tag_image_transform(vid, MASK_OPACITY, function()
		print("blend 1 reached", CLOCK);
	end);

	blend_image(vid, 0.5, 50);
	tag_image_transform(vid, MASK_OPACITY, function()
		print("blend 2 reached", CLOCK);
	end);
#endif

#ifdef ERROR
	tag_image_transform(BADID, 0, tag_image_transform);
#endif

#ifdef ERROR2
	tag_image_transform(alloc_surface(64, 64), tag_image_transform);
#endif
end
