function seg2(source, segv)
	print("in new segment");	
end

function segtest()
	local test = launch_avfeed("", function(source, status)
		if (status.kind == "segment_request") then
			print(source, type(source));
			newvid, newaid, key = target_alloc(source, seg2);
			print("target_alloc():", newvid, newaid, key);
			resize_image(newvid, VRESW * 0.5, VRESH);
			move_image(newvid, 1);
			show_image(newvid);
		end
	end);

	show_image(test);
	resize_image(test, VRESW * 0.5, VRESH);
end

function segtest_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then
		target_input(newvid, iotbl);
	end
end
