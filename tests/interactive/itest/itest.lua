-- test the two different kinds of externally provided
-- input injection, combine with the tests/frameservers/ioinject
-- with the ARCAN_CONNPATH set to the desired route.

function itest()
	target_alloc("itest", function(source, status, iotbl)
		if (status.kind == "input") then
			print("frameserver input");
			for k,v in pairs(iotbl) do
				print(k, v);
			end
		end
	end);
	local vid = target_alloc("itest2", function(source, status)
	end);
	target_flags(vid, TARGET_ALLOWINPUT);
end

function itest_input(iotbl)
	print("platform input:")
	for k,v in pairs(iotbl) do
		print(k, v);
	end
end
