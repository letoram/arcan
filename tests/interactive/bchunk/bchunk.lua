function bchunk(args)
	local output = (args[1] and args[1] == "out");

	con = target_alloc("bchunk",
	function(source, status)
		print(status.kind)
		if (status.kind == "resized") then
			if (output) then
				pipe_out = open_nonblock(con, true);
			else
				pipe_in = open_nonblock(con, false);
			end
		elseif (status.kind == "terminated") then
			delete_image(source);
		end
	end);
end

counter = 1;
function bchunk_clock_pulse()
	if (not valid_vid(con, TYPE_FRAMESERVER)) then
		return shutdown("broken pipe");
	end

	if (pipe_in) then
	local line = pipe_in:read();
	if (line) then
		print("read: ", line);
	end
	end

-- purposely ignore shortwrite
	if (pipe_out) then
	line = string.format("%d\n", counter);
	if (pipe_out:write(line) > 0) then
		counter = counter + 1;
	end
	end
end
