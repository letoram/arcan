function seg2(source, status)
	print("secondary segment event:", status.kind);

	if (status.kind == "resized") then
		resize_image(newvid, VRESW * 0.5, VRESH);
		move_image(newvid, VRESW * 0.5, 0);
		show_image(newvid);
	end
end

function segtest()
	symtable = system_load("builtin/keyboard.lua")();

	test = launch_avfeed("", "avfeed", function(source, status)
		print(status.kind);
		if (status.kind == "segment_request") then
			print(source, type(source));
			newvid, newaid, key = target_alloc(source, seg2);
			print("target_alloc():", newvid, newaid, key);

		elseif(status.kind == "resized") then
			show_image(source);
			resize_image(source, VRESW * 0.5, VRESH);
		end
	end);

	show_image(test);
	resize_image(test, VRESW * 0.5, VRESH);
end

function segtest_input(iotbl)
	if (iotbl.kind == "digital" and iotbl.active) then
		local label = symtable.tolabel(iotbl.keysym)
		if (label == "F10") then
			print("dropping main seg");
			delete_image(test);
		elseif(label == "F9") then
			print("dropping alt seg");
			delete_image(newvid);
		elseif (label == "F8") then
			target_alloc("mykey", seg2);
		else
			print("input to:", newvid);
			target_input(newvid, iotbl);
			target_input(test, iotbl);
		end
	end
end
