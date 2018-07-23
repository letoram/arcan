-- reset_image_transform
-- @short: Drop all ongoing transformations.
-- @inargs: vid
-- @outargs: left_blend, left_move, left_rotate
-- @longdescr: At times there may be queued events that should be
-- cancelled out due to unforeseen changes, this is especially typical
-- when transformations are initated as part as some input or client event
-- handler, like pushing a button to move a cursor indicating a selected item
-- or invoking a keybinding that triggers new animations. To prevent these
-- from stacking up, reset_image_transformation can first be called to flush
-- the queue, and the return values are the number of ticks left to the next
-- item in the chain before flushing.
-- These values could then be used to schedule the new transform and make
-- sure that it would take 'as long' time as the previouslt scheduled one
-- would have occupied.
-- @note: this will not revert the object back to a previous state,
-- but rather stop at whatever part of the chain was currently being
-- processed.
-- @group: image
-- @cfunction: resettransform
-- @related: instant_image_transform
function main()
#ifdef MAIN
	a = fill_surface(20, 20, 255, 0, 0);
	show_image(a);
	move_image(a, 100, 100, 10);
	clock_c = 5;
end

function main_clock_pulse()
	if (clock_c > 0) then
		clock_c = clock_c - 1;
		if (clock_c == 0) then
			reset_image_transform(a);
		end
	end
#endif
end
