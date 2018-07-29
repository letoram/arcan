--
-- script for testing the explicit resize mode
-- use the 'counter' test frameserver along with the 'cp'
-- connpoint as it resizes regularly.
--
-- The correct behavior here is that the client will request a new size,
-- no statusframes or other events will occur during the block yet the
-- size will not match the store.
--
-- Then after 100 ticks, the store after step message comes and should
-- reflect the new request client size. This is a contrived use-case,
--
-- a more common (think animations) would be to resample the backing
-- store into a temporary buffer and then acknowledge the resize.
--
local counter = 0;

function test_synch()
	vid = target_alloc("cp", function(source, status)
		if (status.kind == "preroll") then
		elseif (status.kind == "resized") then
			counter = 100;
			local props = image_storage_properties(source);
			print("Request:", status.width, status.height, "Store:", props.width, props.height);
		else
			for k,v in pairs(status) do print(k, v); end
			print("=====")
		end
	end);
	target_flags(vid, TARGET_SYNCHSIZE);
	target_verbose(vid);
	show_image(vid);
end

function test_synch_clock_pulse()
	if (counter > 0) then
		counter = counter - 1;
		print("resize ack in", counter);
		if (counter == 0) then
			stepframe_target(vid, 0);
			local props = image_storage_properties(vid);
			resize_image(vid, props.width, props.height);
			print("STORE AFTER STEP", props.width, props.height);
		end
	end
end
