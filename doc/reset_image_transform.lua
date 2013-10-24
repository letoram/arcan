-- reset_image_transform
-- @short: Drop all ongoing transformations. 
-- @inargs: vid
-- @longdescr: At times there may be queued events that should be
-- cancelled out due to unforeseen changes, this is especially typical
-- when transformations are initated as part as some input event handler,
-- like pushing a button to move a cursor indicating a selected item. To
-- prevent these from stacking up, reset_image_transformation can first 
-- be called to make sure that the transformation queue is empty.
-- @note: this will not revert the object back to a previous state,
-- but rather stop at whatever part of the chain was currently being processed.
-- @group: image 
-- @cfunction: arcan_lua_resettransform
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
