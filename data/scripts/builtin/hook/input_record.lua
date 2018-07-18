--
-- No Copyright Claimed, Public Domain
--

--
-- This hook-script creates a hook for the regular
-- _input function and records input tables along
-- with their respective clock time.
--
-- It is only intended to be used to drive test-
-- and benchmark cases that rely on input and timing,
-- hence the limited serialization format.
--

if (true) then
	local fname = APPLID .. ".irec";
	local baseclock = 0; -- don't have access to CLOCK at this stage

	zap_resource(fname);
	local output_file = open_nonblock(fname, 1);
--
-- this will essentially turn the output into blocking..
--
	local dump_block = function(str)
		local nw = 0;

		while (nw < #str) do
			local substr = string.sub(str, nw+1, #str);
			nw = nw + output_file:write(substr);
		end
	end

	if (output_file ~= nil) then
		local forward_function = _G[APPLID .. "_input"];
		_G[APPLID .. "_input"] = function(iotbl)
			if (baseclock == 0) then
				baseclock = CLOCK;
			end
			if (iotbl.kind == "digital") then
				if (iotbl.translated) then
					dump_block(string.format("%d:key:%d:%d:%d:%d:%d\n",
						CLOCK-baseclock, iotbl.devid, iotbl.subid, iotbl.modifiers,
						iotbl.keysym, iotbl.active and 1 or 0));
				else
					dump_block(string.format("%d:btn:%d:%d:%d\n",
						CLOCK-baseclock, iotbl.devid,
						iotbl.subid, iotbl.active and 1 or 0)
					);
				end
			elseif (iotbl.kind == "analog" and iotbl.source) then
				dump_block(string.format("%d:mouse:%d:%d:%d:%d\n",
					CLOCK-baseclock, iotbl.devid, iotbl.subid, iotbl.samples[1],
					iotbl.samples[2] ~= nil and iotbl.samples[2] or 0));

			end
			forward_function(iotbl);
		end
	else
		warning("hookscript:input_record(), failed to open " .. fname);
	end

end
